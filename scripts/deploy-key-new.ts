import { existsSync, readFileSync, appendFileSync, writeFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";

/**
 * Génère une clé JETABLE de déploiement (Base Sepolia, testnet uniquement) et l'écrit
 * directement dans .env (gitignoré). La clé privée n'est JAMAIS affichée : seule
 * l'adresse à financer est imprimée.
 *
 * Refuse d'écraser un PRIVATE_KEY existant.
 */
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const envPath = resolve(root, ".env");

const current = existsSync(envPath) ? readFileSync(envPath, "utf8") : "";
if (/^PRIVATE_KEY=0x[0-9a-fA-F]{64}\s*$/m.test(current)) {
  console.error("❌ Un PRIVATE_KEY existe déjà dans .env — rien n'a été modifié.");
  console.error("   Supprime-le à la main si tu veux repartir d'une clé neuve.");
  process.exit(1);
}

const pk = generatePrivateKey();
const account = privateKeyToAccount(pk);

// Le déployeur est aussi le gardien du contrat (démo testnet à une seule clé).
const block =
  `\n# --- déploiement testnet Base Sepolia (clé jetable, générée automatiquement) ---\n` +
  `PRIVATE_KEY=${pk}\n` +
  `GUARDIAN_ADDRESS=${account.address}\n`;

if (current) appendFileSync(envPath, block);
else writeFileSync(envPath, block.trimStart(), { mode: 0o600 });

console.log("✅ Clé de déploiement générée et écrite dans .env (gitignoré, non affichée).");
console.log("");
console.log("ADRESSE À FINANCER :", account.address);
console.log("");
console.log("Faucets Base Sepolia (gratuits) :");
console.log("  https://www.alchemy.com/faucets/base-sepolia");
console.log("  https://faucet.quicknode.com/base/sepolia");
console.log("");
console.log("~0.005 ETH de testnet suffisent largement pour le déploiement + la démo.");
