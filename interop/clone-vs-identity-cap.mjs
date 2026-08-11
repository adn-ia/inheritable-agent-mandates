import "dotenv/config";
import { readFileSync, writeFileSync } from "node:fs";
import { randomBytes } from "node:crypto";
import { createPublicClient, createWalletClient, http, keccak256, encodeAbiParameters,
         parseAbiParameters, encodeFunctionData, getAddress } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { baseSepolia } from "viem/chains";

/**
 * Le scenario du clone — ce qu'un nullifieur ne voit pas.
 *
 * Contexte : le fil « Unclonable Agent Execution Credentials » (ERC en idee/brouillon)
 * rend un credential a usage unique via un nullifieur en connaissance nulle. Apres
 * discussion, la garantie y est enoncee comme « at most once, WITH NO ORDERING » :
 * un clone qui a copie la memoire de l'agent gagne la course par construction, parce
 * qu'il n'attend pas la boucle de raisonnement de l'agent.
 *
 * La question que cela laisse ouverte : le clone a gagne QUOI ?
 *
 * Ce script mesure la reponse sur un gate deploye. Les deux executions sont
 * DIFFERENTES — autre salt, autre commitment, autre nonce, verdict signe a neuf.
 * Rien n'est rejoue : un registre de nullifieurs aurait vu deux consommations
 * parfaitement legitimes et accepte les deux. La seconde est refusee quand meme,
 * parce que la borne est soudee a l'IDENTITE et non au credential :
 *
 *     require(spent[agentId] + amount <= effectiveCap(agentId), "over effective cap");
 *
 * Autrement dit : N clones du meme agent partagent UN budget. Ils ne le multiplient pas.
 *
 * LIMITE, a dire soi-meme : cela borne UNE identite, pas la consommation agregee d'une
 * lignee. Un parent et son enfant, chacun sous son propre plafond, peuvent ensemble
 * depasser celui du parent (mesure et consigne dans DEPLOYMENTS.md). Pour un clone qui
 * engendre a son tour, c'est le gel en cascade qui repond, pas le plafond.
 *
 * Reproduction :  node interop/clone-vs-identity-cap.mjs
 * Requiert PRIVATE_KEY dans .env, et que ce compte soit le gardien du gate (il doit
 * pouvoir appeler setIssuer et crediter). Un tiers rejoue le scenario contre son propre
 * deploiement ; contre celui-ci, il lit les deux transactions citees dans interop/README.md.
 */

const GATE = "0x34a9ab58756b9a0579d9d156292412bbed87cbe8"; // MandateGateV3, Base Sepolia
const AGENT = 3n;
const PAYEE = getAddress("0x000000000000000000000000000000000000dead");
const abi = JSON.parse(readFileSync("build/MandateGateV3.json", "utf8")).abi;

const RPC = process.env.BASE_SEPOLIA_RPC || "https://base-sepolia-rpc.publicnode.com";
const acc = privateKeyToAccount(process.env.PRIVATE_KEY);
const pub = createPublicClient({ chain: baseSepolia, transport: http(RPC) });
const w = createWalletClient({ account: acc, chain: baseSepolia, transport: http(RPC) });
if (await pub.getChainId() !== 84532) throw new Error("REFUS : chainId != 84532 (Base Sepolia)");

const rd = (fn, a) => pub.readContract({ address: GATE, abi, functionName: fn, args: a });
const wait = async (f, n = 40) => { for (let i = 0; i < n; i++) { if (await f()) return true; await new Promise(r => setTimeout(r, 2000)); } return false; };
const txs = [];

console.log("  gate  :", GATE, "· agent", AGENT);
console.log("  compte:", acc.address);

if (!(await rd("authorizedIssuers", [acc.address]))) {
  const h = await w.writeContract({ address: GATE, abi, functionName: "setIssuer", args: [acc.address, true] });
  await pub.waitForTransactionReceipt({ hash: h });
  await wait(async () => rd("authorizedIssuers", [acc.address]));
  console.log("  setIssuer :", h);
}

const cap = await rd("effectiveCap", [AGENT]);
let spent = await rd("spent", [AGENT]);
const room = await rd("room", [AGENT]);
console.log("\n── etat de depart ──");
console.log("  effectiveCap :", cap, "· spent :", spent, "· room :", room);

// Le plafond doit avoir de la marge, sinon la premiere execution ne prouve rien.
const budget = (cap - spent) < room ? (cap - spent) : room;
if (budget === 0n) {
  console.log("\n  >>> Le plafond de cet agent est deja consomme (spent == cap).");
  console.log("      Le scenario a deja ete joue — voir les transactions dans interop/README.md.");
  console.log("      Pour le rejouer : mint/spawn un agent neuf, credit(agentId, montant), puis relancer.");
  process.exit(0);
}

/** Fabrique un verdict ECDSA reellement signe, lie a CETTE action. */
async function verdictFor(amount, nonce) {
  const action = { agentId: AGENT, payee: PAYEE, amount, salt: "0x" + randomBytes(32).toString("hex") };
  const c = keccak256(encodeAbiParameters(parseAbiParameters("uint256, address, uint256, bytes32"),
    [action.agentId, action.payee, action.amount, action.salt]));
  if (c !== await rd("commit", [action])) throw new Error("commit local != commit du gate");
  const expiry = BigInt((await pub.getBlock()).timestamp) + 3600n;
  const v = { artifactHash: c, issuer: acc.address, approve: true, nonce, expiry, signature: "0x" };
  v.signature = await acc.sign({ hash: await rd("verdictDigest", [v]) }); // le digest porte deja EIP-191
  return { action, v, c };
}

async function tryExec(label, amount, nonce) {
  const { action, v, c } = await verdictFor(amount, nonce);
  const data = encodeFunctionData({ abi, functionName: "execute", args: [action, v] });
  let reason = null;
  try { await pub.call({ account: acc.address, to: GATE, data }); }
  catch (e) { const m = String(e.message).match(/reason:\s*\n?(.+)/);
              reason = m ? m[1].trim().replace(/\.$/, "") : String(e.shortMessage || "").slice(0, 70); }
  const h = await w.sendTransaction({ to: GATE, data, gas: 400000n });
  const rc = await pub.waitForTransactionReceipt({ hash: h });
  txs.push({ label, amount: amount.toString(), nonce: nonce.toString(), commitment: c, hash: h, status: rc.status, reason });
  console.log(`\n  ${label}`);
  console.log(`    montant    : ${amount} wei · nonce ${nonce}`);
  console.log(`    commitment : ${c}`);
  console.log(`    tx ${h}  ->  ${rc.status}${reason ? "  · " + reason : ""}`);
}

// ── 1) l'agent legitime consomme son plafond ─────────────────────────────────
await tryExec("1) AGENT LEGITIME — verdict propre, nonce neuf", budget, 1001n);
await wait(async () => (await rd("spent", [AGENT])) > spent);
spent = await rd("spent", [AGENT]);
console.log("    spent[agent] :", spent, "/ plafond", cap);

// ── 2) le clone : tout est frais de son cote ─────────────────────────────────
console.log("\n  Le clone presente une action DIFFERENTE : autre salt, autre commitment,");
console.log("  autre nonce, verdict signe a neuf. Aucun nullifieur ne verrait un rejeu.");
await tryExec("2) LE CLONE — rien de rejoue", 1n, 1002n);

const final = await rd("spent", [AGENT]);
console.log("\n══ CE QUE LE CLONE A GAGNE ══════════════════════════════════");
console.log("  plafond de l'identite :", cap);
console.log("  total depense         :", final);
console.log("  extrait par le clone  :", final - spent, "wei");

writeFileSync("build/clone-vs-identity-cap.json", JSON.stringify({
  gate: GATE, agent: AGENT.toString(), cap: cap.toString(), spentFinal: final.toString(), txs,
}, (_, v) => typeof v === "bigint" ? v.toString() : v, 2));
