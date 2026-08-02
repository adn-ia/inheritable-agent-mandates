import "dotenv/config";
import { readFileSync, writeFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import {
  createPublicClient,
  createWalletClient,
  http,
  keccak256,
  stringToHex,
  formatEther,
  decodeEventLog,
  type Hex,
  type Address,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { baseSepolia } from "viem/chains";

/**
 * Test on-chain — cycle d'arêtes assertées. Base Sepolia, testnet uniquement.
 *
 * Le script crée le cycle, lance les lectures, et imprime l'issue de chacune :
 * une valeur rendue, ou un revert avec sa raison, ou un échec. Il ne compare rien,
 * ne qualifie rien, ne calcule aucun verdict. Toute lecture se fait après coup.
 *
 * La base n'est jamais écrite : seules des assertions sont ajoutées dans la
 * couche de contestation.
 */
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const baseArt = JSON.parse(readFileSync(resolve(root, "build/ProvenanceRegistry.json"), "utf8"));
const contestArt = JSON.parse(readFileSync(resolve(root, "build/ContestationRegistry.json"), "utf8"));

const BASE = "0x202f4eef39b57901061a7353595b72c61eacf5df" as Address;
const CONTEST = "0x236b71b033dc93634ce170d51dcd313bda19b233" as Address;

const account = privateKeyToAccount(process.env.PRIVATE_KEY as Hex);
const rpcUrl = process.env.RPC_URL ?? "https://sepolia.base.org";
const pub = createPublicClient({ chain: baseSepolia, transport: http(rpcUrl) });
const wallet = createWalletClient({ account, chain: baseSepolia, transport: http(rpcUrl) });

const RUN = process.env.RUN_ID ?? String(Date.now());
const key = (label: string) => keccak256(stringToHex(`${RUN}:cycle:${label}`));
const SPEC = keccak256(stringToHex(`${RUN}:cycle:spec`));

const hashP = key("P");
const hashQ = key("Q");
const hashZ = key("Z");
const hashP2 = key("P2");

const out: any = { runId: RUN, base: BASE, contestation: CONTEST, graph: {}, assertions: [], T1: [], T3: [] };
const log = (...a: any[]) => console.log(...a);

async function waitVisible(check: () => Promise<boolean>, tries = 30) {
  for (let i = 0; i < tries; i++) {
    try {
      if (await check()) return;
    } catch {
      /* pas encore visible */
    }
    await new Promise((r) => setTimeout(r, 2000));
  }
  throw new Error("état jamais visible côté RPC");
}

async function register(label: string, k: Hex) {
  const hash = await wallet.writeContract({
    address: BASE,
    abi: baseArt.abi,
    functionName: "register",
    args: [k, [], SPEC, 0],
  });
  const r = await pub.waitForTransactionReceipt({ hash });
  log(`   ${label}  ${k}`);
  log(`        tx ${hash} → ${r.status}  gaz ${r.gasUsed}`);
  out.graph[label] = { programKey: k, tx: hash, status: r.status, gasUsed: r.gasUsed.toString() };
  await waitVisible(async () => {
    const rec: any = await pub.readContract({ address: BASE, abi: baseArt.abi, functionName: "recordOf", args: [k] });
    return rec[3] === true;
  });
}

async function assertParent(label: string, child: Hex, claimed: Hex) {
  log(`   ${label}`);
  let simulation = "";
  try {
    await pub.simulateContract({
      address: CONTEST,
      abi: contestArt.abi,
      functionName: "assertParent",
      args: [child, claimed],
      account,
    });
    simulation = "aboutit";
  } catch (e: any) {
    simulation = e.shortMessage ?? String(e).split("\n")[0];
  }
  log(`        issue simulation : ${simulation}`);

  let tx = "";
  let status = "";
  let gasUsed = "";
  let asserter = "";
  let index = "";
  try {
    tx = await wallet.writeContract({
      address: CONTEST,
      abi: contestArt.abi,
      functionName: "assertParent",
      args: [child, claimed],
      gas: 300_000n,
    });
    const r = await pub.waitForTransactionReceipt({ hash: tx as Hex });
    status = r.status;
    gasUsed = r.gasUsed.toString();
    for (const l of r.logs) {
      try {
        const d: any = decodeEventLog({ abi: contestArt.abi, data: l.data, topics: l.topics });
        if (d.eventName === "ParentAsserted") {
          asserter = d.args.asserter;
          index = String(d.args.index);
        }
      } catch {
        /* log d'un autre contrat */
      }
    }
    log(`        tx ${tx} → ${status}  gaz ${gasUsed}  asserter=${asserter || "—"} index=${index || "—"}`);
  } catch (e: any) {
    status = "non diffusée";
    log(`        issue transaction : ${status} — ${e.shortMessage ?? String(e).split("\n")[0]}`);
  }
  out.assertions.push({ label, child, claimed, simulation, tx, status, gasUsed, asserter, index });
  return status === "success";
}

/** Lance la lecture et imprime son issue, sans la comparer ni la qualifier. */
async function readIssue(label: string, a: Hex, b: Hex, depth: number) {
  let issue = "";
  let gas = "";
  try {
    gas = String(
      await pub.estimateContractGas({
        address: CONTEST,
        abi: contestArt.abi,
        functionName: "shareLineageWithContest",
        args: [a, b, depth],
        account,
      })
    );
  } catch (e: any) {
    gas = "estimation impossible — " + (e.shortMessage ?? String(e).split("\n")[0]);
  }
  try {
    const v = await pub.readContract({
      address: CONTEST,
      abi: contestArt.abi,
      functionName: "shareLineageWithContest",
      args: [a, b, depth],
    });
    issue = String(v);
  } catch (e: any) {
    issue = "ÉCHEC — " + (e.shortMessage ?? e.details ?? String(e).split("\n")[0]);
  }
  log(`   ${label}`);
  log(`        issue : ${issue}`);
  log(`        gaz   : ${gas}`);
  return { label, depth, issue, gas };
}

log("base           :", BASE);
log("contestation   :", CONTEST);
log("compte         :", account.address);
log("runId          :", RUN);
log("solde          :", formatEther(await pub.getBalance({ address: account.address })), "ETH");

// ---------- montage ----------
log("\n── enregistrement des noeuds dans la base ──");
await register("P", hashP);
await register("Q", hashQ);
await register("Z", hashZ);
await register("P2", hashP2);

const pBefore = await pub.readContract({ address: BASE, abi: baseArt.abi, functionName: "parentsOf", args: [hashP] });
const zBefore = await pub.readContract({ address: BASE, abi: baseArt.abi, functionName: "parentsOf", args: [hashZ] });
out.baseBefore = { parentsOfP: pBefore, parentsOfZ: zBefore };

// ---------- création du cycle ----------
log("\n── création du cycle dans la contestation ──");
await assertParent("assertParent(P, Z)", hashP, hashZ);
await waitVisible(async () => {
  const a = (await pub.readContract({ address: CONTEST, abi: contestArt.abi, functionName: "assertedParentsOf", args: [hashP] })) as Hex[];
  return a.includes(hashZ);
});
await assertParent("assertParent(Z, P)", hashZ, hashP);
await waitVisible(async () => {
  const a = (await pub.readContract({ address: CONTEST, abi: contestArt.abi, functionName: "assertedParentsOf", args: [hashZ] })) as Hex[];
  return a.includes(hashP);
});

// ---------- T1 + T2 ----------
log("\n── T1 / T2 — shareLineageWithContest(P, Q, maxDepth) ──");
for (const d of [1, 2, 3, 8, 16]) {
  out.T1.push(await readIssue(`maxDepth = ${d}`, hashP, hashQ, d));
}

// ---------- T3 ----------
log("\n── T3 — auto-boucle sur P2 ──");
await assertParent("assertParent(P2, P2)", hashP2, hashP2);
out.T3.push(await readIssue("shareLineageWithContest(P2, Q, 3)", hashP2, hashQ, 3));

// ---------- lectures complémentaires ----------
log("\n── lectures complémentaires ──");
for (const [label, addr, abi, fn, args] of [
  ["assertedParentsOf(P)", CONTEST, contestArt.abi, "assertedParentsOf", [hashP]],
  ["assertedParentsOf(Z)", CONTEST, contestArt.abi, "assertedParentsOf", [hashZ]],
  ["assertedParentsOf(P2)", CONTEST, contestArt.abi, "assertedParentsOf", [hashP2]],
  ["assertionCount()", CONTEST, contestArt.abi, "assertionCount", []],
  ["parentsOf(P) sur la base", BASE, baseArt.abi, "parentsOf", [hashP]],
  ["parentsOf(Z) sur la base", BASE, baseArt.abi, "parentsOf", [hashZ]],
] as const) {
  const v = await pub.readContract({ address: addr as Address, abi, functionName: fn, args: args as any });
  log(`   ${label}`);
  log(`        rendu : ${v}`);
  (out.extra ??= []).push({ label, value: v });
}

log("\nsolde restant :", formatEther(await pub.getBalance({ address: account.address })), "ETH");
writeFileSync(
  resolve(root, "build/test-cycle-results.json"),
  JSON.stringify(out, (k, v) => (typeof v === "bigint" ? v.toString() : v), 2)
);
log("→ build/test-cycle-results.json");
