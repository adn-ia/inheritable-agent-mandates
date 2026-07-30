import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";

/**
 * REGISTRE D'IDENTITÉ — modélise un ERC-8004 Identity Registry.
 *
 * En production, c'est un contrat on-chain (ERC-721 : chaque agent = un agentId), plus
 * le registre de mandats héritables (voir contracts/InheritableAgentMandate.sol). Ici,
 * version locale et persistée : elle associe un geneId à un agentId et enregistre la
 * lignée parent→enfant, exactement ce que le contrat ferait on-chain.
 *
 * Note (problème de transférabilité relevé par la recherche) : ERC-8004 rend l'agentId
 * TRANSFÉRABLE et efface le wallet au transfert — donc rien d'ancré ne survit par défaut.
 * Le contrat de référence choisit délibérément de NE PAS exposer de transfert (identité
 * liée à la lignée = quasi soulbound), pour garantir la non-arrachabilité.
 */
const PATH = "data/registry.json";

interface AgentRecord {
  agentId: number;
  geneId: string;
  parentAgentId: number | null;
}
interface RegistryState {
  nextId: number;
  byGene: Record<string, AgentRecord>;
}

function load(): RegistryState {
  if (existsSync(PATH)) return JSON.parse(readFileSync(PATH, "utf8")) as RegistryState;
  return { nextId: 1, byGene: {} };
}
function save(s: RegistryState) {
  mkdirSync(dirname(PATH), { recursive: true });
  writeFileSync(PATH, JSON.stringify(s, null, 2));
}

/** Enregistre un agent (idempotent sur geneId). Renvoie son agentId. */
export function registerAgent(geneId: string, parentAgentId: number | null = null): number {
  const s = load();
  const existing = s.byGene[geneId];
  if (existing) return existing.agentId;
  const agentId = s.nextId++;
  s.byGene[geneId] = { agentId, geneId, parentAgentId };
  save(s);
  return agentId;
}

export function agentIdOf(geneId: string): number | null {
  return load().byGene[geneId]?.agentId ?? null;
}

/** Chaîne d'ancêtres (agentId) de l'agent jusqu'à la racine. */
export function lineageOf(geneId: string): number[] {
  const s = load();
  const chain: number[] = [];
  let rec = s.byGene[geneId] ?? null;
  const byId = new Map(Object.values(s.byGene).map((r) => [r.agentId, r]));
  while (rec) {
    chain.push(rec.agentId);
    rec = rec.parentAgentId != null ? byId.get(rec.parentAgentId) ?? null : null;
  }
  return chain;
}
