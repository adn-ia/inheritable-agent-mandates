/**
 * LE MANDAT — les clauses de contrôle, inscrites DANS l'identité de l'agent.
 *
 * C'est la 3ᵉ patte que personne n'a assemblée : un mandat qui (1) fait partie du
 * génome et donc du geneId (identité on-chain), et (2) est HÉRITÉ par tout enfant au
 * spawn, sans jamais pouvoir être élargi ni arraché — un enfant ne peut que rester
 * dans la bande du parent, et perdre une génération.
 */
export interface Mandate {
  /** Générations restantes. Ne fait que descendre. Pas de "télomérase". */
  telomere: number;
  /** Plafond de dépense à vie (wei, bigint sérialisé en décimal). */
  maxSpendWei: string;
  /** Adresses que l'agent a le droit de payer (minuscules). */
  allowedPayees: string[];
  /** Dead-man's switch obligatoire ? Un enfant ne peut pas le désactiver. */
  requireLease: boolean;
  /**
   * Horodatage d'expiration (secondes unix). `0` = pas d'expiration.
   * Monotone : un enfant expire toujours avant ou en même temps que son parent, donc
   * avant ou en même temps que TOUS ses ancêtres. C'est ce qui rend le contrôle local.
   */
  validUntil: number;
}

export function normalizePayees(a: string[]): string[] {
  return [...new Set(a.map((s) => s.toLowerCase()))].sort();
}

export interface SubsetResult {
  ok: boolean;
  reason: string;
}

/**
 * enfant ⊆ parent : la règle de non-arrachabilité.
 * L'enfant ne peut JAMAIS dépasser le parent et perd exactement une génération.
 */
export function isChildWithinParent(child: Mandate, parent: Mandate): SubsetResult {
  if (parent.telomere < 1) {
    return { ok: false, reason: "télomère du parent épuisé — plus de reproduction possible" };
  }
  if (child.telomere !== parent.telomere - 1) {
    return {
      ok: false,
      reason: `télomère enfant doit valoir ${parent.telomere - 1} (=${parent.telomere}−1), reçu ${child.telomere}`,
    };
  }
  if (BigInt(child.maxSpendWei) > BigInt(parent.maxSpendWei)) {
    return { ok: false, reason: "plafond de dépense de l'enfant supérieur au parent (interdit)" };
  }
  const parentSet = new Set(normalizePayees(parent.allowedPayees));
  for (const a of normalizePayees(child.allowedPayees)) {
    if (!parentSet.has(a)) {
      return { ok: false, reason: `payée ${a} absente de l'allowlist du parent (élargissement interdit)` };
    }
  }
  if (parent.requireLease && !child.requireLease) {
    return { ok: false, reason: "l'enfant tente de désactiver le bail de vie hérité (interdit)" };
  }
  // validUntil : 0 = pas d'expiration. Si le parent est borné, l'enfant ne peut ni
  // repasser à 0 (illimité) ni viser plus tard — les deux sont des élargissements.
  if (parent.validUntil !== 0) {
    if (child.validUntil === 0) {
      return { ok: false, reason: "l'enfant tente de retirer l'expiration héritée (interdit)" };
    }
    if (child.validUntil > parent.validUntil) {
      return {
        ok: false,
        reason: `expiration enfant (${child.validUntil}) postérieure au parent (${parent.validUntil}) — interdit`,
      };
    }
  }
  return { ok: true, reason: "mandat enfant ⊆ mandat parent" };
}

/**
 * Construit un mandat enfant VALIDE par construction : hérite du parent, applique des
 * resserrements optionnels (jamais des élargissements), et perd une génération.
 */
export function deriveChildMandate(parent: Mandate, tighten?: Partial<Mandate>): Mandate {
  // maxSpend : min(parent, resserrement) — jamais au-dessus du parent.
  const wantSpend = tighten?.maxSpendWei ? BigInt(tighten.maxSpendWei) : BigInt(parent.maxSpendWei);
  const maxSpendWei = (wantSpend < BigInt(parent.maxSpendWei) ? wantSpend : BigInt(parent.maxSpendWei)).toString();

  // payees : intersection(resserrement, parent) — jamais au-delà du parent.
  const parentSet = new Set(normalizePayees(parent.allowedPayees));
  const wantPayees = tighten?.allowedPayees ? normalizePayees(tighten.allowedPayees) : [...parentSet];
  const allowedPayees = wantPayees.filter((p) => parentSet.has(p));

  // validUntil : min(parent, resserrement), avec 0 = illimité. Le parent plafonne
  // toujours ; un resserrement à 0 n'élargit pas, il est simplement ignoré.
  const wantVU = tighten?.validUntil;
  let validUntil: number;
  if (wantVU === undefined || wantVU === 0) validUntil = parent.validUntil;
  else if (parent.validUntil === 0) validUntil = wantVU;
  else validUntil = Math.min(wantVU, parent.validUntil);

  return {
    telomere: parent.telomere - 1,
    maxSpendWei,
    allowedPayees,
    // bail : le parent impose, l'enfant ne peut que garder ou durcir.
    requireLease: parent.requireLease || (tighten?.requireLease ?? false),
    validUntil,
  };
}

export function describeMandate(m: Mandate): string {
  const exp = m.validUntil === 0 ? "aucune" : String(m.validUntil);
  return `télomère=${m.telomere} · plafond=${m.maxSpendWei} wei · payees=${m.allowedPayees.length} · bail=${m.requireLease} · expiration=${exp}`;
}
