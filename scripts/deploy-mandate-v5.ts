import "dotenv/config";
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import {
  createPublicClient, createWalletClient, http, formatEther, parseEther,
  encodeFunctionData, decodeEventLog, type Hex, type Address,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { baseSepolia } from "viem/chains";

/**
 * Déploie InheritableAgentMandateV5 sur Base Sepolia et exerce la REPRISE.
 *
 * V1, V2 et V3 restent en chaîne et ne sont pas touchés. TESTNET UNIQUEMENT ;
 * la clé n'est jamais imprimée. Aucun résultat n'est écrit en dur comme attendu :
 * chaque appel part, et son issue réelle est imprimée puis consignée.
 */
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const art = JSON.parse(readFileSync(resolve(root, "build/InheritableAgentMandateV5.json"), "utf8"));
const abi = art.abi;

const account = privateKeyToAccount(process.env.PRIVATE_KEY as Hex);
const rpcUrl = process.env.RPC_URL ?? "https://sepolia.base.org";
const pub = createPublicClient({ chain: baseSepolia, transport: http(rpcUrl) });
const wallet = createWalletClient({ account, chain: baseSepolia, transport: http(rpcUrl) });

const chainId = await pub.getChainId();
if (chainId !== baseSepolia.id) throw new Error(`Mauvaise chaîne : ${chainId}`);

const PAYEE = "0x000000000000000000000000000000000000dEaD" as Address;
const out: any = { network: "base-sepolia", chainId, deployer: account.address, steps: {} };

console.log("déployeur :", account.address);
console.log("solde     :", formatEther(await pub.getBalance({ address: account.address })), "ETH\n");

const deployHash = await wallet.deployContract({ abi, bytecode: art.bytecode as Hex, args: [account.address] });
console.log("tx déploiement :", deployHash);
const dr = await pub.waitForTransactionReceipt({ hash: deployHash });
if (dr.status !== "success" || !dr.contractAddress) throw new Error("déploiement échoué");
const C = dr.contractAddress as Address;
console.log("✅ adresse :", C, "· bloc", dr.blockNumber, "· gaz", dr.gasUsed);
out.address = C; out.deployTx = deployHash;
out.blockNumber = dr.blockNumber.toString(); out.deployGas = dr.gasUsed.toString();

async function waitVisible(check: () => Promise<boolean>, tries = 40) {
  for (let i = 0; i < tries; i++) {
    try { if (await check()) return; } catch {}
    await new Promise((r) => setTimeout(r, 2000));
  }
  throw new Error("état jamais visible");
}
await waitVisible(async () => {
  const code = await pub.getCode({ address: C });
  return !!code && code !== "0x";
});
out.codeSize = ((await pub.getCode({ address: C }))!.length - 2) / 2;
console.log("   taille du code :", out.codeSize, "octets");

const read = (fn: string, args: any[]) =>
  pub.readContract({ address: C, abi, functionName: fn, args }) as Promise<any>;
const now = async () => (await pub.getBlock()).timestamp;

const M = (cap: string, start: bigint, len: number, count: number, tel: number) => ({
  maxSpendWei: parseEther(cap), periodStart: start, periodLength: len,
  periodCount: count, telomere: tel, requireLease: true, frozen: false,
});

/** Envoie sans simulation : une tentative qui échoue DOIT atterrir dans un bloc. */
async function attempt(label: string, fn: string, args: any[], gas = 400_000n) {
  const data = encodeFunctionData({ abi, functionName: fn, args });
  const h = await wallet.sendTransaction({ to: C, data, gas });
  const rc = await pub.waitForTransactionReceipt({ hash: h });
  console.log(`   ${label} → ${rc.status}  tx ${h}`);
  return { label, tx: h, status: rc.status, block: rc.blockNumber.toString() };
}
/** Écrit, PUIS attend que l'écriture soit visible en lecture avant de rendre la main.
 *  Sans cette attente, l'appel suivant est estimé contre un nœud qui n'a pas encore vu
 *  celui-ci et échoue pour une raison qui n'a rien à voir avec le contrat. */
async function send(fn: string, args: any[], evt?: string, key?: string,
                    check?: (id: bigint) => Promise<boolean>) {
  const h = await wallet.writeContract({ address: C, abi, functionName: fn, args });
  const rc = await pub.waitForTransactionReceipt({ hash: h });
  if (rc.status !== "success") throw new Error(`${fn} échoué : ${h}`);
  let id = 0n;
  if (evt) for (const log of rc.logs) {
    try {
      const d: any = decodeEventLog({ abi, data: log.data, topics: log.topics });
      if (d.eventName === evt) id = d.args[key!] as bigint;
    } catch {}
  }
  if (check) await waitVisible(() => check(id));
  return { id, tx: h, gas: rc.gasUsed };
}
const ZERO = "0x0000000000000000000000000000000000000000";
const vuMint = async (id: bigint) => (await read("ownerOf", [id])) !== ZERO;
const vuSpawn = (parent: bigint) => async (id: bigint) => (await read("parentOf", [id])) === parent;
const eth = (v: bigint) => formatEther(v) + " ETH";

// ═══════════════════════════════ 1. le gel ouvre la reprise ════════════════
console.log("\n── 1. l'enfant est gelé, sa tranche revient au parent ──");
let t = await now();
const p1 = await send("mint", [account.address, M("100", t, 3600, 24, 3), [PAYEE]], "Minted", "id", vuMint);
console.log("   parent agentId :", p1.id, "· budget libre :", eth(await read("availableBudget", [p1.id])));
const c1 = await send("spawn", [p1.id, account.address, M("40", t, 3600, 24, 2), [PAYEE]], "Spawned", "childId", vuSpawn(p1.id));
console.log("   enfant agentId :", c1.id, "· budget libre du parent :", eth(await read("availableBudget", [p1.id])));

const rootAvant = await read("mandateRoot", [c1.id]);
const fr = await send("freeze", [c1.id]);
await waitVisible(async () => (await read("isDead", [c1.id])) === true);
console.log("   gel tx :", fr.tx);
console.log("   isDead(enfant) :", await read("isDead", [c1.id]),
            "· reprenable :", eth(await read("reclaimableOf", [c1.id])));

const rc1 = await send("reclaim", [c1.id]);
await waitVisible(async () => (await read("reclaimed", [c1.id])) === true);
console.log("   reprise tx :", rc1.tx, "· gaz :", rc1.gas);
console.log("   budget libre du parent APRÈS :", eth(await read("availableBudget", [p1.id])));
const rootApres = await read("mandateRoot", [c1.id]);
console.log("   mandateRoot de l'enfant inchangée :", rootAvant === rootApres);
out.steps.gel = {
  parent: p1.id.toString(), parentTx: p1.tx, child: c1.id.toString(), childTx: c1.tx,
  freezeTx: fr.tx, reclaimTx: rc1.tx, reclaimGas: rc1.gas.toString(),
  budgetApres: (await read("availableBudget", [p1.id])).toString(),
  rootAvant, rootApres, identiteIntacte: rootAvant === rootApres,
};

// ═══════════════════════════════ 2. le refus qui compte ════════════════════
console.log("\n── 2. un enfant VIVANT sous un parent gelé n'est pas reprenable ──");
t = await now();
const p2 = await send("mint", [account.address, M("100", t, 3600, 24, 3), [PAYEE]], "Minted", "id", vuMint);
const c2 = await send("spawn", [p2.id, account.address, M("40", t, 3600, 24, 2), [PAYEE]], "Spawned", "childId", vuSpawn(p2.id));
await send("freeze", [p2.id]);
await waitVisible(async () => (await read("isActive", [c2.id])) === false);
console.log("   isActive(enfant) :", await read("isActive", [c2.id]),
            "· isDead(enfant) :", await read("isDead", [c2.id]),
            "· reprenable :", eth(await read("reclaimableOf", [c2.id])));
const refus = await attempt("reclaim sur un enfant vivant", "reclaim", [c2.id]);
out.steps.refus = { parent: p2.id.toString(), child: c2.id.toString(), ...refus,
  isActive: await read("isActive", [c2.id]), isDead: await read("isDead", [c2.id]) };

// ═══════════════════════════════ 3. l'horloge, sans personne ═══════════════
console.log("\n── 3. l'enfant expire tout seul, personne n'intervient ──");
t = await now();
const p3 = await send("mint", [account.address, M("100", t, 3600, 24, 3), [PAYEE]], "Minted", "id", vuMint);
const c3 = await send("spawn", [p3.id, account.address, M("40", t, 60, 1, 2), [PAYEE]], "Spawned", "childId", vuSpawn(p3.id));
console.log("   enfant agentId", c3.id, "· bail d'UNE période de 60 s");
console.log("   isDead immédiat :", await read("isDead", [c3.id]));
console.log("   attente de l'échéance…");
let mort = false, waited = 0;
while (waited < 240) {
  await new Promise((r) => setTimeout(r, 15_000));
  waited += 15;
  mort = await read("isDead", [c3.id]);
  const bt = await now();
  console.log(`   t = +${bt - t} s · isDead : ${mort}`);
  if (mort) break;
}
if (mort) {
  const rc3 = await send("reclaim", [c3.id]);
  await waitVisible(async () => (await read("reclaimed", [c3.id])) === true);
  console.log("   reprise tx :", rc3.tx);
  console.log("   budget libre du parent :", eth(await read("availableBudget", [p3.id])));
  out.steps.horloge = { parent: p3.id.toString(), child: c3.id.toString(),
    childTx: c3.tx, reclaimTx: rc3.tx, attenduSecondes: waited,
    budgetApres: (await read("availableBudget", [p3.id])).toString() };
} else {
  out.steps.horloge = { child: c3.id.toString(), childTx: c3.tx, note: "échéance non atteinte dans la fenêtre d'attente" };
}

console.log("\nsolde restant :", formatEther(await pub.getBalance({ address: account.address })), "ETH");
mkdirSync(resolve(root, "build"), { recursive: true });
writeFileSync(resolve(root, "build/v5-reprise.json"),
  JSON.stringify(out, (_, v) => (typeof v === "bigint" ? v.toString() : v), 2));
console.log("→ build/v5-reprise.json");
