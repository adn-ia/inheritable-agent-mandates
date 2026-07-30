import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";

/**
 * Fabrique une nouvelle "graine" pour l'organisme : une clé privée + son adresse.
 * Colle la clé dans .env (PRIVATE_KEY=...). TESTNET UNIQUEMENT — ne jamais
 * financer une clé générée comme ça avec de l'argent réel.
 */
const pk = generatePrivateKey();
const account = privateKeyToAccount(pk);

console.log("Nouvelle graine générée (testnet uniquement) :\n");
console.log("PRIVATE_KEY=" + pk);
console.log("adresse     =", account.address);
console.log("\n→ Copie la ligne PRIVATE_KEY dans ton fichier .env");
console.log("→ Puis alimente l'adresse au faucet : https://www.alchemy.com/faucets/base-sepolia");
