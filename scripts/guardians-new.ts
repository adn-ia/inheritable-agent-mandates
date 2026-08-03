import { existsSync, readFileSync, appendFileSync, writeFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";

/**
 * Génère trois clés JETABLES de gardiens (Base Sepolia, testnet uniquement) et les
 * écrit dans .env (gitignoré). Les clés ne sont JAMAIS affichées : seules les
 * adresses le sont.
 *
 * Refuse d'écraser des clés gardiennes existantes.
 */
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const envPath = resolve(root, ".env");
const current = existsSync(envPath) ? readFileSync(envPath, "utf8") : "";

if (/^GUARDIAN1_KEY=0x[0-9a-fA-F]{64}\s*$/m.test(current)) {
  console.error("❌ Des clés gardiennes existent déjà dans .env — rien n'a été modifié.");
  console.error("   Supprime-les à la main pour repartir de zéro.");
  process.exit(1);
}

const lines: string[] = ["\n# --- gardiens jetables, testnet Base Sepolia (générés automatiquement) ---"];
const addresses: string[] = [];

for (let i = 1; i <= 3; i++) {
  const pk = generatePrivateKey();
  const account = privateKeyToAccount(pk);
  lines.push(`GUARDIAN${i}_KEY=${pk}`);
  addresses.push(account.address);
}

const block = lines.join("\n") + "\n";
if (current) appendFileSync(envPath, block);
else writeFileSync(envPath, block.trimStart(), { mode: 0o600 });

console.log("✅ Trois clés gardiennes générées, écrites dans .env (gitignoré, non affichées).\n");
addresses.forEach((a, i) => console.log(`   gardien ${i + 1} : ${a}`));
console.log("\nTestnet uniquement — ces clés ne doivent jamais recevoir autre chose que du gaz de test.");
