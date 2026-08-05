import "dotenv/config";
import { existsSync, readFileSync, writeFileSync, appendFileSync, mkdirSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import {
  createPublicClient, createWalletClient, http, formatEther, parseEther,
  encodeFunctionData, encodePacked, keccak256, encodeAbiParameters, parseAbiParameters,
  type Hex, type Address,
} from "viem";
import { privateKeyToAccount, generatePrivateKey } from "viem/accounts";
import { baseSepolia } from "viem/chains";

/**
 * Déploie MandateGate sur Base Sepolia et l'exerce — preuve live minimale.
 *
 * Le contrat de référence v1 (0x2d463db5…) est LU, jamais écrit : la démonstration
 * réutilise des agents qui y existent déjà (2 = racine, 3 = son enfant), donc AUCUNE
 * transaction n'est envoyée vers v1. TESTNET UNIQUEMENT ; aucune clé n'est imprimée.
 */
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const art = JSON.parse(readFileSync(resolve(root, "build/MandateGate.json"), "utf8"));
const abi = art.abi;

const V1 = "0x2d463db56fadb55cd451d2c3237ec2213ba3bda9" as Address;
const PAYEE = "0x000000000000000000000000000000000000dEaD" as Address;
const PARENT_ID = 2n;
const CHILD_ID = 3n;

const account = privateKeyToAccount(process.env.PRIVATE_KEY as Hex);
const rpcUrl = process.env.RPC_URL ?? "https://sepolia.base.org";
const pub = createPublicClient({ chain: baseSepolia, transport: http(rpcUrl) });
const wallet = createWalletClient({ account, chain: baseSepolia, transport: http(rpcUrl) });

const chainId = await pub.getChainId();
if (chainId !== baseSepolia.id) throw new Error(`Mauvaise chaîne : ${chainId}`);

// ─── clé d'émetteur jetable : générée si absente, JAMAIS imprimée ───
const envPath = resolve(root, ".env");
let issuerPk = process.env.ISSUER_KEY as Hex | undefined;
if (!issuerPk) {
  issuerPk = generatePrivateKey();
  const block = `\n# --- emetteur de verdicts, jetable, testnet Base Sepolia ---\nISSUER_KEY=${issuerPk}\n`;
  if (existsSync(envPath)) appendFileSync(envPath, block);
  else writeFileSync(envPath, block.trimStart(), { mode: 0o600 });
  console.log("clé d'émetteur générée et écrite dans .env (gitignoré, non affichée)");
}
const issuer = privateKeyToAccount(issuerPk);

console.log("déployeur / gardien :", account.address);
console.log("émetteur autorisé   :", issuer.address);
console.log("solde               :", formatEther(await pub.getBalance({ address: account.address })), "ETH\n");

const out: any = {
  network: "base-sepolia", chainId, deployer: account.address,
  guardian: account.address, issuer: issuer.address, mandateV1: V1, steps: {},
};

// ─── déploiement ───
const deployHash = await wallet.deployContract({
  abi, bytecode: art.bytecode as Hex, args: [V1, account.address],
});
console.log("tx déploiement :", deployHash);
const dr = await pub.waitForTransactionReceipt({ hash: deployHash });
if (dr.status !== "success" || !dr.contractAddress) throw new Error("déploiement échoué");
const C = dr.contractAddress as Address;
console.log("✅ adresse :", C, "· bloc", dr.blockNumber, "· gaz", dr.gasUsed);
Object.assign(out, {
  address: C, deployTx: deployHash,
  blockNumber: dr.blockNumber.toString(), deployGas: dr.gasUsed.toString(),
});

async function waitVisible(check: () => Promise<boolean>, tries = 40) {
  for (let i = 0; i < tries; i++) {
    try { if (await check()) return; } catch {}
    await new Promise((r) => setTimeout(r, 2000));
  }
  throw new Error("état jamais visible");
}
await waitVisible(async () => {
  const code = await pub.getCode({ address: C });
  return !!code && code !== "0x";
});
out.codeSize = ((await pub.getCode({ address: C }))!.length - 2) / 2;
console.log("   taille du code :", out.codeSize, "octets");

const read = (fn: string, args: any[]) =>
  pub.readContract({ address: C, abi, functionName: fn, args }) as Promise<any>;

async function send(label: string, fn: string, args: any[]) {
  const h = await wallet.writeContract({ address: C, abi, functionName: fn, args });
  const rc = await pub.waitForTransactionReceipt({ hash: h });
  console.log(`   ${label} → ${rc.status}  tx ${h}`);
  return { label, tx: h, status: rc.status };
}
/** Envoi sans simulation : un refus DOIT atterrir dans un bloc pour être citable. */
async function attempt(label: string, fn: string, args: any[], gas = 500_000n) {
  const data = encodeFunctionData({ abi, functionName: fn, args });
  const h = await wallet.sendTransaction({ to: C, data, gas });
  const rc = await pub.waitForTransactionReceipt({ hash: h });
  console.log(`   ${label} → ${rc.status}  tx ${h}`);
  return { label, tx: h, status: rc.status };
}

// ─── digest EIP-191, recalculé côté client exactement comme le contrat ───
function digestOf(v: { artifactHash: Hex; issuer: Address; approve: boolean; nonce: bigint; expiry: bigint }) {
  const inner = keccak256(encodeAbiParameters(
    parseAbiParameters("bytes32, address, bool, uint256, uint64, address, uint256"),
    [v.artifactHash, v.issuer, v.approve, v.nonce, v.expiry, C, BigInt(chainId)],
  ));
  return keccak256(encodePacked(["string", "bytes32"], ["\x19Ethereum Signed Message:\n32", inner]));
}
async function sign(pk: Hex, v: any) {
  const acct = privateKeyToAccount(pk);
  return acct.sign({ hash: digestOf(v) });
}

// ─── mise en place ───
console.log("\n── mise en place (sur le gate uniquement, jamais sur v1) ──");
await send("setIssuer(émetteur, true)", "setIssuer", [issuer.address, true]);
await waitVisible(async () => (await read("authorizedIssuers", [issuer.address])) === true);
const CREDIT = parseEther("0.001");
await send("credit(agent 3, 0.001)", "credit", [CHILD_ID, CREDIT]);
await waitVisible(async () => (await read("received", [CHILD_ID])) === CREDIT);
console.log("   effectiveCap(3) :", formatEther(await read("effectiveCap", [CHILD_ID])), "ETH");
console.log("   room(3)         :", formatEther(await read("room", [CHILD_ID])), "ETH");

const AMOUNT = parseEther("0.0004");
const SALT = keccak256(encodePacked(["string"], ["live-proof-1"]));
const action = { agentId: CHILD_ID, payee: PAYEE, amount: AMOUNT, salt: SALT };
const commitment: Hex = await read("commit", [action]);
console.log("   actionCommitment :", commitment);
const expiry = (await pub.getBlock()).timestamp + 86_400n;

// ═══════════ 1. execute avec verdict bon + signé + autorisé
console.log("\n── 1. verdict bon + signé + émetteur autorisé ──");
const good: any = { artifactHash: commitment, issuer: issuer.address, approve: true, nonce: 1n, expiry, signature: "0x" };
good.signature = await sign(issuerPk, good);
const r1 = await attempt("execute(action, verdict légitime)", "execute", [action, good]);
console.log("   spent(3) :", formatEther(await read("spent", [CHILD_ID])), "ETH");

// ═══════════ 2. verdict forgé, sans signature (le trou d'origine)
console.log("\n── 2. verdict forgé, sans signature ──");
const salt2 = keccak256(encodePacked(["string"], ["live-proof-2"]));
const action2 = { agentId: CHILD_ID, payee: PAYEE, amount: AMOUNT, salt: salt2 };
const commit2: Hex = await read("commit", [action2]);
const forged = { artifactHash: commit2, issuer: issuer.address, approve: true, nonce: 2n, expiry, signature: "0x" as Hex };
const r2 = await attempt("execute(action, verdict sans signature)", "execute", [action2, forged]);

// ═══════════ 3. self-report : l'agent se signe lui-même
console.log("\n── 3. self-report : signé par le propriétaire de l'agent ──");
const salt3 = keccak256(encodePacked(["string"], ["live-proof-3"]));
const action3 = { agentId: CHILD_ID, payee: PAYEE, amount: AMOUNT, salt: salt3 };
const commit3: Hex = await read("commit", [action3]);
const self: any = { artifactHash: commit3, issuer: account.address, approve: true, nonce: 3n, expiry, signature: "0x" };
self.signature = await sign(process.env.PRIVATE_KEY as Hex, self);
console.log("   signataire récupéré par le contrat :", await read("recoverIssuer", [self]));
console.log("   issuer déclaré                     :", self.issuer);
console.log("   authorizedIssuers[agent]           :", await read("authorizedIssuers", [account.address]));
const r3 = await attempt("execute(action, self-report signé)", "execute", [action3, self]);

// ═══════════ 4/5. reclamation exacte, puis sur-retour
console.log("\n── 4. reclamation exacte au vrai parent ──");
const parentOwner = await pub.readContract({
  address: V1, functionName: "ownerOf", args: [PARENT_ID],
  abi: [{ name: "ownerOf", type: "function", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "address" }] }],
}) as Address;
const roomNow: bigint = await read("room", [CHILD_ID]);
console.log("   propriétaire du parent réel (agent 2) :", parentOwner);
console.log("   reliquat R−S :", formatEther(roomNow), "ETH");
const r4 = await attempt(`reclaim(3, vrai parent, ${formatEther(roomNow)})`, "reclaim", [CHILD_ID, parentOwner, roomNow]);
console.log("   bookClosed(3) :", await read("bookClosed", [CHILD_ID]));

console.log("\n── 5. sur-retour : un wei de trop ──");
const r5 = await attempt("reclaim(3, vrai parent, reliquat + 1)", "reclaim", [CHILD_ID, parentOwner, 1n]);

out.steps = {
  setup: { credit: CREDIT.toString(), effectiveCap: (await read("effectiveCap", [CHILD_ID])).toString() },
  commitment, action: { ...action, agentId: CHILD_ID.toString(), amount: AMOUNT.toString() },
  p1_execute_ok: r1, p2_forged: r2, p3_self_report: r3, p4_reclaim_ok: r4, p5_over_return: r5,
  parentOwner,
  final: {
    received: (await read("received", [CHILD_ID])).toString(),
    spent: (await read("spent", [CHILD_ID])).toString(),
    returnedTo: (await read("returnedTo", [CHILD_ID])).toString(),
    bookClosed: await read("bookClosed", [CHILD_ID]),
  },
};

console.log("\nsolde restant :", formatEther(await pub.getBalance({ address: account.address })), "ETH");
mkdirSync(resolve(root, "build"), { recursive: true });
writeFileSync(resolve(root, "build/gateLive.json"),
  JSON.stringify(out, (_, v) => (typeof v === "bigint" ? v.toString() : v), 2));
console.log("→ build/gateLive.json");
