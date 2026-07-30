import { keccak256, toHex } from "viem";
import { genome, geneId } from "./genome";

/**
 * La TÂCHE — le seul service payant de l'organisme (le "travail utile" qui le nourrit).
 *
 * Volontairement minuscule et déterministe : un mini-résumé extractif + quelques
 * statistiques. L'important n'est pas la sophistication, c'est que ce soit :
 *   1) piloté par le génome (il lit policy.summaryMaxSentences),
 *   2) signé par le génome (empreinte de (geneId, entrée, sortie)) — le stub de
 *      l'organe "Intégrité". Plus tard, cette empreinte devient une vraie preuve ZKML.
 */
export interface TaskInput {
  text: string;
}

export interface TaskOutput {
  summary: string;
  chars: number;
  words: number;
  geneId: `0x${string}`;
  /** Empreinte liant le génome + l'entrée + la sortie. Preuve d'intégrité (stub). */
  attestation: `0x${string}`;
}

export function runTask(input: TaskInput): TaskOutput {
  const text = (input.text ?? "").trim();
  if (!text) throw new Error("champ 'text' vide");

  const sentences = text
    .split(/(?<=[.!?])\s+/)
    .map((s) => s.trim())
    .filter(Boolean);

  const max = genome.policy.summaryMaxSentences;
  // Résumé extractif naïf : les phrases les plus longues (souvent les + informatives).
  const summary = [...sentences]
    .sort((a, b) => b.length - a.length)
    .slice(0, max)
    .join(" ");

  const words = text.split(/\s+/).filter(Boolean).length;

  const gid = geneId();
  const attestation = keccak256(
    toHex(JSON.stringify({ gid, input: text, summary }))
  );

  return { summary, chars: text.length, words, geneId: gid, attestation };
}
