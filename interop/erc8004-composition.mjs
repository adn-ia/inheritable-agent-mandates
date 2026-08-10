import "dotenv/config";
import { createPublicClient, createWalletClient, http, formatEther, parseEther, decodeEventLog } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { baseSepolia } from "viem/chains";

/**
 * ERC-8004 x ERC-8370 — que survit-il a la vente d'une identite d'agent ?
 *
 * Ce script ne demontre rien : il MESURE, sur les registres ERC-8004 reellement
 * deployes sur Base Sepolia. Aucun fork, aucun mock, aucun contrat a nous.
 *
 * Quatre questions, dans l'ordre :
 *   1. une clause de controle attachee via leur extension metadata survit-elle au
 *      transfert du NFT d'identite ?
 *   2. le nouveau proprietaire peut-il la reecrire ?
 *   3. la cle reservee `agentWallet` est-elle bien effacee, comme leur spec l'annonce ?
 *   4. la reputation accumulee suit-elle le jeton chez l'acheteur ?
 *
 * Trois roles distincts, car leur registre refuse l'auto-notation ("Self-feedback
 * not allowed") : un vendeur qui possede l'agent, un client tiers qui le note, un
 * acheteur qui l'acquiert. Les deux derniers sont des comptes jetables de testnet
 * derives de graines PUBLIQUES et finances par le script. Ne jamais les reutiliser.
 *
 * Reproduction :  node interop/erc8004-composition.mjs
 * Requiert PRIVATE_KEY dans .env (Base Sepolia, ~0.001 ETH de test suffit).
 */

const ID = "0x8004A818BFB912233c491871b3d84c89A494BD9e";  // IdentityRegistry
const REP = "0x8004B663056A597Dffe9eCcC1965A193B7388713"; // ReputationRegistry
// comptes jetables, graines PUBLIQUES, testnet uniquement — finances par le script
const BUYER_SEED = "0x" + "8004".repeat(16);   // celui qui achete l'identite
const CLIENT_SEED = "0x" + "c11e".repeat(16);  // le tiers qui note l'agent

const idAbi = [
  { name: "register", type: "function", stateMutability: "nonpayable", inputs: [], outputs: [{ type: "uint256" }] },
  { name: "ownerOf", type: "function", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "address" }] },
  { name: "getMetadata", type: "function", stateMutability: "view",
    inputs: [{ type: "uint256" }, { type: "string" }], outputs: [{ type: "bytes" }] },
  { name: "setMetadata", type: "function", stateMutability: "nonpayable",
    inputs: [{ type: "uint256" }, { type: "string" }, { type: "bytes" }], outputs: [] },
  { name: "transferFrom", type: "function", stateMutability: "nonpayable",
    inputs: [{ type: "address" }, { type: "address" }, { type: "uint256" }], outputs: [] },
  { type: "event", name: "Registered", inputs: [
    { indexed: true, name: "agentId", type: "uint256" },
    { indexed: false, name: "agentURI", type: "string" },
    { indexed: true, name: "owner", type: "address" }] },
];

const repAbi = [
  { name: "giveFeedback", type: "function", stateMutability: "nonpayable", inputs: [
    { name: "agentId", type: "uint256" }, { name: "value", type: "int128" }, { name: "valueDecimals", type: "uint8" },
    { name: "tag1", type: "string" }, { name: "tag2", type: "string" }, { name: "endpoint", type: "string" },
    { name: "feedbackURI", type: "string" }, { name: "feedbackHash", type: "bytes32" }], outputs: [] },
  { name: "getSummary", type: "function", stateMutability: "view",
    inputs: [{ name: "agentId", type: "uint256" }, { name: "clients", type: "address[]" },
             { name: "tag1", type: "string" }, { name: "tag2", type: "string" }],
    outputs: [{ type: "uint64" }, { type: "int128" }, { type: "uint8" }] },
  { name: "getClients", type: "function", stateMutability: "view", inputs: [{ type: "uint256" }], outputs: [{ type: "address[]" }] },
  { name: "getLastIndex", type: "function", stateMutability: "view",
    inputs: [{ type: "uint256" }, { type: "address" }], outputs: [{ type: "uint64" }] },
];

const RPC = process.env.BASE_SEPOLIA_RPC || "https://base-sepolia-rpc.publicnode.com";
const seller = privateKeyToAccount(process.env.PRIVATE_KEY);
const buyer = privateKeyToAccount(BUYER_SEED);
const client = privateKeyToAccount(CLIENT_SEED);
const pub = createPublicClient({ chain: baseSepolia, transport: http(RPC) });
const wSeller = createWalletClient({ account: seller, chain: baseSepolia, transport: http(RPC) });
const wBuyer = createWalletClient({ account: buyer, chain: baseSepolia, transport: http(RPC) });
const wClient = createWalletClient({ account: client, chain: baseSepolia, transport: http(RPC) });

// garde-fou : testnet uniquement, la graine acheteur est publique
const chainId = await pub.getChainId();
if (chainId !== 84532) throw new Error(`REFUS : chainId ${chainId}, attendu 84532 (Base Sepolia)`);

const rdId = (fn, args) => pub.readContract({ address: ID, abi: idAbi, functionName: fn, args });
const rdRep = (fn, args) => pub.readContract({ address: REP, abi: repAbi, functionName: fn, args });
const utf8 = (b) => (!b || b === "0x") ? "(vide)" : Buffer.from(b.slice(2), "hex").toString();
const hex = (o) => "0x" + Buffer.from(JSON.stringify(o), "utf8").toString("hex");
const wait = async (f, n = 40) => { for (let i = 0; i < n; i++) { try { if (await f()) return true; } catch {} await new Promise(r => setTimeout(r, 2000)); } return false; };
const txs = [];
async function send(w, address, abi, functionName, args, label) {
  const h = await w.writeContract({ address, abi, functionName, args });
  const rc = await pub.waitForTransactionReceipt({ hash: h });
  txs.push({ label, hash: h, block: rc.blockNumber, status: rc.status });
  console.log(`    ${label}\n      tx ${h}  bloc ${rc.blockNumber}  -> ${rc.status}`);
  return rc;
}

console.log("  chainId    :", chainId, "(Base Sepolia)");
console.log("  vendeur    :", seller.address, "·", formatEther(await pub.getBalance({ address: seller.address })), "ETH");
console.log("  acheteur   :", buyer.address, "(graine publique, jetable)");
console.log("  client     :", client.address, "(graine publique, jetable)");

// acheteur et client signent eux-memes : ils doivent pouvoir payer leur gaz
for (const [nom, adr] of [["acheteur", buyer.address], ["client", client.address]]) {
  let b = await pub.getBalance({ address: adr });
  if (b < parseEther("0.00005")) {
    const h = await wSeller.sendTransaction({ to: adr, value: parseEther("0.0002") });
    await pub.waitForTransactionReceipt({ hash: h });
    await wait(async () => (await pub.getBalance({ address: adr })) > b);
    b = await pub.getBalance({ address: adr });
  }
  console.log(`  solde ${nom.padEnd(9)}:`, formatEther(b), "ETH");
}

// ── 1) on s'enregistre sur LEUR registre ─────────────────────────────────────
console.log("\n── 1) register() : une identite d'agent, chez eux ──");
const rc1 = await send(wSeller, ID, idAbi, "register", [], "register()");
let agentId = 0n;
for (const log of rc1.logs) {
  try { const d = decodeEventLog({ abi: idAbi, data: log.data, topics: log.topics });
        if (d.eventName === "Registered") agentId = d.args.agentId; } catch {}
}
if (!agentId) throw new Error("agentId introuvable dans les logs");
console.log("      agentId :", agentId);
await wait(async () => (await rdId("ownerOf", [agentId])).toLowerCase() === seller.address.toLowerCase());

// ── 2) on y attache une clause de controle, via LEUR extension metadata ──────
console.log("\n── 2) on attache une clause de controle (le mandat ERC-8370) ──");
const clause = { maxSpendWei: "1000", telomere: 3, frozen: false };
await send(wSeller, ID, idAbi, "setMetadata", [agentId, "mandate", hex(clause)], "setMetadata(.., 'mandate', ..)");
await wait(async () => (await rdId("getMetadata", [agentId, "mandate"])) !== "0x");

// ── 3) un tiers note l'agent ─────────────────────────────────────────────────
console.log("\n── 3) un client TIERS note l'agent 95/100 ──");
console.log("    (le proprietaire ne peut pas : leur registre refuse l'auto-notation)");
await send(wClient, REP, repAbi, "giveFeedback",
  [agentId, 95n, 0, "quality", "", "", "", "0x" + "00".repeat(32)], "giveFeedback(95) PAR LE CLIENT");
await wait(async () => (await rdRep("getLastIndex", [agentId, client.address])) > 0n);

const before = {
  owner: await rdId("ownerOf", [agentId]),
  wallet: await rdId("getMetadata", [agentId, "agentWallet"]),
  mandate: await rdId("getMetadata", [agentId, "mandate"]),
  clients: await rdRep("getClients", [agentId]),
};
before.summary = await rdRep("getSummary", [agentId, before.clients, "", ""]);
console.log("\n  ETAT AVANT LA VENTE");
console.log("    ownerOf     :", before.owner);
console.log("    agentWallet :", before.wallet === "0x" ? "(vide)" : before.wallet);
console.log("    mandate     :", utf8(before.mandate));
console.log("    reputation  : count", before.summary[0], "· somme", before.summary[1]);

// ── 4) LA VENTE ──────────────────────────────────────────────────────────────
console.log("\n── 4) l'identite est vendue : transferFrom ──");
await send(wSeller, ID, idAbi, "transferFrom", [seller.address, buyer.address, agentId], "transferFrom(vendeur -> acheteur)");
await wait(async () => (await rdId("ownerOf", [agentId])).toLowerCase() === buyer.address.toLowerCase());

const after = {
  owner: await rdId("ownerOf", [agentId]),
  wallet: await rdId("getMetadata", [agentId, "agentWallet"]),
  mandate: await rdId("getMetadata", [agentId, "mandate"]),
  clients: await rdRep("getClients", [agentId]),
};
after.summary = await rdRep("getSummary", [agentId, after.clients, "", ""]);
console.log("\n  ETAT APRES LA VENTE");
console.log("    ownerOf     :", after.owner);
console.log("    agentWallet :", after.wallet === "0x" ? "(vide)" : after.wallet);
console.log("    mandate     :", utf8(after.mandate));
console.log("    reputation  : count", after.summary[0], "· somme", after.summary[1]);

// ── 5) l'ACHETEUR reecrit la clause qu'il vient d'acquerir ───────────────────
console.log("\n── 5) l'acheteur reecrit la clause, avec SA propre signature ──");
const rewritten = { maxSpendWei: "999999999", telomere: 255, frozen: false };
let rewriteOk = true, rewriteErr = null;
try {
  await send(wBuyer, ID, idAbi, "setMetadata", [agentId, "mandate", hex(rewritten)], "setMetadata(.., 'mandate', ..) PAR L'ACHETEUR");
} catch (e) { rewriteOk = false; rewriteErr = String(e.shortMessage || e.message).slice(0, 120); }
if (rewriteOk) await wait(async () => utf8(await rdId("getMetadata", [agentId, "mandate"])).includes("999999999"));
const finalMandate = await rdId("getMetadata", [agentId, "mandate"]);

// ── verdict ──────────────────────────────────────────────────────────────────
const eq = (a, b) => JSON.stringify(a, (_, v) => typeof v === "bigint" ? v.toString() : v)
                  === JSON.stringify(b, (_, v) => typeof v === "bigint" ? v.toString() : v);
console.log("\n══ CE QUE LA VENTE A EMPORTE ══════════════════════════════════════");
console.log("  proprietaire      :", before.owner, "->", after.owner);
console.log("  agentWallet       :", before.wallet === after.wallet ? "inchange" : "EFFACE",
            "(", before.wallet === "0x" ? "vide" : "defini", "->", after.wallet === "0x" ? "vide" : "defini", ")");
console.log("  clause de controle:", before.mandate === after.mandate ? "SURVIT INTACTE" : "modifiee");
console.log("  reputation        :", eq(before.summary, after.summary) ? "SURVIT INTACTE" : "modifiee",
            "( count", before.summary[0], "somme", before.summary[1], "->",
            "count", after.summary[0], "somme", after.summary[1], ")");
console.log("  reecriture par l'acheteur :", rewriteOk ? "ACCEPTEE, aucun refus" : "REFUSEE — " + rewriteErr);
if (rewriteOk) console.log("    clause finale   :", utf8(finalMandate));
console.log("\n  agent mesure :", agentId, "· transactions :");
for (const t of txs) console.log(`    ${t.label.padEnd(46)} ${t.hash}`);
