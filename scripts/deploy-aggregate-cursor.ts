import "dotenv/config";
import { readFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import {
  createPublicClient, createWalletClient, http, formatEther, parseEther,
  type Hex, type Address,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { baseSepolia } from "viem/chains";

/**
 * Déploie MandateAwareAggregateCursor sur Base Sepolia et l'exerce.
 *
 * TESTNET UNIQUEMENT. La clé n'est jamais imprimée. Aucun résultat n'est écrit
 * en dur : chaque appel part, et son issue réelle est imprimée.
 *
 * Le scénario rejoue N1 de TEST-SECTION5.md — prouvé jusqu'ici en local
 * seulement — pour rendre la conservation de lignée constatable sur la chaîne :
 * une racine, deux enfants, un petit-enfant, et le tirage qui dépasse le
 * plafond de la RACINE doit reverter, quelle que soit la profondeur.
 *
 * C'est le cas exact que le mandat V3 laisse passer (racine 100 → lignée 300,
 * mesuré le 14/08) : ici le compteur est unique, donc la profondeur ne
 * multiplie rien.
 *
 * Adossé à InheritableAgentMandateV3 déjà déployé, qui n'est ni touché ni
 * redéployé.
 */
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const art = JSON.parse(readFileSync(resolve(root, "build/MandateAwareAggregateCursor.json"), "utf8"));
const abi = art.abi;

const MANDATE_V3 = "0xfd786e6dda41faea07c45948114d497b0f39f32b" as Address;

const account = privateKeyToAccount(process.env.PRIVATE_KEY as Hex);
const rpcUrl = process.env.RPC_URL ?? "https://sepolia.base.org";
const pub = createPublicClient({ chain: baseSepolia, transport: http(rpcUrl) });
const wallet = createWalletClient({ account, chain: baseSepolia, transport: http(rpcUrl) });

const chainId = await pub.getChainId();
if (chainId !== baseSepolia.id) throw new Error(`REFUS — mauvaise chaîne : ${chainId}`);

console.log("déployeur :", account.address);
console.log("solde     :", formatEther(await pub.getBalance({ address: account.address })), "ETH");
console.log("mandat    :", MANDATE_V3, "(inchangé)\n");

// ─────────────────────────────────────────────────────────────── déploiement
const deployHash = await wallet.deployContract({
  abi, bytecode: art.bytecode as Hex, args: [MANDATE_V3],
});
console.log("tx déploiement :", deployHash);
const dr = await pub.waitForTransactionReceipt({ hash: deployHash });
if (dr.status !== "success" || !dr.contractAddress) throw new Error("déploiement échoué");
const C = dr.contractAddress as Address;
console.log("✅ adresse :", C);
console.log("   bloc :", dr.blockNumber, "· gaz :", dr.gasUsed, "\n");

const write = async (fn: string, args: any[]) => {
  const h = await wallet.writeContract({ address: C, abi, functionName: fn, args });
  const r = await pub.waitForTransactionReceipt({ hash: h });
  return { hash: h, status: r.status };
};
const read = (fn: string, args: any[] = []) =>
  pub.readContract({ address: C, abi, functionName: fn, args }) as Promise<any>;

// ────────────────────────────────────── N1 sur la chaîne : compteur de racine
// Une seule adresse joue tous les nœuds : ce qu'on mesure ici est le compteur
// de racine, pas le contrôle d'appelant — déjà couvert en local.
const AGENT = account.address;
const CAP = parseEther("100");
const PERIOD = 86_400n;
const SALT = ("0x" + "a9".repeat(32)) as Hex;

const rootId = (await read("computeRootId", [account.address, AGENT, SALT])) as Hex;
console.log("── racine : cap 100 ETH, période 1 jour ──");
console.log("   rootId :", rootId);
const rc = await write("createRoot", [AGENT, CAP, PERIOD, 0n, SALT]);
console.log("   createRoot :", rc.status, "·", rc.hash);

// deux enfants de la racine (nœud 0), puis un petit-enfant plafonné à 30
const d1 = await write("delegate", [rootId, 0n, AGENT, parseEther("60")]);
console.log("   delegate enfant 1 (cap 60) :", d1.status);
const d2 = await write("delegate", [rootId, 0n, AGENT, parseEther("60")]);
console.log("   delegate enfant 2 (cap 60) :", d2.status);
const d3 = await write("delegate", [rootId, 1n, AGENT, parseEther("30")]);
console.log("   delegate petit-enfant de #1 (cap 30) :", d3.status, "\n");

// tirages : 40 (enfant 1) + 20 (enfant 2) + 25 (petit-enfant) = 85 ≤ 100
console.log("── tirages ──");
for (const [node, amt] of [[1n, "40"], [2n, "20"], [3n, "25"]] as const) {
  const r = await write("draw", [rootId, node, parseEther(amt)]);
  const period = await read("currentPeriod", [rootId]);
  const spent = await read("spentRoot", [rootId, period]);
  console.log(`   nœud ${node} tire ${amt} ETH → ${r.status} · spentRoot ${formatEther(spent)} ETH`);
}
console.log("   remainingRoot :", formatEther(await read("remainingRoot", [rootId])), "ETH\n");

// le tirage de trop : 20 de plus ferait 105 > 100. Profondeur 2, plafond de
// nœud à 30 non atteint (25 tirés) — seul le compteur de RACINE doit mordre.
console.log("── le tirage de trop : petit-enfant, 20 ETH (total 105) ──");
let refus = "PASSÉ — le compteur de racine n'a pas mordu";
try {
  const r = await write("draw", [rootId, 3n, parseEther("20")]);
  refus = `PASSÉ (status ${r.status}) · ${r.hash}`;
} catch (e: any) {
  const m = String(e?.shortMessage ?? e?.message ?? e);
  refus = "REFUSÉ — " + (m.match(/RootCapExceeded|reverted[^\n]*/)?.[0] ?? m.slice(0, 120));
}
console.log("   →", refus);

const period = await read("currentPeriod", [rootId]);
console.log("   spentRoot après :", formatEther(await read("spentRoot", [rootId, period])), "ETH (doit être 85)");
console.log("   remainingRoot   :", formatEther(await read("remainingRoot", [rootId])), "ETH");

console.log("\n── conformité ──");
for (const id of ["0xc7cabe86", "0x01ffc9a7", "0xffffffff", "0xdeadbeef"]) {
  console.log(`   supportsInterface(${id}) :`, await read("supportsInterface", [id]));
}
console.log("   mandate() :", await read("mandate"));

export {};
