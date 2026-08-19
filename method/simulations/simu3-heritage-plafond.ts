/**
 * SIMULATION 3 — la capacité qui se resserre en se transmettant
 *
 * Reproduit la trouvaille du 14/08 (message #41 du fil ERC-8370) :
 *   « débiter le parent immédiat borne la LARGEUR, pas la PROFONDEUR. »
 *
 * ⚠️ Correction du 16/08 : une première version confondait le budget CONFIÉ à
 *    un enfant et la dépense PROPRE d'un nœud, ce qui faussait les totaux des
 *    scénarios B et C. Deux compteurs distincts désormais :
 *       alloue  = budget confié aux enfants
 *       depense = dépense propre
 *       reste   = plafond − alloue − depense
 *
 * Lancer :  npx tsx notes/simulation-capacites/simu3-heritage-plafond.ts
 */

type Mode = "par-enfant" | "debit-parent" | "debit-lignee";

class Noeud {
  alloue = 0;
  depense = 0;
  constructor(
    public nom: string,
    public plafond: number,
    public telomere: number,
    public parent: Noeud | null = null
  ) {}

  reste() {
    return this.plafond - this.alloue - this.depense;
  }

  depenserTout(): number {
    const m = this.reste();
    this.depense += m;
    return m;
  }

  deleguer(nom: string, plafond: number, mode: Mode): Noeud | string {
    if (this.telomere <= 0) return "télomère épuisé";
    if (plafond > this.plafond) return "plafond enfant > plafond parent";

    if (mode === "debit-parent" || mode === "debit-lignee") {
      if (plafond > this.reste()) return `reste du parent insuffisant (${this.reste()})`;
      this.alloue += plafond;
    }
    if (mode === "debit-lignee") {
      let a = this.parent;
      while (a) {
        if (plafond > a.reste()) return `reste d'un ancêtre insuffisant (${a.nom}: ${a.reste()})`;
        a.alloue += plafond;
        a = a.parent;
      }
    }
    return new Noeud(nom, plafond, this.telomere - 1, this);
  }
}

/** Chaîne de D générations sous la racine ; chacune redemande le plafond max. */
function chaine(mode: Mode, D: number, plafondRacine: number) {
  const racine = new Noeud("racine", plafondRacine, D + 2);
  const lignee: Noeud[] = [racine];
  const refus: string[] = [];
  let courant = racine;

  for (let d = 1; d <= D; d++) {
    const e = courant.deleguer(`gen${d}`, plafondRacine, mode);
    if (typeof e === "string") {
      refus.push(`gen${d} refusée — ${e}`);
      break;
    }
    lignee.push(e);
    courant = e;
  }

  // chaque nœud dépense tout ce qu'il lui reste EN PROPRE
  let total = 0;
  for (const n of lignee) total += n.depenserTout();
  return { lignee, refus, total };
}

const bar = (t: string) => console.log("\n" + "─".repeat(74) + `\n${t}\n` + "─".repeat(74));
const tableau = (l: Noeud[]) =>
  l.forEach((n) =>
    console.log(
      `   ${n.nom.padEnd(8)} plafond ${String(n.plafond).padStart(4)} │ confié ${String(n.alloue).padStart(4)} │ dépensé ${String(n.depense).padStart(4)}`
    )
  );

const P = 100;
const D = 3;

bar(`A · PLAFOND PAR ENFANT SEULEMENT — racine ${P}, ${D} générations sous elle`);
let r = chaine("par-enfant", D, P);
tableau(r.lignee);
console.log(`\n   ⚠️  DÉPENSE RÉELLE DE LA LIGNÉE : ${r.total}   (plafond racine : ${P})`);
console.log(`   ${r.lignee.length} nœuds × ${P} — chacun respecte son plafond, la lignée le dépasse ${r.total / P}×.`);

bar("B · DÉBIT DU PARENT IMMÉDIAT — borne la largeur, pas la profondeur");
r = chaine("debit-parent", D, P);
tableau(r.lignee);
r.refus.forEach((x) => console.log(`   ⛔ ${x}`));
console.log(`\n   DÉPENSE RÉELLE : ${r.total}`);
console.log(`   Le parent confie ${P} et n'a plus rien pour un frère : la LARGEUR est fermée.`);
console.log(`   Mais l'enfant repart d'un compteur à zéro : la PROFONDEUR passe.`);

bar("C · DÉBIT DE TOUTE LA LIGNÉE — borne réellement");
r = chaine("debit-lignee", D, P);
tableau(r.lignee);
r.refus.forEach((x) => console.log(`   ⛔ ${x}`));
console.log(`\n   ✅ DÉPENSE RÉELLE : ${r.total}  — jamais au-dessus de la racine.`);

bar("D · CONVENTION DE COMPTAGE — d'où vient 300 plutôt que 400 ?");
for (const d of [2, 3]) {
  const x = chaine("par-enfant", d, P);
  console.log(`   ${d} génération(s) sous la racine → ${x.lignee.length} nœuds → total ${x.total}`);
}
console.log(`
   Le chiffre publié le 14/08 — « root at 100, three generations, lineage at 300 »
   correspond à TROIS NŒUDS AU TOTAL (racine + 2 descendants), c'est-à-dire deux
   générations sous la racine. Avec trois générations SOUS la racine on obtient
   quatre nœuds, donc 400.
   → « trois générations » y désigne le nombre de nœuds de la lignée, racine
     comprise. Formule : total = (D+1) × plafond, avec D générations sous la racine.
   → Aucune erreur dans le chiffre publié ; c'est une convention à énoncer si le
     texte est repris ailleurs.`);

bar("E · TÉLOMÈRE — indépendant du budget");
const souche = new Noeud("souche", 50, 2);
let c: any = souche;
for (let i = 1; i <= 4; i++) {
  const e = c.deleguer(`g${i}`, 50, "par-enfant");
  if (typeof e === "string") {
    console.log(`   génération ${i} : ⛔ ${e}`);
    break;
  }
  console.log(`   génération ${i} : ✅ créée, télomère restant ${e.telomere}`);
  c = e;
}
console.log(`
   Le télomère borne le NOMBRE de générations, pas la dépense. Les deux limites
   sont indépendantes : l'une ferme la profondeur de la descendance, l'autre la
   profondeur du budget. Il faut les deux.`);
