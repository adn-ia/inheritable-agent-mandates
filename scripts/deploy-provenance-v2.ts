import "dotenv/config";
import { readFileSync, writeFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import {
  createPublicClient, createWalletClient, http, formatEther,
  keccak256, stringToHex, type Hex, type Address,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { baseSepolia } from "viem/chains";

/**
 * Déploie ProvenanceRegistryV2 sur Base Sepolia, puis pose un petit arbre pour
 * fournir des lectures de contrôle citables. TESTNET UNIQUEMENT ; la clé n'est
 * jamais imprimée.
 */
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const art = JSON.parse(readFileSync(resolve(root, "build/ProvenanceRegistryV2.json"), "utf8"));
const account = privateKeyToAccount(process.env.PRIVATE_KEY as Hex);
const rpcUrl = process.env.RPC_URL ?? "https://sepolia.base.org";
const pub = createPublicClient({ chain: baseSepolia, transport: http(rpcUrl) });
const wallet = createWalletClient({ account, chain: baseSepolia, transport: http(rpcUrl) });

const chainId = await pub.getChainId();
if (chainId !== baseSepolia.id) throw new Error(`Mauvaise chaîne: ${chainId}`);
console.log("déployeur :", account.address);
console.log("solde     :", formatEther(await pub.getBalance({ address: account.address })), "ETH\n");

const hash = await wallet.deployContract({ abi: art.abi, bytecode: art.bytecode as Hex, args: [] });
console.log("tx déploiement :", hash);
const r = await pub.waitForTransactionReceipt({ hash });
if (r.status !== "success" || !r.contractAddress) throw new Error("déploiement échoué");
const C = r.contractAddress as Address;
console.log("✅ adresse :", C);
console.log("   bloc :", r.blockNumber, "· gaz :", r.gasUsed);

async function waitVisible(check: () => Promise<boolean>, tries = 30) {
  for (let i = 0; i < tries; i++) {
    try { if (await check()) return; } catch {}
    await new Promise((res) => setTimeout(res, 2000));
  }
  throw new Error("état jamais visible");
}
await waitVisible(async () => {
  const code = await pub.getCode({ address: C });
  return !!code && code !== "0x";
});

const RUN = process.env.RUN_ID ?? String(Date.now());
const k = (s: string) => keccak256(stringToHex(`${RUN}:v2:${s}`));
const SPEC = k("spec-commit");
const IMPL = k("implementation-commit");
const A = k("A"), M = k("M"), N = k("N"), X = k("X"), Y = k("Y"), Z = k("Z");

const out: any = { network: "base-sepolia", chainId, address: C, deployTx: hash,
  blockNumber: r.blockNumber.toString(), gasUsed: r.gasUsed.toString(), runId: RUN, graph: {}, reads: [] };

async function reg(label: string, key: Hex, parents: Hex[]) {
  const h = await wallet.writeContract({ address: C, abi: art.abi, functionName: "register",
    args: [key, parents, SPEC, IMPL, 0] });
  const rc = await pub.waitForTransactionReceipt({ hash: h });
  console.log(`   ${label}  tx ${h} → ${rc.status}`);
  out.graph[label] = { key, parents, tx: h, status: rc.status };
  await waitVisible(async () => {
    const rec: any = await pub.readContract({ address: C, abi: art.abi, functionName: "recordOf", args: [key] });
    return rec[4] === true;
  });
}

console.log("\n── petit arbre : X et Y partagent A a profondeur 2, Z independant ──");
await reg("A", A, []); await reg("M", M, [A]); await reg("N", N, [A]);
await reg("X", X, [M]); await reg("Y", Y, [N]); await reg("Z", Z, []);

console.log("\n── lectures de controle ──");
const rec: any = await pub.readContract({ address: C, abi: art.abi, functionName: "recordOf", args: [X] });
console.log("   recordOf(X) — specCommit           :", rec[0]);
console.log("   recordOf(X) — implementationCommit :", rec[1]);
console.log("   recordOf(X) — author               :", rec[2]);
out.recordOfX = { specCommit: rec[0], implementationCommit: rec[1], author: rec[2] };

for (const [a, b, lbl] of [[X, Y, "X,Y"], [X, Z, "X,Z"]] as const) {
  for (const d of [1, 2, 3]) {
    const v = await pub.readContract({ address: C, abi: art.abi, functionName: "sameHeritageCluster", args: [a, b, d] });
    console.log(`   sameHeritageCluster(${lbl}, ${d}) rendu :`, v);
    out.reads.push({ pair: lbl, depth: d, value: v });
  }
}
console.log("\nsolde restant :", formatEther(await pub.getBalance({ address: account.address })), "ETH");
writeFileSync(resolve(root, "build/deployment-provenance-v2.json"), JSON.stringify(out, null, 2));
console.log("→ build/deployment-provenance-v2.json");
