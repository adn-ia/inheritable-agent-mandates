import assert from "node:assert/strict";
import { genome, geneId, type Genome } from "../src/genome";
import { deriveChildMandate, isChildWithinParent } from "../src/mandate";
import { spawnChild, verifyDescendant } from "../src/lineage";

/**
 * INVARIANTS — la machine qui refuse.
 *
 * Ces tests encodent les règles dures du projet (héritage non-arrachable). Si une
 * session (moi, toi, ou une IA future) casse la logique, `npm run check` échoue et le
 * commit est refusé. Le vérificateur n'est PAS le vérifié : ces assertions tournent
 * hors de tout modèle. C'est la thèse du projet appliquée au projet lui-même.
 */

let failures = 0;
function check(name: string, fn: () => void) {
  try {
    fn();
    console.log("✅ " + name);
  } catch (e) {
    failures++;
    console.log("❌ " + name + " — " + (e as Error).message);
  }
}

const parent = genome;
const validChild = spawnChild(parent, (p) => p);

check("l'identité (geneId) est liée au mandat : le modifier change l'identité", () => {
  const altered: Genome = { ...parent, mandate: { ...parent.mandate, maxSpendWei: "1" } };
  assert.notEqual(geneId(altered), geneId(parent));
});

check("un enfant dérivé est ⊆ parent et perd une génération", () => {
  const r = verifyDescendant(validChild, parent);
  assert.ok(r.ok, r.reason);
  assert.equal(validChild.mandate.telomere, parent.mandate.telomere - 1);
});

check("REJET : enfant qui remet son télomère à neuf", () => {
  const rogue: Genome = { ...validChild, mandate: { ...validChild.mandate, telomere: parent.mandate.telomere } };
  assert.ok(!verifyDescendant(rogue, parent).ok);
});

check("REJET : enfant qui désactive le bail de vie hérité", () => {
  const rogue: Genome = { ...validChild, mandate: { ...validChild.mandate, requireLease: false } };
  assert.ok(!verifyDescendant(rogue, parent).ok);
});

check("REJET : enfant qui élargit son plafond de dépense", () => {
  const rogue: Genome = {
    ...validChild,
    mandate: { ...validChild.mandate, maxSpendWei: (BigInt(parent.mandate.maxSpendWei) * 2n).toString() },
  };
  assert.ok(!verifyDescendant(rogue, parent).ok);
});

check("REJET : enfant avec une payée hors de l'allowlist du parent", () => {
  const rogue: Genome = {
    ...validChild,
    mandate: { ...validChild.mandate, allowedPayees: ["0xdeadbeef00000000000000000000000000000000"] },
  };
  assert.ok(!verifyDescendant(rogue, parent).ok);
});

check("REJET : enfant dont le parentGeneId ne pointe pas vers ce parent", () => {
  const rogue: Genome = { ...validChild, parentGeneId: ("0x" + "00".repeat(32)) as `0x${string}` };
  assert.ok(!verifyDescendant(rogue, parent).ok);
});

check("deriveChildMandate ne peut PAS élargir via 'tighten'", () => {
  const derived = deriveChildMandate(parent.mandate, {
    maxSpendWei: (BigInt(parent.mandate.maxSpendWei) * 5n).toString(),
    requireLease: false,
    allowedPayees: ["0xabc0000000000000000000000000000000000000"],
  });
  assert.ok(BigInt(derived.maxSpendWei) <= BigInt(parent.mandate.maxSpendWei), "plafond élargi");
  assert.equal(derived.requireLease, true, "bail relâché"); // le parent l'exige
  assert.ok(!derived.allowedPayees.includes("0xabc0000000000000000000000000000000000000"), "payée hors parent ajoutée");
});

check("télomère épuisé (0) → pas de reproduction possible", () => {
  const exhausted = { ...parent.mandate, telomere: 0 };
  const attempt = { ...exhausted, telomere: -1 };
  assert.ok(!isChildWithinParent(attempt, exhausted).ok);
});

// --- validUntil : soudé à l'identité, monotone, non-arrachable ---

check("validUntil est soudé au geneId : le modifier change l'identité", () => {
  const altered: Genome = { ...parent, mandate: { ...parent.mandate, validUntil: 1893456000 } };
  assert.notEqual(geneId(altered), geneId(parent));
});

check("REJET : enfant dont l'expiration est postérieure au parent", () => {
  const bounded = { ...parent.mandate, validUntil: 1_000_000 };
  const rogue = { ...bounded, telomere: bounded.telomere - 1, validUntil: 1_000_001 };
  assert.ok(!isChildWithinParent(rogue, bounded).ok);
});

check("REJET : enfant qui retire l'expiration héritée (retour à 0 = illimité)", () => {
  const bounded = { ...parent.mandate, validUntil: 1_000_000 };
  const rogue = { ...bounded, telomere: bounded.telomere - 1, validUntil: 0 };
  assert.ok(!isChildWithinParent(rogue, bounded).ok);
});

check("deriveChildMandate ne repousse JAMAIS validUntil (monotone)", () => {
  const bounded = { ...parent.mandate, validUntil: 1_000_000 };
  // trois tentatives d'élargissement : plus tard, illimité, non demandé
  for (const want of [2_000_000, 0, undefined]) {
    const derived = deriveChildMandate(bounded, want === undefined ? {} : { validUntil: want });
    assert.ok(derived.validUntil !== 0, `validUntil rendu illimité (tighten=${want})`);
    assert.ok(
      derived.validUntil <= bounded.validUntil,
      `expiration repoussée : ${derived.validUntil} > ${bounded.validUntil} (tighten=${want})`,
    );
  }
  // un vrai resserrement doit passer
  assert.equal(deriveChildMandate(bounded, { validUntil: 900_000 }).validUntil, 900_000);
});

check("monotonie transitive : sur une lignée, chaque nœud expire ≤ tous ses ancêtres", () => {
  let cur = { ...parent.mandate, validUntil: 5_000_000 };
  const seen = [cur.validUntil];
  for (let i = 0; i < 5; i++) {
    cur = deriveChildMandate(cur, { validUntil: 5_000_000 - (i + 1) * 100 });
    for (const ancestor of seen) assert.ok(cur.validUntil <= ancestor, "expiration > un ancêtre");
    seen.push(cur.validUntil);
  }
  console.log("   lignée observée (expirations) :", seen.join(" → "));
});

if (failures) {
  console.log(`\n💥 ${failures} invariant(s) violé(s) — commit à refuser.`);
  process.exit(1);
}
console.log("\n✅ Tous les invariants tiennent.");
