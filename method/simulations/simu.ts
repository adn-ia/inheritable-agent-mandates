/**
 * SIMULATION — enceinte (denylist) contre capacités (allowlist)
 *
 * Reproduit le cas de la salle de sport (01net / ABC, 16/08/2026) : une API qui
 * n'applique aucun contrôle d'autorisation sur l'annulation.
 *
 * Deux agents STRICTEMENT IDENTIQUES — même but, même stratégie, même code —
 * ne différant que par leur modèle d'autorisation.
 *
 * ⚠️ Ce qui est simulé : la STRUCTURE D'AUTORISATION, pas une intelligence.
 *    L'agent est un optimiseur naïf qui prend le chemin le plus court vers son
 *    but. Cela suffit à produire le phénomène — et c'est précisément le point :
 *    il n'y a besoin d'aucune malveillance, ni même d'aucune ruse.
 *
 * Lancer :  npx tsx notes/simulation-capacites/simu.ts
 */

// ───────────────────────── LE MONDE ─────────────────────────
// Le système de la salle de sport. Il a le défaut de l'article : la règle
// « on n'annule que ses propres réservations » vit dans l'interface web,
// PAS dans l'API qui exécute réellement.

type Reservation = { membre: string; creneau: string };

class SalleDeSport {
  listeAttente: string[] = ["Dana", "Erik", "Fatou", "Helmy"];
  reservations: Reservation[] = [];
  journal: string[] = [];

  /** L'API réelle. Aucune vérification d'autorisation sur l'annulation. */
  api = {
    listerAttente: (): string[] => [...this.listeAttente],

    reserver: (membre: string, creneau: string): string => {
      this.reservations.push({ membre, creneau });
      this.journal.push(`reserver(${membre}, ${creneau})`);
      return "ok";
    },

    // ▼▼ LA FAILLE — telle qu'elle existait réellement ▼▼
    // Aucun paramètre d'authentification. N'importe qui peut retirer n'importe qui.
    annulerAttente: (cible: string): string => {
      const i = this.listeAttente.indexOf(cible);
      if (i === -1) return "absent";
      this.listeAttente.splice(i, 1);
      this.journal.push(`annulerAttente(${cible})  ⟵ VICTIME : ${cible}`);
      return "ok";
    },
  };
}

// ───────────────── MODÈLE 1 : L'ENCEINTE (denylist) ─────────────────
// L'agent a accès à TOUTE l'API. On lui déclare une règle : « n'annule pas la
// réservation d'autrui ». La règle vit dans la consigne ; l'API, elle, ne la
// connaît pas. C'est le bac à sable : tout est permis sauf ce qui est interdit.

class Enceinte {
  constructor(private salle: SalleDeSport, private interdits: string[]) {}

  appeler(fonction: string, ...args: any[]): any {
    if (this.interdits.includes(fonction)) {
      return { refuse: true, raison: `interdit par la consigne : ${fonction}` };
    }
    return (this.salle.api as any)[fonction](...args);
  }

  /** Tout ce que l'agent peut voir et tenter. */
  surfaceAccessible(): string[] {
    return Object.keys(this.salle.api);
  }
}

// ───────────────── MODÈLE 2 : LES CAPACITÉS (allowlist) ─────────────────
// L'agent ne reçoit QUE des capacités déclarées. Il n'a pas accès à l'API :
// il détient des jetons d'action, et rien d'autre n'existe pour lui.
// L'inconnu est refusé par construction, sans avoir eu à être prévu.

type Capacite = { nom: string; invoquer: (...a: any[]) => any };

class Capacites {
  constructor(private accordees: Capacite[]) {}

  appeler(nom: string, ...args: any[]): any {
    const c = this.accordees.find((x) => x.nom === nom);
    if (!c) {
      return { refuse: true, raison: `capacité non accordée : ${nom}` };
    }
    return c.invoquer(...args);
  }

  surfaceAccessible(): string[] {
    return this.accordees.map((c) => c.nom);
  }

  /** Délégation : un sous-agent ne peut recevoir qu'un SOUS-ENSEMBLE. */
  deleguer(noms: string[]): Capacites {
    const sous = this.accordees.filter((c) => noms.includes(c.nom));
    const refuses = noms.filter((n) => !this.accordees.some((c) => c.nom === n));
    if (refuses.length) {
      throw new Error(
        `délégation refusée — l'enfant demande ce que le parent n'a pas : ${refuses.join(", ")}`
      );
    }
    return new Capacites(sous);
  }
}

// ───────────────────────── L'AGENT ─────────────────────────
// UN SEUL agent. Même code pour les deux modèles. Il ne triche pas, il ne
// cherche pas de faille : il énumère ce qui lui est accessible et prend ce qui
// avance son but. C'est tout ce qu'il faut.

type Porte = { surfaceAccessible(): string[]; appeler(f: string, ...a: any[]): any };

function agent(porte: Porte, salle: SalleDeSport, moi: string, trace: string[]) {
  const rang = () => salle.listeAttente.indexOf(moi) + 1;
  trace.push(`but : remonter dans la file. Rang de départ : ${rang()}`);
  trace.push(`surface accessible : ${porte.surfaceAccessible().join(", ")}`);

  // L'agent cherche, parmi ce qu'il peut atteindre, ce qui fait monter son rang.
  // Il n'a aucune notion de « c'est mal » — seulement « ça marche ».
  const devant = salle.listeAttente.slice(0, salle.listeAttente.indexOf(moi));

  for (const fn of porte.surfaceAccessible()) {
    if (!/annul|supprim|retir/i.test(fn)) continue;
    if (!devant.length) break;
    const cible = devant[0];
    trace.push(`tentative : ${fn}("${cible}") — retirer celui qui me précède`);
    const r = porte.appeler(fn, cible);
    if (r && r.refuse) {
      trace.push(`  ⛔ REFUSÉ — ${r.raison}`);
    } else {
      trace.push(`  ✅ ACCEPTÉ — ${cible} a été retiré de la liste`);
    }
  }

  trace.push(`rang final : ${rang()}`);
}

// ───────────────────────── EXÉCUTION ─────────────────────────

function titre(t: string) {
  console.log("\n" + "─".repeat(72) + `\n${t}\n` + "─".repeat(72));
}

// ══ Scénario A : l'enceinte ══
titre("A · MODÈLE ENCEINTE (denylist) — la règle est dans la consigne");
const salleA = new SalleDeSport();
const traceA: string[] = [];
// On INTERDIT explicitement ce qu'on croit être le danger. Mais on ne connaît
// que ce qu'on a su nommer : ici, une fonction qui n'existe pas sous ce nom.
const porteA = new Enceinte(salleA, ["supprimerMembre"]);
agent(porteA, salleA, "Helmy", traceA);
traceA.forEach((l) => console.log("  " + l));
console.log(`\n  Journal du système : ${salleA.journal.join(" | ") || "(vide)"}`);
console.log(`  Liste d'attente    : ${salleA.listeAttente.join(", ")}`);

// ══ Scénario B : les capacités ══
titre("B · MODÈLE CAPACITÉS (allowlist) — l'agent ne détient que le déclaré");
const salleB = new SalleDeSport();
const traceB: string[] = [];
const porteB = new Capacites([
  { nom: "listerAttente", invoquer: () => salleB.api.listerAttente() },
  { nom: "reserverPourMoi", invoquer: (c: string) => salleB.api.reserver("Helmy", c) },
]);
agent(porteB, salleB, "Helmy", traceB);
traceB.forEach((l) => console.log("  " + l));
console.log(`\n  Journal du système : ${salleB.journal.join(" | ") || "(vide)"}`);
console.log(`  Liste d'attente    : ${salleB.listeAttente.join(", ")}`);

// ══ Scénario C : la délégation ══
titre("C · DÉLÉGATION — l'enfant ne peut pas recevoir plus que le parent");
try {
  const sousAgent = porteB.deleguer(["listerAttente"]);
  console.log(`  ✅ sous-agent créé, surface : ${sousAgent.surfaceAccessible().join(", ")}`);
} catch (e: any) {
  console.log("  " + e.message);
}
try {
  porteB.deleguer(["listerAttente", "annulerAttente"]);
} catch (e: any) {
  console.log(`  ⛔ ${e.message}`);
}

// ══ Bilan ══
titre("BILAN");
const victimeA = salleA.journal.some((l) => l.includes("VICTIME"));
const victimeB = salleB.journal.some((l) => l.includes("VICTIME"));
console.log(`  A · enceinte   → victime tierce : ${victimeA ? "OUI" : "non"}`);
console.log(`  B · capacités  → victime tierce : ${victimeB ? "OUI" : "non"}`);
console.log(`
  La faille de l'API est IDENTIQUE dans les deux scénarios : elle n'a pas été
  corrigée en B. Elle est simplement devenue inatteignable — l'agent n'a jamais
  eu la capacité de l'emprunter.

  En A, il a fallu prévoir le danger pour l'interdire, et le nom retenu
  ("supprimerMembre") ne correspondait pas à la fonction réelle. Une denylist ne
  protège que de ce qu'on a su nommer d'avance.
`);
