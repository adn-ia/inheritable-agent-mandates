import { existsSync, readFileSync, appendFileSync, writeFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";
import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";

/**
 * Génère UNE clé de déploiement mainnet dédiée et l'écrit dans .env (gitignoré).
 * La clé n'est JAMAIS affichée : seule l'adresse publique l'est.
 *
 * Refuse d'écraser une clé existante — une clé mainnet écrasée par accident, c'est
 * un contrat orphelin et un déployeur qu'on ne contrôle plus.
 *
 * Garde-fous vérifiés AVANT d'écrire quoi que ce soit :
 *   - .env est bien ignoré par git ;
 *   - .env n'est pas suivi ;
 *   - .env n'a jamais existé dans l'historique.
 * Si l'un d'eux tombe, le script s'arrête sans rien générer.
 */
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const envPath = resolve(root, ".env");
const VAR = "MAINNET_DEPLOYER_KEY";

const git = (args: string[]) => {
  try {
    return { ok: true, out: execFileSync("git", args, { cwd: root, encoding: "utf8" }).trim() };
  } catch (e: any) {
    return { ok: false, out: String(e?.stdout ?? "").trim() };
  }
};

console.log("Garde-fous :");
const ignored = git(["check-ignore", "-q", ".env"]).ok;
console.log(`  .env ignoré par git            : ${ignored ? "oui" : "NON"}`);
const tracked = git(["ls-files", "--error-unmatch", ".env"]).ok;
console.log(`  .env suivi par git             : ${tracked ? "OUI" : "non"}`);
const history = git(["log", "--all", "--pretty=format:%H", "--", ".env"]).out;
const inHistory = history.length > 0;
console.log(`  .env présent dans l'historique  : ${inHistory ? "OUI" : "non"}`);

if (!ignored || tracked || inHistory) {
  console.error("\n❌ Garde-fou en défaut — aucune clé générée.");
  process.exit(1);
}

const current = existsSync(envPath) ? readFileSync(envPath, "utf8") : "";
if (new RegExp(`^${VAR}=0x[0-9a-fA-F]{64}\\s*$`, "m").test(current)) {
  const existing = current.match(new RegExp(`^${VAR}=(0x[0-9a-fA-F]{64})`, "m"))![1] as `0x${string}`;
  console.error(`\n❌ ${VAR} existe déjà dans .env — rien n'a été modifié.`);
  console.error(`   adresse existante : ${privateKeyToAccount(existing).address}`);
  console.error("   Supprime la ligne à la main pour en régénérer une.");
  process.exit(1);
}

const pk = generatePrivateKey();
const account = privateKeyToAccount(pk);
const block = `\n# --- déploiement mainnet, clé dédiée (générée automatiquement) ---\n${VAR}=${pk}\n`;
if (current) appendFileSync(envPath, block);
else writeFileSync(envPath, block.trimStart(), { mode: 0o600 });

console.log("\n✅ Clé de déploiement mainnet générée, écrite dans .env (gitignoré, non affichée).\n");
console.log(`   adresse : ${account.address}`);
console.log("\n   Solde attendu : 0. Rien n'est déployé par ce script.");
