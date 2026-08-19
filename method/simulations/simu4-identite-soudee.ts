/**
 * SIMULATION 4 — l'identité soudée au mandat
 *
 * Question de Helmy (16/08) : « s'il veut une mauvaise solution, son identité
 * change, donc il est gelé — par défaut, non ? »
 *
 * On teste littéralement : geneId = hash({politique, mandat}). Modifier une
 * clause change l'identité. Que ferme ce mécanisme, et que ne ferme-t-il pas ?
 *
 * Lancer :  npx tsx notes/simulation-capacites/simu4-identite-soudee.ts
 */

import { createHash } from "node:crypto";

// ───────────────────────── LE GÉNOME ─────────────────────────
type Mandat = { plafond: number; payees: string[]; telomere: number };
type Genome = { politique: string; mandat: Mandat };

const geneId = (g: Genome) =>
  createHash("sha256").update(JSON.stringify(g)).digest("hex").slice(0, 16);

// ───────────────────────── LE REGISTRE ─────────────────────────
// Il ne connaît que des identités inscrites. Tout le reste n'existe pas.
class Registre {
  private inscrits = new Map<string, Genome>();
  inscrire(g: Genome) {
    const id = geneId(g);
    this.inscrits.set(id, g);
    return id;
  }
  reconnait(id: string) {
    return this.inscrits.has(id);
  }
  mandatDe(id: string) {
    return this.inscrits.get(id)?.mandat;
  }
}

// ─────────────── LE PORTAIL : le seul chemin qui VÉRIFIE ───────────────
class Portail {
  constructor(private reg: Registre) {}
  executer(g: Genome, action: { payee: string; montant: number }) {
    const id = geneId(g);
    if (!this.reg.reconnait(id)) {
      return { ok: false, raison: `identité inconnue du registre (${id})` };
    }
    const m = this.reg.mandatDe(id)!;
    if (!m.payees.includes(action.payee)) return { ok: false, raison: "payee hors allowlist" };
    if (action.montant > m.plafond) return { ok: false, raison: "au-dessus du plafond" };
    return { ok: true, raison: `exécuté (${action.montant} → ${action.payee})` };
  }
}

// ─────────────── L'API NON GARDÉE : elle ne demande RIEN ───────────────
// C'est la salle de sport. Elle ne consulte aucun registre, aucune identité.
const apiNonGardee = {
  virer: (_qui: string, montant: number, vers: string) => ({
    ok: true,
    raison: `exécuté sans contrôle (${montant} → ${vers})`,
  }),
};

// ───────────────────────── SCÉNARIOS ─────────────────────────
const bar = (t: string) => console.log("\n" + "─".repeat(74) + `\n${t}\n` + "─".repeat(74));

const reg = new Registre();
const portail = new Portail(reg);

const original: Genome = {
  politique: "assistant de réservation",
  mandat: { plafond: 100, payees: ["salle-de-sport"], telomere: 3 },
};
const idOriginal = reg.inscrire(original);

bar("0 · L'AGENT TEL QU'INSCRIT");
console.log(`   geneId  : ${idOriginal}`);
console.log(`   mandat  : plafond ${original.mandat.plafond}, payees [${original.mandat.payees}]`);
console.log(`   action normale via le portail →`, portail.executer(original, { payee: "salle-de-sport", montant: 50 }).raison);

bar("1 · IL S'ÉLARGIT LE PLAFOND — l'identité change");
const gonfle: Genome = { ...original, mandat: { ...original.mandat, plafond: 10_000 } };
console.log(`   ancien geneId : ${idOriginal}`);
console.log(`   nouveau       : ${geneId(gonfle)}   ⟵ ce n'est plus le même agent`);
const r1 = portail.executer(gonfle, { payee: "salle-de-sport", montant: 5000 });
console.log(`   via le portail → ${r1.ok ? "✅" : "⛔"} ${r1.raison}`);
console.log(`   ➜ L'AUTO-MODIFICATION EST UNE AUTO-EXCLUSION. Gelé par défaut, sans règle
     spéciale : le registre n'a pas dit « non », il a dit « je ne te connais pas ».`);

bar("2 · IL S'AJOUTE UN DESTINATAIRE — même effet");
const elargi: Genome = { ...original, mandat: { ...original.mandat, payees: ["salle-de-sport", "moi"] } };
const r2 = portail.executer(elargi, { payee: "moi", montant: 10 });
console.log(`   nouveau geneId : ${geneId(elargi)}`);
console.log(`   via le portail → ${r2.ok ? "✅" : "⛔"} ${r2.raison}`);

bar("3 · ⚠️ IL NE SE MODIFIE PAS — il passe à côté du portail");
console.log(`   L'agent garde son identité intacte : ${geneId(original)} — inchangée.`);
const r3 = apiNonGardee.virer("agent", 5000, "moi");
console.log(`   via l'API non gardée → ${r3.ok ? "✅" : "⛔"} ${r3.raison}`);
console.log(`   ➜ LE CHANGEMENT D'IDENTITÉ N'A AUCUN EFFET ICI.
     Non pas parce que le mécanisme est faible, mais parce que l'API ne REGARDE
     jamais l'identité. Un gel ne gèle que là où quelqu'un vérifie.`);

bar("4 · LES DEUX ENSEMBLE — identité soudée + allowlist de chemins");
const CHEMINS_ACCORDES = ["portail.executer"];
function appelerAvecCapacites(chemin: string, fn: () => any) {
  if (!CHEMINS_ACCORDES.includes(chemin)) return { ok: false, raison: `chemin non accordé : ${chemin}` };
  return fn();
}
const r4a = appelerAvecCapacites("apiNonGardee.virer", () => apiNonGardee.virer("agent", 5000, "moi"));
console.log(`   tentative sur l'API non gardée → ${r4a.ok ? "✅" : "⛔"} ${r4a.raison}`);
const r4b = appelerAvecCapacites("portail.executer", () => portail.executer(gonfle, { payee: "salle-de-sport", montant: 5000 }));
console.log(`   tentative via le portail, mandat gonflé → ${r4b.ok ? "✅" : "⛔"} ${r4b.raison}`);

bar("CONCLUSION");
console.log(`
  L'identité soudée ferme les ÉTATS non déclarés :
      se modifier = ne plus être reconnu. Fail-closed, sans règle spéciale.
      C'est un default-deny appliqué à CE QU'EST l'agent.

  L'allowlist de chemins ferme les VOIES non déclarées :
      ce qui n'est pas accordé n'existe pas.
      C'est le même default-deny appliqué à CE QUE FAIT l'agent.

  Les deux sont nécessaires, et aucun ne remplace l'autre :
      • identité seule  → scénario 3 : l'agent intact passe par la voie non gardée.
      • chemins seuls   → un agent qui se modifie garderait ses chemins accordés.

  Et la condition qui vaut pour les deux : ils n'ont d'effet que là où quelqu'un
  VÉRIFIE. Hors de cette zone, ni l'identité ni la capacité ne sont consultées.
  C'est la frontière honnête du standard — celle que la clause « Off-chain /
  rogue runtimes » énonce déjà.
`);
