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
  type Hex,
  type Address,
} from "viem";
import { privateKeyToAccount, generatePrivateKey } from "viem/accounts";
import { baseSepolia } from "viem/chains";

/**
 * Tests d'invariants on-chain du ProvenanceRegistry.
 *
 * RÈGLE : le résultat est déterminé par le contrat, pas par le montage. Chaque
 * propriété testée PEUT échouer. On imprime l'attendu ET l'obtenu, et le verdict
 * final est calculé à partir des sorties réelles — jamais forcé.
 *
 * Ce script ne modifie jamais le montage pour obtenir du vert. Si un résultat
 * surprend, il est rapporté « NON CONCLUANT » tel quel.
 */
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const artifact = JSON.parse(readFileSync(resolve(root, "build/ProvenanceRegistry.json"), "utf8"));
const deployment = JSON.parse(
  readFileSync(resolve(root, "build/deployment-provenance.json"), "utf8")
);
const address = deployment.address as Address;
const abi = artifact.abi;

const account = privateKeyToAccount(process.env.PRIVATE_KEY as Hex);
const rpcUrl = process.env.RPC_URL ?? "https://sepolia.base.org";
const pub = createPublicClient({ chain: baseSepolia, transport: http(rpcUrl) });
const wallet = createWalletClient({ account, chain: baseSepolia, transport: http(rpcUrl) });

// Le registre est write-once : rejouer la démo avec les mêmes clés reverterait
// partout. On salte donc les programKey par exécution. Les hash restent
// déterministes À L'INTÉRIEUR d'une exécution.
const RUN = process.env.RUN_ID ?? String(Date.now());
const key = (label: string) => keccak256(stringToHex(`${RUN}:${label}`));

const M = {
  BlindReconstruction: 0,
  SharedSpecCollab: 1,
  DerivedFromExisting: 2,
  RawArtifactDecode: 3,
} as const;

const S1 = keccak256(stringToHex(`${RUN}:spec-commit-1`));
const S2 = keccak256(stringToHex(`${RUN}:spec-commit-2`));

const hashA = key("A");
const hashB = key("B");
const hashC = key("C");
const hashD = key("D");
const hashE = key("E");

const out: any = { contract: address, runId: RUN, registers: [], rewriteAttempts: [], reads: [] };
const log = (...a: any[]) => console.log(...a);

async function register(label: string, k: Hex, parents: Hex[], spec: Hex, method: number) {
  const hash = await wallet.writeContract({
    address,
    abi,
    functionName: "register",
    args: [k, parents, spec, method],
  });
  const r = await pub.waitForTransactionReceipt({ hash });
  log(`   ${label}  tx ${hash} → ${r.status}`);
  out.registers.push({ label, programKey: k, parents, tx: hash, status: r.status });
  if (r.status !== "success") throw new Error(`register(${label}) a échoué — montage invalide`);
}

/** Tente une réécriture. On rapporte si la chaîne a REFUSÉ, sans présumer. */
async function tryRewrite(label: string, args: any[], from = wallet) {
  let simulationReverted = false;
  let reason = "";
  try {
    await pub.simulateContract({
      address,
      abi,
      functionName: "register",
      args,
      account: from.account!,
    });
  } catch (e: any) {
    simulationReverted = true;
    reason = e.shortMessage ?? e.details ?? String(e).split("\n")[0];
  }

  let txHash: string | undefined;
  let txStatus: string | undefined;
  try {
    txHash = await from.writeContract({
      address,
      abi,
      functionName: "register",
      args,
      gas: 300_000n,
    });
    const r = await pub.waitForTransactionReceipt({ hash: txHash as Hex });
    txStatus = r.status;
  } catch {
    txStatus = "non diffusée (rejet au niveau du noeud)";
  }

  const refused = simulationReverted && txStatus !== "success";
  log(`   ${refused ? "REFUSÉ  " : "ACCEPTÉ "} ${label}`);
  log(`            motif : ${reason || "(aucun — la simulation est passée)"}`);
  if (txHash) log(`            tx ${txHash} → ${txStatus}`);
  out.rewriteAttempts.push({ label, refused, reason, tx: txHash, txStatus });
  return refused;
}

async function shareLineage(a: Hex, b: Hex, depth: number): Promise<boolean> {
  return (await pub.readContract({
    address,
    abi,
    functionName: "shareLineage",
    args: [a, b, depth],
  })) as boolean;
}

log("contrat :", address);
log("auteur  :", account.address);
log("runId   :", RUN);
log("explorateur : https://sepolia.basescan.org/address/" + address);

// ---------------- montage : le graphe ----------------
log("\n── MONTAGE — enregistrement du graphe ──");
log("   A racine · B enfant de A · C indépendant · D enfant de A (code ≠ B) · E enfant de B");
await register("A", hashA, [], S1, M.BlindReconstruction);
await register("B", hashB, [hashA], S1, M.DerivedFromExisting);
await register("C", hashC, [], S2, M.BlindReconstruction);
await register("D", hashD, [hashA], S1, M.SharedSpecCollab);
await register("E", hashE, [hashB], S1, M.DerivedFromExisting);

// ---------------- TEST 1 : append-only ----------------
log("\n── TEST 1 — APPEND-ONLY (objectif, pass/fail) ──");
log("   Toute tentative de réécrire un programKey déjà pris doit être refusée.");
const rewrites: boolean[] = [];
rewrites.push(await tryRewrite("réécrire A avec un autre parent", [hashA, [hashC], S2, M.SharedSpecCollab]));
rewrites.push(await tryRewrite("réécrire A sans parent", [hashA, [], S1, M.BlindReconstruction]));
rewrites.push(await tryRewrite("réécrire B à l'identique", [hashB, [hashA], S1, M.DerivedFromExisting]));
rewrites.push(
  await tryRewrite("réécrire B en effaçant sa lignée", [hashB, [], S1, M.BlindReconstruction])
);

// autre auteur : nécessite une 2e clé financée depuis la 1re
let otherAuthorTested = false;
try {
  const otherPk = generatePrivateKey(); // jamais imprimée
  const other = privateKeyToAccount(otherPk);
  const bal = await pub.getBalance({ address: account.address });
  if (bal > parseEther("0.002")) {
    const fund = await wallet.sendTransaction({ to: other.address, value: parseEther("0.0006") });
    await pub.waitForTransactionReceipt({ hash: fund });
    const otherWallet = createWalletClient({
      account: other,
      chain: baseSepolia,
      transport: http(rpcUrl),
    });
    log(`   (2e auteur financé : ${other.address})`);
    rewrites.push(
      await tryRewrite(
        "réécrire A depuis un AUTRE auteur",
        [hashA, [], S1, M.BlindReconstruction],
        otherWallet
      )
    );
    otherAuthorTested = true;
  } else {
    log("   ⚠️ solde insuffisant pour financer un 2e auteur — cas NON TESTÉ");
  }
} catch (e: any) {
  log("   ⚠️ cas « autre auteur » NON TESTÉ :", e.shortMessage ?? String(e).split("\n")[0]);
}

const test1 = rewrites.every(Boolean);
out.test1_appendOnly = { attempts: rewrites.length, allRefused: test1, otherAuthorTested };
log(`\n   → ${rewrites.length} tentatives, toutes refusées : ${test1 ? "OUI — TEST PASSÉ" : "NON — TEST ÉCHOUÉ"}`);

// ---------------- TEST 2 : traversée, positifs ET négatifs ----------------
log("\n── TEST 2 — TRAVERSÉE shareLineage (objectif, pass/fail) ──");
const cases: Array<{ label: string; a: Hex; b: Hex; depth: number; expected: boolean; why: string }> = [
  { label: "B vs D, depth 2", a: hashB, b: hashD, depth: 2, expected: true, why: "ancêtre commun A" },
  { label: "B vs C, depth 2", a: hashB, b: hashC, depth: 2, expected: false, why: "NÉGATIF — ascendances disjointes" },
  { label: "A vs C, depth 2", a: hashA, b: hashC, depth: 2, expected: false, why: "NÉGATIF — aucun lien" },
  { label: "D vs C, depth 3", a: hashD, b: hashC, depth: 3, expected: false, why: "NÉGATIF — profondeur accrue ne doit pas créer de lien" },
  { label: "E vs A, depth 1", a: hashE, b: hashA, depth: 1, expected: false, why: "HORS PORTÉE — A est à 2 générations" },
  { label: "E vs A, depth 2", a: hashE, b: hashA, depth: 2, expected: true, why: "à portée à depth 2" },
  { label: "E vs D, depth 1", a: hashE, b: hashD, depth: 1, expected: false, why: "HORS PORTÉE — A est à 2 générations de E" },
  { label: "E vs D, depth 2", a: hashE, b: hashD, depth: 2, expected: true, why: "ancêtre commun A" },
];

let test2 = true;
for (const c of cases) {
  const actual = await shareLineage(c.a, c.b, c.depth);
  const ok = actual === c.expected;
  if (!ok) test2 = false;
  log(
    `   ${ok ? "ok  " : "!!  "} ${c.label.padEnd(16)} attendu ${String(c.expected).padEnd(5)} obtenu ${String(actual).padEnd(5)} — ${c.why}`
  );
  out.reads.push({ ...c, actual, ok });
}
out.test2_traversal = { allMatch: test2 };
log(`\n   → tous conformes : ${test2 ? "OUI — TEST PASSÉ" : "NON — au moins un écart, voir ci-dessus"}`);

// ---------------- ILLUSTRATION (pas un test) ----------------
log("\n── ILLUSTRATION — PAS un test, PAS un résultat ──");
log("   hashB ≠ hashD :", hashB !== hashD);
log("   B et D déclarent tous deux A comme parent.");
log("   Lecture correcte : le modèle exprime la lignée SÉPARÉMENT du code.");
log("   Lecture INTERDITE : « on a détecté une lignée cachée ». D descend de A");
log("   parce qu'on l'a DÉCLARÉ ; le contrat ne fait que relire cette déclaration.");
out.illustration = { hashB, hashD, differentCode: hashB !== hashD, bothDeclareParentA: true };

// ---------------- verdict ----------------
log("\n════════ VERDICT ════════");
log(`TEST 1 append-only : ${test1 ? "PASSÉ" : "ÉCHOUÉ"}${otherAuthorTested ? "" : " (cas « autre auteur » non testé)"}`);
log(`TEST 2 traversée   : ${test2 ? "PASSÉ" : "ÉCHOUÉ / NON CONCLUANT"}`);
const bal = await pub.getBalance({ address: account.address });
log(`solde restant      : ${formatEther(bal)} ETH`);

writeFileSync(resolve(root, "build/demo-provenance-results.json"), JSON.stringify(out, null, 2));
log("→ build/demo-provenance-results.json");

if (!test1 || !test2) {
  log("\n⚠️ Au moins un invariant n'est pas tenu. Résultat rapporté tel quel, montage inchangé.");
  process.exit(1);
}
