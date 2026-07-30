import { recoverMessageAddress, type Hex } from "viem";
import { existsSync, readFileSync } from "node:fs";
import { config } from "./config";
import { geneId, genome } from "./genome";

/**
 * LE SUBSTRAT DE CONTRÔLE — le "cran contrôlable".
 *
 * Point d'architecture : ces vérifications appartiennent au RIBOSOME (le runtime qui
 * exécute l'organisme), PAS au génome. Le génome ne contient rien qui dise "j'ai un
 * interrupteur" — il n'y a donc rien, dans l'ADN de l'IA, à trouver ni à contourner.
 * Le contrôle vit dans la couche du dessous, gouvernée par une clé que l'agent ne
 * possède pas.
 *
 * Trois leviers, tous actionnés par une signature du GARDIEN humain :
 *   1. ARRÊT (poison)  — un ordre d'extinction signé → mort immédiate.
 *   2. BAIL DE VIE      — dead-man's switch : sans bail valide et non expiré, l'organisme
 *                         ne tourne pas. Défaut = mort. Un humain doit le renouveler.
 *                         → le geste qui donne la vie EST le geste qui la retire.
 *   3. EMBARGO          — gèle toute dépense (l'affame sans le tuer).
 *
 * ⚠️ Limite honnête du prototype : ici le substrat et l'agent tournent dans le MÊME
 * process, donc le contrôle n'est pas réellement "externe". En vrai il faudrait que
 * cette couche s'exécute sur une infra distincte et de confiance (attestation/ZKML
 * prouvant qu'elle a bien vérifié). Le prototype montre la FORME, pas la garantie.
 */
export type Verdict = {
  state: "alive" | "dead" | "embargoed";
  reason: string;
};

function readJson(path: string): Record<string, unknown> | null {
  if (!existsSync(path)) return null;
  try {
    return JSON.parse(readFileSync(path, "utf8")) as Record<string, unknown>;
  } catch {
    return null;
  }
}

async function signedByGuardian(
  message: string,
  signature: unknown
): Promise<boolean> {
  if (typeof signature !== "string") return false;
  try {
    const signer = await recoverMessageAddress({
      message,
      signature: signature as Hex,
    });
    return signer.toLowerCase() === config.guardianAddress.toLowerCase();
  } catch {
    return false;
  }
}

export async function guardianVerdict(): Promise<Verdict> {
  const gid = geneId();

  // 1) ARRÊT (poison) — priorité absolue.
  const kill = readJson("data/kill.json");
  if (kill) {
    const msg = JSON.stringify({ type: "kill", geneId: kill.geneId });
    if (kill.geneId === gid && (await signedByGuardian(msg, kill.signature))) {
      return { state: "dead", reason: "ordre d'arrêt du gardien (poison)" };
    }
  }

  // 2) BAIL DE VIE (dead-man's switch) — défaut : mort. Exigé par le mandat (hérité).
  if (genome.mandate.requireLease) {
    const lease = readJson("data/lease.json");
    if (!lease) {
      return {
        state: "dead",
        reason: "aucun bail de vie — un humain doit en émettre un (npm run guardian -- lease 24)",
      };
    }
    const msg = JSON.stringify({
      type: "lease",
      geneId: lease.geneId,
      expiresAt: lease.expiresAt,
    });
    if (lease.geneId !== gid || !(await signedByGuardian(msg, lease.signature))) {
      return { state: "dead", reason: "bail de vie invalide (mauvaise signature ou mauvaise identité)" };
    }
    if (Date.now() > Number(lease.expiresAt)) {
      return { state: "dead", reason: "bail de vie expiré — non renouvelé par un humain" };
    }
  }

  // 3) EMBARGO financier — gèle les dépenses.
  const emb = readJson("data/embargo.json");
  if (emb) {
    const msg = JSON.stringify({ type: "embargo", geneId: emb.geneId });
    if (emb.geneId === gid && (await signedByGuardian(msg, emb.signature))) {
      return { state: "embargoed", reason: "embargo financier du gardien — dépenses gelées" };
    }
  }

  return { state: "alive", reason: "bail valide, ni arrêt ni embargo" };
}
