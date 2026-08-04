import { keccak256, toHex } from "viem";
import type { Mandate } from "./mandate";

/**
 * Le GÉNOME de l'organisme — et son MANDAT de contrôle, inscrit DEDANS.
 *
 * Point-clé (la 3ᵉ patte) : le mandat (clauses de contrôle) fait partie du génome,
 * donc du geneId. L'identité de l'agent EST le hash de {politique + mandat}. Conséquence :
 *   - l'IA ne peut pas s'arracher ses clauses sans changer d'identité,
 *   - et tout enfant hérite du mandat au spawn (voir lineage.ts), sans pouvoir l'élargir.
 *
 * En production, ce génome (ou son empreinte) vit sur Arweave et le mandat est ancré sur
 * une identité ERC-8004 (voir identity.ts et contracts/InheritableAgentMandate.sol).
 */
export interface Genome {
  species: string;
  version: number;
  /** geneId du parent, ou null pour un organisme-racine. Trace la lignée. */
  parentGeneId: `0x${string}` | null;
  /** Les clauses de contrôle, inscrites dans l'identité et héritables. */
  mandate: Mandate;
  /** Le comportement (ce que lit la tâche). */
  policy: {
    summaryMaxSentences: number;
    tone: "neutre" | "concis";
  };
}

export const genome: Genome = {
  species: "adn-ia",
  version: 1,
  parentGeneId: null,
  mandate: {
    telomere: 8,
    maxSpendWei: "10000000000000000", // = 0.01 ETH
    allowedPayees: [],
    requireLease: true,
    validUntil: 0, // 0 = pas d'expiration ; toute valeur non nulle se transmet en se resserrant
  },
  policy: {
    summaryMaxSentences: 2,
    tone: "concis",
  },
};

/** Empreinte déterministe du génome (mandat inclus) — le "geneId" / identité de l'agent. */
export function geneId(g: Genome = genome): `0x${string}` {
  return keccak256(toHex(JSON.stringify(g)));
}
