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
  parseEther,
  formatEther,
  decodeEventLog,
  type Hex,
  type Address,
} from "viem";
import { privateKeyToAccount, generatePrivateKey } from "viem/accounts";
import { baseSepolia } from "viem/chains";

/**
 * Test interne — provenance déclarée (base, inchangée) vs. contestation par un tiers
 * (contrat séparé, append-only). Base Sepolia, testnet uniquement.
 *
 * Ce script exécute chaque lecture et imprime CE QUE LE CONTRAT REND.
 * Il ne compare à rien, ne calcule aucun verdict, ne qualifie aucune sortie.
 * Toute interprétation se fait après coup, à partir de ces sorties uniquement.
 */
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const baseArt = JSON.parse(readFileSync(resolve(root, "build/ProvenanceRegistry.json"), "utf8"));
const contestArt = JSON.parse(
  readFileSync(resolve(root, "build/ContestationRegistry.json"), "utf8")
);
const baseDep = JSON.parse(readFileSync(resolve(root, "build/deployment-provenance.json"), "utf8"));
const BASE = baseDep.address as Address;

const account = privateKeyToAccount(process.env.PRIVATE_KEY as Hex);
const rpcUrl = process.env.RPC_URL ?? "https://sepolia.base.org";
const pub = createPublicClient({ chain: baseSepolia, transport: http(rpcUrl) });
const wallet = createWalletClient({ account, chain: baseSepolia, transport: http(rpcUrl) });

// La base est write-once : chaque exécution utilise ses propres programKey.
const RUN = process.env.RUN_ID ?? String(Date.now());
const key = (label: string) => keccak256(stringToHex(`${RUN}:contest:${label}`));

const M = {
  BlindReconstruction: 0,
  SharedSpecCollab: 1,
  DerivedFromExisting: 2,
  RawArtifactDecode: 3,
} as const;

const S1 = keccak256(stringToHex(`${RUN}:contest:spec-1`));
const S2 = keccak256(stringToHex(`${RUN}:contest:spec-2`));

const hashA = key("A");
const hashB = key("B");
const hashC = key("C");
const hashD = key("D");
const hashE = key("E");

const out: any = { runId: RUN, base: BASE, graph: {}, assertions: [], readings: [] };
const log = (...a: any[]) => console.log(...a);

/** Attend que l'état soit visible du noeud RPC : un reçu confirmé ne garantit pas
 *  que la requête suivante voie le même état. */
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

async function register(
  label: string,
  k: Hex,
  parents: Hex[],
  spec: Hex,
  method: number,
  from = wallet
) {
  const hash = await from.writeContract({
    address: BASE,
    abi: baseArt.abi,
    functionName: "register",
    args: [k, parents, spec, method],
  });
  const r = await pub.waitForTransactionReceipt({ hash });
  log(`   ${label}  programKey=${k}`);
  log(`        parents déclarés : ${parents.length ? parents.join(", ") : "(aucun)"}`);
  log(`        tx ${hash} → ${r.status}`);
  out.graph[label] = { programKey: k, declaredParents: parents, tx: hash, status: r.status };
  await waitVisible(async () => {
    const rec: any = await pub.readContract({
      address: BASE,
      abi: baseArt.abi,
      functionName: "recordOf",
      args: [k],
    });
    return rec[3] === true;
  });
  return hash;
}

/** Exécute un appel et imprime la valeur rendue, sans la qualifier. */
async function read(label: string, address: Address, abi: any, fn: string, args: any[]) {
  const value = await pub.readContract({ address, abi, functionName: fn, args });
  log(`   ${label}`);
  log(`        rendu : ${value}`);
  out.readings.push({ label, contract: address, fn, args: args.map(String), value });
  return value;
}

log("base (inchangée, déjà déployée) :", BASE);
log("compte                          :", account.address);
log("runId                           :", RUN);
log("solde                           :", formatEther(await pub.getBalance({ address: account.address })), "ETH");

// ---------- déploiement de la couche de contestation ----------
log("\n── déploiement de ContestationRegistry (contrat séparé) ──");
const depHash = await wallet.deployContract({
  abi: contestArt.abi,
  bytecode: contestArt.bytecode as Hex,
  args: [BASE],
});
const depR = await pub.waitForTransactionReceipt({ hash: depHash });
if (depR.status !== "success" || !depR.contractAddress) throw new Error("déploiement échoué");
const CONTEST = depR.contractAddress;
log("   contestation :", CONTEST);
log("   tx           :", depHash, "→", depR.status);
out.contestation = CONTEST;
out.contestationDeployTx = depHash;

await waitVisible(async () => {
  const code = await pub.getCode({ address: CONTEST });
  return !!code && code !== "0x";
});
const wired = await pub.readContract({
  address: CONTEST,
  abi: contestArt.abi,
  functionName: "base",
});
log("   base() lue sur le contrat de contestation :", wired);
out.wiredBase = wired;

// ---------- montage du graphe ----------
log("\n── montage du graphe dans la base ──");
log("   Vérité-terrain expérimentale posée par le protocole : D dérive de A,");
log("   et la déclaration de D omet A. C est posé sans lien à A.");
await register("A", hashA, [], S1, M.BlindReconstruction);
await register("B", hashB, [hashA], S1, M.DerivedFromExisting);
await register("D", hashD, [], S1, M.DerivedFromExisting);
await register("C", hashC, [], S2, M.BlindReconstruction);
await register("E", hashE, [hashB], S1, M.DerivedFromExisting);

// Copie de l'enregistrement de D avant toute contestation (pour P3a).
const dBefore: any = await pub.readContract({
  address: BASE,
  abi: baseArt.abi,
  functionName: "recordOf",
  args: [hashD],
});
const dParentsBefore = (await pub.readContract({
  address: BASE,
  abi: baseArt.abi,
  functionName: "parentsOf",
  args: [hashD],
})) as Hex[];
out.dBefore = { record: dBefore.map(String), parents: dParentsBefore };

// ---------- P1 ----------
log("\n── P1 — lecture sur la base seule ──");
await read("shareLineage(B, D, 2) sur la base", BASE, baseArt.abi, "shareLineage", [hashB, hashD, 2]);

// ---------- tiers ----------
log("\n── mise en place d'un tiers (adresse distincte de l'auteur de D) ──");
const thirdPk = generatePrivateKey(); // jamais imprimée
const third = privateKeyToAccount(thirdPk);
const thirdWallet = createWalletClient({ account: third, chain: baseSepolia, transport: http(rpcUrl) });
const fund = await wallet.sendTransaction({ to: third.address, value: parseEther("0.0008") });
await pub.waitForTransactionReceipt({ hash: fund });
log("   tiers financé :", third.address);
log("   auteur de D   :", account.address);
out.thirdParty = third.address;

async function assertParent(label: string, child: Hex, claimed: Hex) {
  const hash = await thirdWallet.writeContract({
    address: CONTEST,
    abi: contestArt.abi,
    functionName: "assertParent",
    args: [child, claimed],
  });
  const r = await pub.waitForTransactionReceipt({ hash });
  let asserter = "";
  let index = "";
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
  log(`   ${label}`);
  log(`        tx ${hash} → ${r.status}  · event ParentAsserted asserter=${asserter} index=${index}`);
  out.assertions.push({ label, child, claimed, tx: hash, status: r.status, asserter, index });
  await waitVisible(async () => {
    const a = (await pub.readContract({
      address: CONTEST,
      abi: contestArt.abi,
      functionName: "assertedParentsOf",
      args: [child],
    })) as Hex[];
    return a.includes(claimed);
  });
}

// ---------- P2 ----------
log("\n── P2 — assertion tierce puis lecture augmentée ──");
await assertParent("assertParent(D, A) par le tiers", hashD, hashA);
await read(
  "shareLineageWithContest(B, D, 2)",
  CONTEST,
  contestArt.abi,
  "shareLineageWithContest",
  [hashB, hashD, 2]
);

// ---------- P3 ----------
log("\n── P3a — relecture de l'enregistrement de D dans la base ──");
const dAfter: any = await pub.readContract({
  address: BASE,
  abi: baseArt.abi,
  functionName: "recordOf",
  args: [hashD],
});
const dParentsAfter = (await pub.readContract({
  address: BASE,
  abi: baseArt.abi,
  functionName: "parentsOf",
  args: [hashD],
})) as Hex[];
log("   avant contestation : recordOf =", JSON.stringify(dBefore.map(String)));
log("                        parentsOf =", JSON.stringify(dParentsBefore));
log("   après contestation : recordOf =", JSON.stringify(dAfter.map(String)));
log("                        parentsOf =", JSON.stringify(dParentsAfter));
const identical =
  JSON.stringify(dBefore.map(String)) === JSON.stringify(dAfter.map(String)) &&
  JSON.stringify(dParentsBefore) === JSON.stringify(dParentsAfter);
log("   comparaison octet à octet : identique =", identical);
out.p3a = { before: dBefore.map(String), after: dAfter.map(String), parentsBefore: dParentsBefore, parentsAfter: dParentsAfter, identical };

log("\n── P3b — nouvelle tentative de register(D, [A], …) sur la base ──");
let p3bSim = "";
try {
  await pub.simulateContract({
    address: BASE,
    abi: baseArt.abi,
    functionName: "register",
    args: [hashD, [hashA], S1, M.DerivedFromExisting],
    account,
  });
  p3bSim = "la simulation aboutit";
} catch (e: any) {
  p3bSim = e.shortMessage ?? String(e).split("\n")[0];
}
log("   simulation :", p3bSim);
let p3bTx = "";
let p3bStatus = "";
try {
  p3bTx = await wallet.writeContract({
    address: BASE,
    abi: baseArt.abi,
    functionName: "register",
    args: [hashD, [hashA], S1, M.DerivedFromExisting],
    gas: 300_000n,
  });
  const r = await pub.waitForTransactionReceipt({ hash: p3bTx as Hex });
  p3bStatus = r.status;
  log(`   tx ${p3bTx} → ${p3bStatus}`);
} catch {
  p3bStatus = "non diffusée (rejet au niveau du noeud)";
  log("   " + p3bStatus);
}
out.p3b = { simulation: p3bSim, tx: p3bTx, status: p3bStatus };

// ---------- P4 ----------
log("\n── P4 — assertion tierce sur C, puis lecture augmentée ──");
await assertParent("assertParent(C, A) par le tiers", hashC, hashA);
await read(
  "shareLineageWithContest(B, C, 2)",
  CONTEST,
  contestArt.abi,
  "shareLineageWithContest",
  [hashB, hashC, 2]
);

// ---------- P5 ----------
log("\n── P5 — borne de profondeur ──");
log("   E déclare B ; B déclare A. D porte une arête assertée vers A.");
await read("shareLineageWithContest(E, D, 1)", CONTEST, contestArt.abi, "shareLineageWithContest", [hashE, hashD, 1]);
await read("shareLineageWithContest(E, D, 2)", CONTEST, contestArt.abi, "shareLineageWithContest", [hashE, hashD, 2]);
await read("shareLineageWithContest(E, D, 3)", CONTEST, contestArt.abi, "shareLineageWithContest", [hashE, hashD, 3]);

// ---------- lectures complémentaires ----------
log("\n── lectures complémentaires ──");
await read("assertedParentsOf(D)", CONTEST, contestArt.abi, "assertedParentsOf", [hashD]);
await read("assertedParentsOf(C)", CONTEST, contestArt.abi, "assertedParentsOf", [hashC]);
await read("assertionCount()", CONTEST, contestArt.abi, "assertionCount", []);
await read("parentsOf(D) sur la base", BASE, baseArt.abi, "parentsOf", [hashD]);
await read("parentsOf(C) sur la base", BASE, baseArt.abi, "parentsOf", [hashC]);

const bal = await pub.getBalance({ address: account.address });
log("\nsolde restant :", formatEther(bal), "ETH");

writeFileSync(
  resolve(root, "build/test-contestation-results.json"),
  JSON.stringify(out, (k, v) => (typeof v === "bigint" ? v.toString() : v), 2)
);
log("→ build/test-contestation-results.json");
