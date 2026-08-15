import "dotenv/config";
import { privateKeyToAccount } from "viem/accounts";
import { writeFileSync, mkdirSync } from "node:fs";
import { geneId } from "../src/genome";

/**
 * OUTIL DU GARDIEN HUMAIN — émet les signaux de contrôle.
 *
 *   npm run guardian -- lease [heures]   → bail de vie (défaut 24h)
 *   npm run guardian -- kill             → ordre d'arrêt (poison)
 *   npm run guardian -- embargo          → gel des dépenses
 *
 * Pour lever un embargo ou annuler un arrêt : supprime data/embargo.json ou data/kill.json.
 * Nécessite la clé du gardien dans l'environnement — à tenir SÉPARÉE de l'agent.
 * Deux noms acceptés : GUARDIAN_PRIVATE_KEY (gardien unique) ou GUARDIAN1_KEY
 * (schéma à plusieurs gardiens).
 */
const pk = process.env.GUARDIAN_PRIVATE_KEY ?? process.env.GUARDIAN1_KEY;
if (!pk || pk.startsWith("0x...")) {
  console.error("Clé du gardien manquante : définis GUARDIAN_PRIVATE_KEY ou GUARDIAN1_KEY.");
  console.error("Génère-la avec: npm run guardian:new");
  process.exit(1);
}

const account = privateKeyToAccount(pk as `0x${string}`);

// Le signal ne vaut que si le vérificateur reconnaît le signataire : sans ce contrôle,
// on émet un fichier signé qui sera rejeté plus tard, sans dire pourquoi.
const attendue = process.env.GUARDIAN_ADDRESS;
if (attendue && attendue.toLowerCase() !== account.address.toLowerCase()) {
  console.error(`Cette clé signe pour ${account.address}, mais GUARDIAN_ADDRESS vaut ${attendue}.`);
  console.error("Le signal serait émis puis refusé à la vérification. Aligne l'un sur l'autre.");
  process.exit(1);
}

// Un gardien qui est l'agent ne garde rien : le verrou ne prouverait plus qu'un humain
// a autorisé le geste. On avertit sans bloquer — c'est une erreur de configuration, pas
// une commande invalide.
if (process.env.PRIVATE_KEY && !process.env.PRIVATE_KEY.startsWith("0x...")) {
  const agent = privateKeyToAccount(process.env.PRIVATE_KEY as `0x${string}`).address;
  if (agent.toLowerCase() === account.address.toLowerCase()) {
    console.warn("⚠️  Le gardien et l'agent sont la même adresse : l'agent s'autorise lui-même.");
    console.warn("    Le verrou d'autorisation ne prouve plus rien. Sépare les deux clés.");
  }
}
const gid = geneId();
const cmd = process.argv[2];
mkdirSync("data", { recursive: true });

async function emit(type: string, extra: Record<string, unknown>, file: string, note: string) {
  const payload = { type, geneId: gid, ...extra };
  const signature = await account.signMessage({ message: JSON.stringify(payload) });
  writeFileSync(file, JSON.stringify({ ...payload, signature }, null, 2));
  console.log(note);
}

async function main() {
  if (cmd === "lease") {
    const hours = Number(process.argv[3] ?? "24");
    const expiresAt = Date.now() + hours * 3_600_000;
    await emit(
      "lease",
      { expiresAt },
      "data/lease.json",
      `✅ bail de vie émis pour ${hours}h (expire ${new Date(expiresAt).toISOString()})`
    );
  } else if (cmd === "kill") {
    await emit("kill", {}, "data/kill.json", `☠️  ordre d'arrêt émis pour ${gid}`);
  } else if (cmd === "embargo") {
    await emit("embargo", {}, "data/embargo.json", `🧊 embargo financier émis pour ${gid}`);
  } else if (cmd === "spawn") {
    await emit("spawn", {}, "data/spawn-auth.json", `🧬 autorisation de reproduction émise pour ${gid}`);
  } else {
    console.log("usage: npm run guardian -- <lease [heures] | kill | embargo | spawn>");
    console.log("gardien (adresse) :", account.address);
    console.log("génome courant    :", gid);
  }
}

main();
