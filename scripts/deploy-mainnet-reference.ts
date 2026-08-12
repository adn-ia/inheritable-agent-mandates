import "dotenv/config";
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import {
  createPublicClient, createWalletClient, http, formatEther,
  encodeDeployData, type Hex, type Address,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { networks } from "../src/config";

/**
 * Publie le contrat de RÉFÉRENCE sur Base mainnet (chainId 8453).
 *
 * Ce contrat est un registre d'identité et de mandats : il ne reçoit, ne détient et ne
 * transfère AUCUN fonds. Non audité, publié à titre de référence pour l'ERC-8370.
 *
 * Sécurité : par défaut ce script ne fait QUE le plan. Il faut `DEPLOY=1` dans
 * l'environnement pour qu'il signe quoi que ce soit — une exécution distraite ne peut pas
 * déclencher un déploiement mainnet.
 *
 *   npx tsx scripts/deploy-mainnet-reference.ts            # plan seul, rien signé
 *   DEPLOY=1 npx tsx scripts/deploy-mainnet-reference.ts   # déploie
 */
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const CONTRACT = "InheritableAgentMandateV2";
const art = JSON.parse(readFileSync(resolve(root, `build/${CONTRACT}.json`), "utf8"));

const key = process.env.MAINNET_DEPLOYER_KEY as Hex | undefined;
if (!key) throw new Error("MAINNET_DEPLOYER_KEY absente de .env — lance scripts/mainnet-key-new.ts");
const account = privateKeyToAccount(key);

const { chain, rpcUrl } = networks.base;
const pub = createPublicClient({ chain, transport: http(rpcUrl) });

const chainId = await pub.getChainId();
if (chainId !== 8453) throw new Error(`Mauvaise chaîne : ${chainId} (attendu 8453)`);

/**
 * Gardien = un Safe (SafeL2 1.4.1) sur Base mainnet, propriétaire unique, seuil 1.
 * Déployé en `0x817536a7…ef630b`. Le choix d'un Safe plutôt qu'une EOA est structurel :
 * `guardian` est `immutable`, il ne se change plus après ce déploiement — mais les
 * signataires et le seuil du Safe, eux, restent modifiables. C'est la seule façon de
 * garder ouverte la possibilité d'un vrai multisig sans redéployer le contrat.
 */
const GUARDIAN = "0xAf15E8b845CA57785a39D8B89aCa72351FFba385" as Address;

const data = encodeDeployData({ abi: art.abi, bytecode: art.bytecode as Hex, args: [GUARDIAN] });
const balance = await pub.getBalance({ address: account.address });
const gas = await pub.estimateGas({ account: account.address, data });
const fees = await pub.estimateFeesPerGas();
const maxFee = fees.maxFeePerGas ?? 0n;
const cost = gas * maxFee;

console.log("── PLAN ─────────────────────────────────────────────");
console.log("  contrat        :", CONTRACT, `(${(art.bytecode.length - 2) / 2} octets de création)`);
console.log("  réseau         :", chain.name, `(chainId ${chainId})`);
console.log("  rpc            :", rpcUrl);
console.log("  déployeur      :", account.address);
console.log("  gardien        :", GUARDIAN, "(Safe SafeL2 1.4.1 — 1 propriétaire, seuil 1)");
console.log("  solde          :", formatEther(balance), "ETH");
console.log("  gaz estimé     :", gas.toString(), "unités");
console.log("  maxFeePerGas   :", (Number(maxFee) / 1e9).toFixed(4), "gwei");
console.log("  coût maximal   :", formatEther(cost), "ETH");
console.log("  reste après    :", formatEther(balance - cost), "ETH");
console.log("  fonds envoyés au contrat : 0 (aucun, par construction)");
console.log("─────────────────────────────────────────────────────");

if (process.env.DEPLOY !== "1") {
  console.log("\nPLAN SEUL — rien n'a été signé.");
  console.log("Pour déployer : DEPLOY=1 npx tsx scripts/deploy-mainnet-reference.ts");
  process.exit(0);
}

if (balance < cost) throw new Error("Solde insuffisant pour couvrir le gaz.");

const wallet = createWalletClient({ account, chain, transport: http(rpcUrl) });
const hash = await wallet.deployContract({ abi: art.abi, bytecode: art.bytecode as Hex, args: [GUARDIAN] });
console.log("\ntx déploiement :", hash);
const r = await pub.waitForTransactionReceipt({ hash });
if (r.status !== "success" || !r.contractAddress) throw new Error("déploiement échoué");
console.log("✅ adresse :", r.contractAddress, "· bloc", r.blockNumber, "· gaz", r.gasUsed);

for (let i = 0; i < 40; i++) {
  const code = await pub.getCode({ address: r.contractAddress });
  if (code && code !== "0x") break;
  await new Promise((res) => setTimeout(res, 2000));
}
const code = await pub.getCode({ address: r.contractAddress });

mkdirSync(resolve(root, "build"), { recursive: true });
writeFileSync(resolve(root, "build/mainnetReference.json"), JSON.stringify({
  contract: CONTRACT, network: chain.name, chainId, address: r.contractAddress,
  deployTx: hash, blockNumber: r.blockNumber.toString(), gasUsed: r.gasUsed.toString(),
  guardian: GUARDIAN, deployer: account.address, codeSize: ((code?.length ?? 2) - 2) / 2,
}, null, 2));
console.log("→ build/mainnetReference.json");
