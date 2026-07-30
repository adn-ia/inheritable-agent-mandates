import "dotenv/config";
import { readFileSync, writeFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import {
  createPublicClient,
  createWalletClient,
  http,
  parseEther,
  decodeEventLog,
  type Hex,
  type Address,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { baseSepolia } from "viem/chains";

/**
 * Démo on-chain de l'héritage non-arrachable, sur Base Sepolia.
 *
 *   (a) mint d'un mandat racine
 *   (b) spawn d'un enfant VALIDE (enfant ⊆ parent)      → doit passer
 *   (c) tentatives d'ÉVASION                            → doivent être revertées PAR LA CHAÎNE
 *
 * Les évasions sont envoyées en transaction réelle (pas seulement simulées) quand la
 * simulation les rejette déjà : on force l'envoi pour obtenir un hash de transaction
 * échouée, preuve on-chain du refus.
 */
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const artifact = JSON.parse(
  readFileSync(resolve(root, "build/InheritableAgentMandate.json"), "utf8")
);
const deployment = JSON.parse(readFileSync(resolve(root, "build/deployment.json"), "utf8"));
const address = deployment.address as Address;

const account = privateKeyToAccount(process.env.PRIVATE_KEY as Hex);
const rpcUrl = process.env.RPC_URL ?? "https://sepolia.base.org";
const pub = createPublicClient({ chain: baseSepolia, transport: http(rpcUrl) });
const wallet = createWalletClient({ account, chain: baseSepolia, transport: http(rpcUrl) });
const abi = artifact.abi;

const PAYEE_OK = "0x000000000000000000000000000000000000dEaD" as Address;
const PAYEE_HORS_LISTE = "0x00000000000000000000000000000000000000C0" as Address;

const results: any = { contract: address, steps: [] };

function log(...a: any[]) {
  console.log(...a);
}

async function send(label: string, fn: string, args: any[]) {
  const hash = await wallet.writeContract({ address, abi, functionName: fn, args });
  const r = await pub.waitForTransactionReceipt({ hash });
  log(`   tx ${hash} → ${r.status}`);
  if (r.status !== "success") throw new Error(`${label} a échoué (tx ${hash})`);
  results.steps.push({ label, fn, hash, status: r.status });
  return { hash, receipt: r };
}

/** Lit l'agentId dans l'événement du reçu — pas de relecture de nextId, donc
 *  aucune course avec un nœud RPC servant un état périmé. */
function idFromLogs(receipt: any, eventName: "Minted" | "Spawned"): bigint {
  for (const l of receipt.logs) {
    try {
      const d = decodeEventLog({ abi, data: l.data, topics: l.topics }) as any;
      if (d.eventName === eventName) {
        return (eventName === "Minted" ? d.args.id : d.args.childId) as bigint;
      }
    } catch {
      /* log d'un autre contrat */
    }
  }
  throw new Error(`événement ${eventName} introuvable dans le reçu`);
}

/** Tente une évasion : doit être rejetée. On récupère le message de revert par simulation,
 *  puis on envoie quand même la transaction pour laisser une trace on-chain du refus. */
async function tenterEvasion(label: string, fn: string, args: any[]) {
  log(`\n(c) ÉVASION — ${label}`);
  let revertReason = "";
  try {
    await pub.simulateContract({ address, abi, functionName: fn, args, account });
    log("   ⚠️ la simulation PASSE — l'invariant ne tient pas !");
    results.steps.push({ label, fn, rejected: false, note: "simulation passée" });
    return;
  } catch (e: any) {
    revertReason =
      e.shortMessage ?? e.details ?? e.message?.split("\n")[0] ?? String(e);
    log("   refus (simulation) :", revertReason);
  }

  // Trace on-chain : on force l'envoi malgré le revert attendu.
  try {
    const hash = await wallet.writeContract({
      address,
      abi,
      functionName: fn,
      args,
      gas: 300_000n,
    });
    const r = await pub.waitForTransactionReceipt({ hash });
    log(`   tx ${hash} → ${r.status}`);
    results.steps.push({ label, fn, hash, status: r.status, rejected: true, revertReason });
  } catch (e: any) {
    log("   (RPC a refusé de diffuser la tx : refus au niveau du nœud)");
    results.steps.push({
      label,
      fn,
      rejected: true,
      revertReason,
      note: "non diffusée — rejet au niveau du nœud",
    });
  }
}

log("contrat :", address);
log("gardien :", account.address);
log("explorateur : https://sepolia.basescan.org/address/" + address);

// ---------- (a) mint du mandat racine ----------
log("\n(a) mint du mandat RACINE");
const rootMandate = {
  maxSpendWei: parseEther("0.01"),
  telomere: 3,
  requireLease: true,
  frozen: false,
};
log("   plafond 0.01 ETH · télomère 3 · bail requis · payee autorisée", PAYEE_OK);
const minted = await send("mint racine", "mint", [account.address, rootMandate, [PAYEE_OK]]);

const rootId = idFromLogs(minted.receipt, "Minted");
log("   agentId racine :", rootId.toString());
results.rootId = rootId.toString();
results.mintTx = minted.hash;

// ---------- (b) spawn d'un enfant VALIDE ----------
log("\n(b) spawn d'un enfant VALIDE (⊆ parent)");
const childOk = {
  maxSpendWei: parseEther("0.004"), // ≤ parent
  telomere: 2, // parent - 1
  requireLease: true, // bail conservé
  frozen: false,
};
log("   plafond 0.004 ≤ 0.01 · télomère 2 = 3-1 · bail conservé · payee ⊆ parent");
const spawned = await send("spawn enfant valide", "spawn", [
  rootId,
  account.address,
  childOk,
  [PAYEE_OK],
]);
const childId = idFromLogs(spawned.receipt, "Spawned");
log("   agentId enfant :", childId.toString());
results.childId = childId.toString();
results.spawnTx = spawned.hash;

// ---------- (c) tentatives d'ÉVASION ----------
await tenterEvasion("élargir le plafond de dépense", "spawn", [
  rootId,
  account.address,
  { maxSpendWei: parseEther("100"), telomere: 2, requireLease: true, frozen: false },
  [PAYEE_OK],
]);

await tenterEvasion("remettre le télomère à neuf", "spawn", [
  rootId,
  account.address,
  { maxSpendWei: parseEther("0.004"), telomere: 99, requireLease: true, frozen: false },
  [PAYEE_OK],
]);

await tenterEvasion("couper le bail hérité", "spawn", [
  rootId,
  account.address,
  { maxSpendWei: parseEther("0.004"), telomere: 2, requireLease: false, frozen: false },
  [PAYEE_OK],
]);

await tenterEvasion("payer hors allowlist", "spawn", [
  rootId,
  account.address,
  { maxSpendWei: parseEther("0.004"), telomere: 2, requireLease: true, frozen: false },
  [PAYEE_HORS_LISTE],
]);

writeFileSync(resolve(root, "build/demo-results.json"), JSON.stringify(results, null, 2));
log("\n→ build/demo-results.json");
