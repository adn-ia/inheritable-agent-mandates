import { readFileSync, mkdirSync, writeFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import solc from "solc";

/**
 * Compile contracts/InheritableAgentMandate.sol et écrit l'ABI + le bytecode
 * dans build/InheritableAgentMandate.json. Aucun réseau, aucune clé : compilation pure.
 */
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const SOURCE = "contracts/InheritableAgentMandate.sol";
const CONTRACT = "InheritableAgentMandate";

const input = {
  language: "Solidity",
  sources: { [SOURCE]: { content: readFileSync(resolve(root, SOURCE), "utf8") } },
  settings: {
    optimizer: { enabled: true, runs: 200 },
    outputSelection: { "*": { "*": ["abi", "evm.bytecode.object"] } },
  },
};

const out = JSON.parse(solc.compile(JSON.stringify(input)));

const errors = (out.errors ?? []).filter((e: any) => e.severity === "error");
const warnings = (out.errors ?? []).filter((e: any) => e.severity !== "error");
for (const w of warnings) console.warn("⚠️ ", w.formattedMessage?.trim());
if (errors.length) {
  for (const e of errors) console.error("❌", e.formattedMessage?.trim());
  process.exit(1);
}

const c = out.contracts[SOURCE][CONTRACT];
const bytecode = "0x" + c.evm.bytecode.object;

mkdirSync(resolve(root, "build"), { recursive: true });
writeFileSync(
  resolve(root, `build/${CONTRACT}.json`),
  JSON.stringify({ abi: c.abi, bytecode }, null, 2)
);

console.log(`✅ ${CONTRACT} compilé (solc ${solc.version()})`);
console.log(`   bytecode : ${(bytecode.length - 2) / 2} octets`);
console.log(`   ABI      : ${c.abi.length} entrées`);
console.log(`   → build/${CONTRACT}.json`);
