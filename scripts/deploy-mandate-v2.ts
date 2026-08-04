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
 * Phase B — déploie InheritableAgentMandateV2 sur Base Sepolia et l'exerce.
 *
 * v1 (0x2d463db5…) n'est ni touché ni redéployé. TESTNET UNIQUEMENT ; la clé
 * n'est jamais imprimée. Rien n'est écrit en dur comme résultat attendu : chaque
 * appel est envoyé, et son issue réelle est imprimée puis consignée.
 */
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const art = JSON.parse(readFileSync(resolve(root, "build/InheritableAgentMandateV2.json"), "utf8"));
const abi = art.abi;

const account = privateKeyToAccount(process.env.PRIVATE_KEY as Hex);
const rpcUrl = process.env.RPC_URL ?? "https://sepolia.base.org";
const pub = createPublicClient({ chain: baseSepolia, transport: http(rpcUrl) });
const wallet = createWalletClient({ account, chain: baseSepolia, transport: http(rpcUrl) });

const chainId = await pub.getChainId();
if (chainId !== baseSepolia.id) throw new Error(`Mauvaise chaîne : ${chainId}`);

const PAYEE = "0x000000000000000000000000000000000000dEaD" as Address;
const CAP = parseEther("100");
const out: any = { network: "base-sepolia", chainId, deployer: account.address, steps: {} };

console.log("déployeur :", account.address);
console.log("solde     :", formatEther(await pub.getBalance({ address: account.address })), "ETH\n");

// ───────────────────────────────────────────────────────────── déploiement
const deployHash = await wallet.deployContract({ abi, bytecode: art.bytecode as Hex, args: [account.address] });
console.log("tx déploiement :", deployHash);
const dr = await pub.waitForTransactionReceipt({ hash: deployHash });
if (dr.status !== "success" || !dr.contractAddress) throw new Error("déploiement échoué");
const C = dr.contractAddress as Address;
console.log("✅ adresse :", C);
console.log("   bloc :", dr.blockNumber, "· gaz :", dr.gasUsed);
out.address = C;
out.deployTx = deployHash;
out.blockNumber = dr.blockNumber.toString();
out.deployGas = dr.gasUsed.toString();

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
const codeSize = ((await pub.getCode({ address: C }))!.length - 2) / 2;
console.log("   taille du code déployé :", codeSize, "octets");
out.codeSize = codeSize;

// ───────────────────────────────────────────────────────────── helpers
const read = (fn: string, args: any[]) =>
  pub.readContract({ address: C, abi, functionName: fn, args }) as Promise<any>;

/** Envoie une tx sans simulation préalable : une tentative qui échoue DOIT
 *  atterrir dans un bloc pour être citable. */
async function attempt(label: string, fn: string, args: any[], gas = 400_000n) {
  const data = encodeFunctionData({ abi, functionName: fn, args });
  const h = await wallet.sendTransaction({ to: C, data, gas });
  const rc = await pub.waitForTransactionReceipt({ hash: h });
  console.log(`   ${label} → ${rc.status}  tx ${h}`);
  return { label, tx: h, status: rc.status, block: rc.blockNumber.toString() };
}

async function mintNode(tel: number, validUntil: bigint) {
  const h = await wallet.writeContract({
    address: C, abi, functionName: "mint",
    args: [account.address, { maxSpendWei: CAP, validUntil, telomere: tel, requireLease: true, frozen: false }, [PAYEE]],
  });
  const rc = await pub.waitForTransactionReceipt({ hash: h });
  if (rc.status !== "success") throw new Error(`mint échoué: ${h}`);
  let id = 0n;
  for (const log of rc.logs) {
    try {
      const d: any = decodeEventLog({ abi, data: log.data, topics: log.topics });
      if (d.eventName === "Minted") id = d.args.id as bigint;
    } catch {}
  }
  if (!id) throw new Error("Minted introuvable");
  await waitVisible(async () => (await read("ownerOf", [id])) !== "0x0000000000000000000000000000000000000000");
  return { id, tx: h };
}

async function spawnNode(parent: bigint, tel: number, validUntil: bigint) {
  const h = await wallet.writeContract({
    address: C, abi, functionName: "spawn",
    args: [parent, account.address, { maxSpendWei: CAP, validUntil, telomere: tel, requireLease: true, frozen: false }, [PAYEE]],
  });
  const rc = await pub.waitForTransactionReceipt({ hash: h });
  if (rc.status !== "success") throw new Error(`spawn échoué: ${h}`);
  let id = 0n;
  for (const log of rc.logs) {
    try {
      const d: any = decodeEventLog({ abi, data: log.data, topics: log.topics });
      if (d.eventName === "Spawned") id = d.args.childId as bigint;
    } catch {}
  }
  if (!id) throw new Error("Spawned introuvable");
  await waitVisible(async () => (await read("parentOf", [id])) === parent);
  return { id, tx: h };
}

async function freeze(id: bigint) {
  const h = await wallet.writeContract({ address: C, abi, functionName: "freeze", args: [id] });
  const rc = await pub.waitForTransactionReceipt({ hash: h });
  console.log(`   freeze(${id}) → ${rc.status}  tx ${h}`);
  await waitVisible(async () => (await read("mandateOf", [id]))[4] === true);
  return { tx: h, status: rc.status };
}

const now = async () => (await pub.getBlock()).timestamp;

// ═════════════════════════════════════════════ 1. chaîne A — cascade génésis
console.log("\n── 1. chaîne A : 16 générations, sans expiration ──");
const A: bigint[] = [];
const aTx: string[] = [];
{
  const g = await mintNode(40, 0n);
  A.push(g.id); aTx.push(g.tx);
  console.log("   génésis agentId :", g.id);
  for (let i = 1; i <= 16; i++) {
    const s = await spawnNode(A[i - 1]!, 40 - i, 0n);
    A.push(s.id); aTx.push(s.tx);
    if (i % 4 === 0) console.log(`   profondeur ${i} → agentId ${s.id}`);
  }
}
const deepest = A[16]!;
out.steps.chainA = { ids: A.map(String), txs: aTx, depth: 16 };

// gaz de isActive AVANT tout gel (la marche va jusqu'à la racine dans les deux cas)
console.log("\n── 2. gaz réel de isActive, avant gel ──");
const gasRows: any[] = [];
for (const d of [1, 4, 8, 16]) {
  const data = encodeFunctionData({ abi, functionName: "isActive", args: [A[d]!] });
  const g = await pub.estimateGas({ account: account.address, to: C, data });
  const v = await read("isActive", [A[d]!]);
  console.log(`   profondeur ${String(d).padStart(2)} · agentId ${A[d]} · estimateGas ${g} · isActive ${v}`);
  gasRows.push({ depth: d, agentId: A[d]!.toString(), gas: g.toString(), isActive: v });
}
out.steps.gas = gasRows;

console.log("\n── 3. cascade : gel du génésis ──");
console.log("   avant gel · isActive(profondeur 16) :", await read("isActive", [deepest]));
const frA = await freeze(A[0]!);
const afterFreeze = await read("isActive", [deepest]);
console.log("   après gel · isActive(profondeur 16) :", afterFreeze);
const spot: any = {};
for (const d of [1, 8, 15, 16]) spot[d] = await read("isActive", [A[d]!]);
console.log("   sondes après gel :", JSON.stringify(spot));
out.steps.cascade = { freezeTx: frA.tx, deepest: deepest.toString(), afterFreeze, spot };

// ═════════════════════════════════════════════ 4. chaîne B — direction
console.log("\n── 4. chaîne B : 9 générations, gel d'un ancêtre du milieu ──");
const B: bigint[] = [];
const bTx: string[] = [];
{
  const g = await mintNode(20, 0n);
  B.push(g.id); bTx.push(g.tx);
  for (let i = 1; i <= 8; i++) {
    const s = await spawnNode(B[i - 1]!, 20 - i, 0n);
    B.push(s.id); bTx.push(s.tx);
  }
  console.log("   agentIds :", B.map(String).join(" → "));
}
const beforeB: any = {};
for (const d of [2, 4, 6, 8]) beforeB[d] = await read("isActive", [B[d]!]);
console.log("   avant gel :", JSON.stringify(beforeB));
const frB = await freeze(B[4]!);
const afterB: any = {};
for (const d of [0, 2, 3, 4, 5, 6, 8]) afterB[d] = await read("isActive", [B[d]!]);
console.log("   après gel(profondeur 4) :", JSON.stringify(afterB));
out.steps.direction = { ids: B.map(String), txs: bTx, freezeTx: frB.tx, frozenDepth: 4, before: beforeB, after: afterB };

// ═════════════════════════════════════════════ 5. validUntil
console.log("\n── 5. validUntil : refus on-chain ──");
const t0 = await now();
console.log("   timestamp de chaîne :", t0);
const P = await mintNode(5, t0 + 3600n);
console.log("   parent agentId", P.id, "· validUntil = t0 + 3600");
const refus = [
  await attempt("enfant à t0+7200 (plus tard que le parent)", "spawn",
    [P.id, account.address, { maxSpendWei: CAP, validUntil: t0 + 7200n, telomere: 4, requireLease: true, frozen: false }, [PAYEE]]),
  await attempt("enfant à 0 (retrait de l'expiration héritée)", "spawn",
    [P.id, account.address, { maxSpendWei: CAP, validUntil: 0n, telomere: 4, requireLease: true, frozen: false }, [PAYEE]]),
];
const okChild = await spawnNode(P.id, 4, t0 + 1800n);
console.log("   enfant à t0+1800 (resserrement) → success  tx", okChild.tx);
out.steps.validUntilRefus = { parent: P.id.toString(), parentTx: P.tx, t0: t0.toString(), refus, okChild: { id: okChild.id.toString(), tx: okChild.tx } };

console.log("\n── 6. validUntil : un nœud expire vraiment avec le temps ──");
const tNow = await now();
const E = await mintNode(3, tNow + 90n);
console.log("   agentId", E.id, "· validUntil = maintenant + 90 s");
console.log("   isActive immédiat :", await read("isActive", [E.id]));
const past = await mintNode(3, tNow - 1n);
console.log("   contrôle : agentId", past.id, "· validUntil déjà dépassé →", await read("isActive", [past.id]));
console.log("   attente de l'échéance…");
let expired = true, waited = 0;
while (waited < 200) {
  await new Promise((r) => setTimeout(r, 10_000));
  waited += 10;
  const bt = await now();
  expired = await read("isActive", [E.id]);
  if (bt > tNow + 90n) { console.log(`   t = +${bt - tNow} s · isActive :`, expired); break; }
}
out.steps.expiry = {
  timed: { id: E.id.toString(), tx: E.tx, validUntil: (tNow + 90n).toString(), isActiveAfter: expired },
  alreadyPast: { id: past.id.toString(), tx: past.tx, validUntil: (tNow - 1n).toString(), isActive: await read("isActive", [past.id]) },
};

// ═════════════════════════════════════════════ 7. mandateRoot
console.log("\n── 7. non-strippabilité : mandateRoot inclut validUntil ──");
const tr = await now();
const R1 = await mintNode(5, tr + 1000n);
const R2 = await mintNode(5, tr + 2000n);
const root1 = await read("mandateRoot", [R1.id]);
const root2 = await read("mandateRoot", [R2.id]);
console.log("   agentId", R1.id, "validUntil", tr + 1000n, "→", root1);
console.log("   agentId", R2.id, "validUntil", tr + 2000n, "→", root2);
console.log("   racines distinctes :", root1 !== root2);
out.steps.mandateRoot = {
  a: { id: R1.id.toString(), tx: R1.tx, validUntil: (tr + 1000n).toString(), root: root1 },
  b: { id: R2.id.toString(), tx: R2.tx, validUntil: (tr + 2000n).toString(), root: root2 },
  distinct: root1 !== root2,
};

console.log("\nsolde restant :", formatEther(await pub.getBalance({ address: account.address })), "ETH");
mkdirSync(resolve(root, "build"), { recursive: true });
writeFileSync(resolve(root, "build/phaseB.json"), JSON.stringify(out, (_, v) => (typeof v === "bigint" ? v.toString() : v), 2));
console.log("→ build/phaseB.json");
