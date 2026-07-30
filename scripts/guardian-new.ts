import { generatePrivateKey, privateKeyToAccount } from "viem/accounts";

/**
 * Génère la clé du GARDIEN humain.
 *
 * ⚠️ Règle d'or : cette clé privée ne doit JAMAIS se trouver dans l'environnement de
 * l'agent. L'agent ne connaît que l'ADRESSE (publique) du gardien. C'est ce qui
 * l'empêche de se signer son propre bail de vie. Idéalement, garde-la sur une autre
 * machine.
 */
const pk = generatePrivateKey();
const account = privateKeyToAccount(pk);

console.log("Clé du gardien générée (testnet uniquement) :\n");
console.log("→ Dans le .env de l'AGENT, mets seulement l'adresse publique :");
console.log("GUARDIAN_ADDRESS=" + account.address);
console.log("\n→ Garde la clé privée À PART (pas dans le .env de l'agent) pour signer");
console.log("  les baux/arrêts/embargos. Pour l'outil gardien, expose-la via :");
console.log("GUARDIAN_PRIVATE_KEY=" + pk);
