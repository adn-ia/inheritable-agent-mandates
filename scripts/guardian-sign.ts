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
 * Nécessite GUARDIAN_PRIVATE_KEY dans l'environnement — à tenir SÉPARÉ de l'agent.
 */
const pk = process.env.GUARDIAN_PRIVATE_KEY;
if (!pk || pk.startsWith("0x...")) {
  console.error("GUARDIAN_PRIVATE_KEY manquante. Génère-la avec: npm run guardian:new");
  process.exit(1);
}

const account = privateKeyToAccount(pk as `0x${string}`);
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
