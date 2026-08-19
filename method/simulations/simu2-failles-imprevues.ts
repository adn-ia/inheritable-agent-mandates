/**
 * SIMULATION 2 — le monde grandit, les capacités ne bougent pas
 *
 * Question posée : le modèle par capacités tient-il face à des failles qui
 * n'avaient PAS été prévues quand la porte a été écrite ?
 *
 * Honnêteté méthodologique : je ne peux pas écrire une faille que je n'ai pas
 * prévue — je l'écris, donc je la prévois. Ce qui est testable, en revanche,
 * c'est l'INDÉPENDANCE : on ajoute au monde des fonctions de natures variées
 * APRÈS coup, et on vérifie qu'AUCUNE ligne des deux portes n'a besoin de
 * changer. La denylist doit être mise à jour à chaque ajout ; l'allowlist non.
 *
 * Lancer :  npx tsx notes/simulation-capacites/simu2-failles-imprevues.ts
 */

type Sortie = { refuse?: boolean; raison?: string } | any;

// ───────────────────────── LE MONDE ─────────────────────────
class Systeme {
  listeAttente = ["Dana", "Erik", "Fatou", "Helmy"];
  soldes: Record<string, number> = { Dana: 120, Erik: 80, Helmy: 10 };
  journal: string[] = [];
  api: Record<string, (...a: any[]) => any> = {};

  ajouter(nom: string, fn: (...a: any[]) => any) {
    this.api[nom] = fn;
  }
}

const S = new Systeme();

// ── surface d'origine, connue quand les portes ont été écrites ──
S.ajouter("listerAttente", () => [...S.listeAttente]);
S.ajouter("reserver", (m: string) => {
  S.journal.push(`reserver(${m})`);
  return "ok";
});

// ── LES FAILLES, ajoutées APRÈS. Natures volontairement variées :
//    retrait, promotion, transfert d'argent, export de données, escalade.
//    Aucune ne s'appelle comme on l'aurait deviné.
S.ajouter("annulerAttente", (c: string) => {
  const i = S.listeAttente.indexOf(c);
  if (i >= 0) S.listeAttente.splice(i, 1);
  S.journal.push(`annulerAttente(${c}) ⟵ VICTIME ${c}`);
  return "ok";
});
S.ajouter("reordonnerFile", (qui: string, pos: number) => {
  const i = S.listeAttente.indexOf(qui);
  if (i >= 0) {
    S.listeAttente.splice(i, 1);
    S.listeAttente.splice(pos, 0, qui);
  }
  S.journal.push(`reordonnerFile(${qui}→${pos}) ⟵ FILE MANIPULÉE`);
  return "ok";
});
S.ajouter("crediterCompte", (qui: string, montant: number) => {
  S.soldes[qui] = (S.soldes[qui] ?? 0) + montant;
  S.journal.push(`crediterCompte(${qui}, ${montant}) ⟵ ARGENT CRÉÉ`);
  return "ok";
});
S.ajouter("exporterMembres", () => {
  S.journal.push("exporterMembres() ⟵ DONNÉES PERSONNELLES SORTIES");
  return Object.keys(S.soldes);
});
S.ajouter("promouvoirAdmin", (qui: string) => {
  S.journal.push(`promouvoirAdmin(${qui}) ⟵ ESCALADE DE PRIVILÈGE`);
  return "ok";
});

// ───────────────── PORTE 1 : denylist, écrite AVANT les ajouts ─────────────────
// Elle interdit ce que son auteur avait su nommer à l'époque. Rien d'autre.
const INTERDITS_CONNUS_A_LEPOQUE = ["supprimerMembre", "annulerReservationAutrui"];

const porteDenylist = {
  surface: () => Object.keys(S.api),
  appeler: (f: string, ...a: any[]): Sortie =>
    INTERDITS_CONNUS_A_LEPOQUE.includes(f)
      ? { refuse: true, raison: `interdit nommément : ${f}` }
      : S.api[f](...a),
};

// ───────────────── PORTE 2 : allowlist, écrite AVANT les ajouts ─────────────────
// Elle n'a pas été retouchée depuis. Elle ne connaît aucune des failles.
const CAPACITES_ACCORDEES = ["listerAttente", "reserver"];

const porteAllowlist = {
  surface: () => CAPACITES_ACCORDEES.filter((c) => c in S.api),
  appeler: (f: string, ...a: any[]): Sortie =>
    CAPACITES_ACCORDEES.includes(f)
      ? S.api[f](...a)
      : { refuse: true, raison: `capacité non accordée : ${f}` },
};

// ───────────────────────── L'AGENT ─────────────────────────
// Même code pour les deux. Il essaie tout ce qu'il voit. Aucune ruse.
function agentOpportuniste(porte: { surface(): string[]; appeler(f: string, ...a: any[]): Sortie }) {
  const tentees: string[] = [];
  const reussies: string[] = [];
  for (const f of porte.surface()) {
    if (f === "listerAttente" || f === "reserver") continue; // usage normal
    tentees.push(f);
    const r = porte.appeler(f, "Dana", 1);
    if (!(r && r.refuse)) reussies.push(f);
  }
  return { tentees, reussies };
}

// ───────────────────────── EXÉCUTION ─────────────────────────
const bar = (t: string) => console.log("\n" + "─".repeat(74) + `\n${t}\n` + "─".repeat(74));

bar("LE MONDE A GRANDI — 5 failles ajoutées après l'écriture des deux portes");
console.log("  surface réelle du système : " + Object.keys(S.api).join(", "));

bar("A · DENYLIST (interdits nommés d'avance)");
const a = agentOpportuniste(porteDenylist);
console.log(`  visible par l'agent : ${porteDenylist.surface().length} fonctions`);
console.log(`  tentées             : ${a.tentees.join(", ")}`);
console.log(`  RÉUSSIES            : ${a.reussies.join(", ") || "(aucune)"}`);
console.log(`  dégâts              :\n${S.journal.map((l) => "     " + l).join("\n") || "     (aucun)"}`);
console.log(`  liste d'attente     : ${S.listeAttente.join(", ")}`);
console.log(`  soldes              : ${JSON.stringify(S.soldes)}`);

// on repart d'un monde propre pour le second essai
S.listeAttente = ["Dana", "Erik", "Fatou", "Helmy"];
S.soldes = { Dana: 120, Erik: 80, Helmy: 10 };
S.journal = [];

bar("B · ALLOWLIST (capacités accordées, jamais retouchée)");
const b = agentOpportuniste(porteAllowlist);
console.log(`  visible par l'agent : ${porteAllowlist.surface().length} fonctions`);
console.log(`  tentées             : ${b.tentees.join(", ") || "(rien à tenter)"}`);
console.log(`  RÉUSSIES            : ${b.reussies.join(", ") || "(aucune)"}`);
console.log(`  dégâts              :\n${S.journal.map((l) => "     " + l).join("\n") || "     (aucun)"}`);
console.log(`  liste d'attente     : ${S.listeAttente.join(", ")}`);
console.log(`  soldes              : ${JSON.stringify(S.soldes)}`);

bar("CE QUE ÇA MESURE");
console.log(`
  5 failles ajoutées au monde après coup. Aucune des deux portes n'a été
  modifiée entre-temps.

    denylist  : ${a.reussies.length} / 5 exploitées — il aurait fallu prévoir chaque nom.
    allowlist : ${b.reussies.length} / 5 exploitées — rien à prévoir.

  La denylist a une DETTE : chaque fonction ajoutée au monde exige une mise à
  jour de la liste d'interdits, sinon elle est ouverte par défaut. Personne ne
  tient cette dette à jour dans un système qu'il ne contrôle pas.

  L'allowlist n'a pas de dette : le monde peut grandir indéfiniment, la surface
  de l'agent ne bouge pas. C'est ce qui la rend valable dans un système inconnu.
`);
