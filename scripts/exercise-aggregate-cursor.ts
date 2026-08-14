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
 * Exerce MandateAwareAggregateCursor DÉJÀ DÉPLOYÉ. Ne redéploie rien.
 *
 * Rejoue N1 de TEST-SECTION5.md, jusqu'ici prouvé en local seulement, pour que
 * la conservation de lignée soit constatable sur la chaîne : une racine, deux
 * enfants, un petit-enfant, et le tirage qui dépasse le plafond de la RACINE
 * doit reverter quelle que soit la profondeur.
 *
 * C'est le cas exact que le mandat V3 laisse passer (racine 100 → lignée 300,
 * mesuré le 14/08) : ici le compteur est unique, donc la profondeur ne
 * multiplie rien.
 *
 * TESTNET UNIQUEMENT. La clé n'est jamais imprimée. Rien n'est écrit en dur
 * comme résultat attendu.
 */
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const art = JSON.parse(readFileSync(resolve(root, "build/MandateAwareAggregateCursor.json"), "utf8"));
const abi = art.abi;

const C = "0x839542d75e5846227ea2a9b685a9afd1a1563b6e" as Address;

const account = privateKeyToAccount(process.env.PRIVATE_KEY as Hex);
const rpcUrl = process.env.RPC_URL ?? "https://sepolia.base.org";
const pub = createPublicClient({ chain: baseSepolia, transport: http(rpcUrl) });
const wallet = createWalletClient({ account, chain: baseSepolia, transport: http(rpcUrl) });

const chainId = await pub.getChainId();
if (chainId !== baseSepolia.id) throw new Error(`REFUS — mauvaise chaîne : ${chainId}`);

// Le RPC public accuse un retard lecture-après-écriture : une écriture qui
// dépend de la précédente part avant que le noeud ne l'ait vue. On laisse
// respirer entre deux écritures plutôt que d'inventer un bug de contrat.
const settle = () => new Promise((r) => setTimeout(r, 2500));
const write = async (fn: string, args: any[]) => {
  const h = await wallet.writeContract({ address: C, abi, functionName: fn, args });
  const r = await pub.waitForTransactionReceipt({ hash: h });
  await settle();
  return { hash: h, status: r.status };
};
const read = (fn: string, args: any[] = []) =>
  pub.readContract({ address: C, abi, functionName: fn, args }) as Promise<any>;

console.log("curseur :", C);
console.log("mandat  :", await read("mandate"), "(inchangé)");
console.log("compte  :", account.address);
console.log("solde   :", formatEther(await pub.getBalance({ address: account.address })), "ETH\n");

const AGENT = account.address;
const CAP = parseEther("100");
const PERIOD = 86_400n;
const SALT = ("0x" + "b7".repeat(32)) as Hex;

const rootId = (await read("computeRootId", [account.address, AGENT, SALT])) as Hex;
console.log("── racine : cap 100 ETH, période 1 jour ──");
console.log("   rootId :", rootId);
const rExist = (await read("rootOf", [rootId]))[0] as Address;
if (rExist === "0x0000000000000000000000000000000000000000") {
  console.log("   createRoot :", (await write("createRoot", [AGENT, CAP, PERIOD, 0n, SALT])).status);
} else {
  console.log("   racine déjà en place · nœuds existants :", (await read("rootOf", [rootId]))[4]);
}

// nodeCap 0 = non plafonné, donc autorisé à déléguer ; un nœud plafonné est une feuille.
if ((await read("rootOf", [rootId]))[4] < 2n) console.log("   delegate enfant 1 (non plafonné) :", (await write("delegate", [rootId, 0n, AGENT, 0n])).status);
if ((await read("rootOf", [rootId]))[4] < 3n) console.log("   delegate enfant 2 (non plafonné) :", (await write("delegate", [rootId, 0n, AGENT, 0n])).status);
if ((await read("rootOf", [rootId]))[4] < 4n) console.log("   delegate petit-enfant de #1 (cap 100) :", (await write("delegate", [rootId, 1n, AGENT, parseEther("100")])).status);
console.log("   nœuds au total :", (await read("rootOf", [rootId]))[4], "\n");

console.log("── tirages : 40 + 20 + 25 = 85 ≤ 100 ──");
for (const [node, amt] of [[1n, "40"], [2n, "20"], [3n, "25"]] as const) {
  const r = await write("draw", [rootId, node, parseEther(amt)]);
  const p = await read("currentPeriod", [rootId]);
  console.log(`   nœud ${node} tire ${amt} → ${r.status} · spentRoot ${formatEther(await read("spentRoot", [rootId, p]))} ETH`);
}
console.log("   remainingRoot :", formatEther(await read("remainingRoot", [rootId])), "ETH\n");

// Le petit-enfant est à la profondeur 2, plafonné à 100 dont 25 tirés : SON
// plafond autorise largement 20 de plus. Seul le compteur de RACINE peut
// refuser — 85 + 20 = 105 > 100. C'est le cas exact que le mandat V3 laisse
// passer, et il doit échouer ici.
console.log("── le tirage de trop : petit-enfant (profondeur 2), 20 ETH ──");
console.log("   son plafond local :", formatEther((await read("nodeOf", [rootId, 3n]))[4]), "ETH · déjà tiré 25 → local OK");
try {
  const r = await write("draw", [rootId, 3n, parseEther("20")]);
  console.log("   → PASSÉ (status", r.status + ") ·", r.hash, "— le compteur de racine n'a pas mordu");
} catch (e: any) {
  const m = String(e?.shortMessage ?? e?.message ?? e);
  console.log("   → REFUSÉ —", m.match(/RootCapExceeded|reverted[^\n]*/)?.[0] ?? m.slice(0, 140));
}

const p = await read("currentPeriod", [rootId]);
console.log("   spentRoot après :", formatEther(await read("spentRoot", [rootId, p])), "ETH");
console.log("   remainingRoot   :", formatEther(await read("remainingRoot", [rootId])), "ETH");

console.log("\n── conformité ERC-165 ──");
for (const id of ["0xc7cabe86", "0x01ffc9a7", "0xffffffff", "0xdeadbeef"]) {
  console.log(`   supportsInterface(${id}) :`, await read("supportsInterface", [id]));
}

export {};
