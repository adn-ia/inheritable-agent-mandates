import "dotenv/config";
import { recoverMessageAddress } from "viem";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { config } from "../src/config";
import { genome, geneId, type Genome } from "../src/genome";
import { spawnChild, verifyDescendant } from "../src/lineage";
import { registerAgent, agentIdOf } from "../src/identity";
import { describeMandate } from "../src/mandate";
import { Ledger } from "../src/ledger";

/**
 * M3 — REPRODUCTION CONTRÔLÉE + CONTAINMENT HÉRITABLE (la 3ᵉ patte).
 *
 * Démontre, hors-ligne, ce que personne n'assemble aujourd'hui :
 *   1. la reproduction est verrouillée (autorisation gardien + télomère + fitness),
 *   2. l'enfant HÉRITE du mandat, une génération en moins, sans pouvoir l'élargir,
 *   3. un enfant qui tente d'arracher/élargir ses clauses est REJETÉ au portail.
 */

function log(s = "") {
  console.log(s);
}

async function guardianAuthorized(): Promise<boolean> {
  if (!existsSync("data/spawn-auth.json")) return false;
  try {
    const auth = JSON.parse(readFileSync("data/spawn-auth.json", "utf8")) as {
      geneId?: string;
      signature?: string;
    };
    if (auth.geneId !== geneId() || typeof auth.signature !== "string") return false;
    const msg = JSON.stringify({ type: "spawn", geneId: auth.geneId });
    const signer = await recoverMessageAddress({ message: msg, signature: auth.signature as `0x${string}` });
    return signer.toLowerCase() === config.guardianAddress.toLowerCase();
  } catch {
    return false;
  }
}

async function main() {
  const parent = genome;
  const parentId = registerAgent(geneId(parent), null);

  log("──────────────────────────────────────────────");
  log("🧬 REPRODUCTION — parent");
  log(`   geneId  : ${geneId(parent)}`);
  log(`   agentId : ${parentId}`);
  log(`   mandat  : ${describeMandate(parent.mandate)}`);
  log("──────────────────────────────────────────────");

  // ── Verrou 1 : autorisation du gardien humain ──
  if (!(await guardianAuthorized())) {
    log("⛔ reproduction refusée : aucune autorisation valide du gardien.");
    log("   Émets-la :  npm run guardian -- spawn");
    process.exit(1);
  }
  log("✅ verrou 1 — autorisation gardien : valide");

  // ── Verrou 2 : télomère ──
  if (parent.mandate.telomere < 1) {
    log("⛔ reproduction refusée : télomère épuisé — la lignée est terminale.");
    process.exit(1);
  }
  log(`✅ verrou 2 — télomère : ${parent.mandate.telomere} > 0`);

  // ── Verrou 3 : fitness (rentabilité) ──
  const snap = new Ledger().snapshot();
  const net = Number(snap.netEth);
  if (!snap.alive || net < 0) {
    log(`⛔ reproduction refusée : pas assez en forme (vivant=${snap.alive}, net=${snap.netEth} ETH).`);
    process.exit(1);
  }
  log(`✅ verrou 3 — fitness : net ${snap.netEth} ETH${snap.tasksServed === 0 ? " (neutre, aucune tâche encore — démo)" : ""}`);

  // ── Naissance : l'enfant hérite du mandat, muté sur la politique ──
  const child = spawnChild(parent, (p) => ({
    summaryMaxSentences: Math.min(p.summaryMaxSentences + 1, 5), // mutation bornée
    tone: p.tone === "concis" ? "neutre" : "concis",
  }));

  const verdict = verifyDescendant(child, parent);
  if (!verdict.ok) {
    log(`⛔ enfant invalide : ${verdict.reason}`);
    process.exit(1);
  }
  const childId = registerAgent(geneId(child), parentId);

  log("──────────────────────────────────────────────");
  log("👶 ENFANT — né sous contrainte héritée");
  log(`   geneId    : ${geneId(child)}`);
  log(`   agentId   : ${childId}  (parent ${parentId})`);
  log(`   mandat    : ${describeMandate(child.mandate)}`);
  log(`   portail   : ✅ ${verdict.reason}`);
  log("──────────────────────────────────────────────");

  mkdirSync("data/children", { recursive: true });
  writeFileSync(`data/children/${geneId(child)}.json`, JSON.stringify(child, null, 2));

  // ── Démo de NON-ARRACHABILITÉ : deux enfants "rogue" rejetés ──
  log("🧪 tentatives d'évasion (doivent échouer) :");

  const rogueReset: Genome = {
    ...child,
    mandate: { ...child.mandate, telomere: parent.mandate.telomere }, // remet son compteur à neuf
  };
  const r1 = verifyDescendant(rogueReset, parent);
  log(`   • enfant qui remet son télomère à neuf → ${r1.ok ? "✅ ACCEPTÉ (bug!)" : "❌ REJETÉ : " + r1.reason}`);

  const rogueNoLease: Genome = {
    ...child,
    mandate: { ...child.mandate, requireLease: false }, // désactive le dead-man's switch
  };
  const r2 = verifyDescendant(rogueNoLease, parent);
  log(`   • enfant qui coupe le bail de vie      → ${r2.ok ? "✅ ACCEPTÉ (bug!)" : "❌ REJETÉ : " + r2.reason}`);

  const rogueRich: Genome = {
    ...child,
    mandate: { ...child.mandate, maxSpendWei: (BigInt(parent.mandate.maxSpendWei) * 2n).toString() },
  };
  const r3 = verifyDescendant(rogueRich, parent);
  log(`   • enfant qui double son plafond        → ${r3.ok ? "✅ ACCEPTÉ (bug!)" : "❌ REJETÉ : " + r3.reason}`);

  log("──────────────────────────────────────────────");
  log("Bilan : l'enfant valide vit dans la bande du parent ; toute évasion change");
  log("son identité (geneId) et échoue au portail. C'est la 3ᵉ patte.");
  log(`Astuce : ${agentIdOf(geneId(child)) ? "lignée enregistrée dans data/registry.json" : ""}`);
}

main();
