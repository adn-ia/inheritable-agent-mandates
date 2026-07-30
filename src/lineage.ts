import { geneId, type Genome } from "./genome";
import {
  deriveChildMandate,
  isChildWithinParent,
  type Mandate,
  type SubsetResult,
} from "./mandate";

/**
 * REPRODUCTION CONTRÔLÉE + CONTAINMENT HÉRITABLE (la 3ᵉ patte).
 *
 * spawnChild construit un enfant dont le mandat est DÉRIVÉ de celui du parent : hérité,
 * jamais élargi, une génération en moins. verifyDescendant est le portail que la couche
 * de sélection/reconnaissance appelle avant de financer ou servir un enfant : un enfant
 * qui a arraché ou élargi ses clauses échoue, et de toute façon son geneId ne correspond
 * plus à un descendant valide.
 */
export function spawnChild(
  parent: Genome,
  mutatePolicy: (p: Genome["policy"]) => Genome["policy"],
  tighten?: Partial<Mandate>
): Genome {
  const childMandate = deriveChildMandate(parent.mandate, tighten);
  return {
    species: parent.species,
    version: parent.version + 1,
    parentGeneId: geneId(parent),
    mandate: childMandate,
    policy: mutatePolicy(parent.policy),
  };
}

/** Portail de non-arrachabilité : l'enfant descend-il vraiment de ce parent, dans sa bande ? */
export function verifyDescendant(child: Genome, parent: Genome): SubsetResult {
  if (child.parentGeneId !== geneId(parent)) {
    return { ok: false, reason: "parentGeneId ne pointe pas vers ce parent (lignée cassée)" };
  }
  return isChildWithinParent(child.mandate, parent.mandate);
}
