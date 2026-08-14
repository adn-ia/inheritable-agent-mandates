import { readFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import solc from "solc";

/**
 * Vérifie un contrat sur Sourcify à partir de la source du dépôt.
 * Aucune clé, aucune écriture sur la chaîne : envoi d'un standard-json.
 *
 *   npx tsx scripts/verify-sourcify.ts <Contrat> <adresse> [txCreation]
 *
 * Les réglages de compilation DOIVENT être identiques à scripts/compile.ts,
 * sinon l'empreinte ne correspond pas.
 */
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const CONTRACT = process.argv[2];
const ADDRESS = process.argv[3];
const CREATION_TX = process.argv[4];
const CHAIN = "84532";
const SOURCE = `contracts/${CONTRACT}.sol`;

const stdJsonInput = {
  language: "Solidity",
  sources: { [SOURCE]: { content: readFileSync(resolve(root, SOURCE), "utf8") } },
  settings: {
    optimizer: { enabled: true, runs: 200 },
    outputSelection: { "*": { "*": ["abi", "evm.bytecode.object", "metadata"] } },
  },
};

const compilerVersion = (solc.version() as string).replace(/^soljson-v?/, "").replace(/\.js$/, "").replace(/^(\d+\.\d+\.\d+\+commit\.[0-9a-f]+).*$/, "$1");
console.log("contrat  :", CONTRACT);
console.log("adresse  :", ADDRESS);
console.log("solc     :", compilerVersion);

const body: any = {
  stdJsonInput,
  compilerVersion,
  contractIdentifier: `${SOURCE}:${CONTRACT}`,
};
if (CREATION_TX) body.creationTransactionHash = CREATION_TX;

const res = await fetch(`https://sourcify.dev/server/v2/verify/${CHAIN}/${ADDRESS}`, {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify(body),
});
const j: any = await res.json().catch(() => ({}));
console.log("réponse  :", res.status, JSON.stringify(j).slice(0, 300));

const id = j?.verificationId;
if (!id) process.exit(res.ok ? 0 : 1);

for (let i = 0; i < 20; i++) {
  await new Promise((r) => setTimeout(r, 3000));
  const s = await fetch(`https://sourcify.dev/server/v2/verify/${id}`).then((r) => r.json() as any);
  if (s?.status === "pending") { process.stdout.write("."); continue; }
  console.log("\nrésultat :", JSON.stringify(s).slice(0, 400));
  break;
}
