import "dotenv/config";
import { readFileSync, writeFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import {
  createPublicClient,
  createWalletClient,
  http,
  formatEther,
  parseEther,
  type Hex,
  type Address,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { baseSepolia } from "viem/chains";

/**
 * Déploie les deux démonstrateurs sur Base Sepolia. TESTNET UNIQUEMENT.
 * La clé n'est ni lue ni imprimée : seule l'adresse apparaît.
 */
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const account = privateKeyToAccount(process.env.PRIVATE_KEY as Hex);
const rpcUrl = process.env.RPC_URL ?? "https://sepolia.base.org";

const pub = createPublicClient({ chain: baseSepolia, transport: http(rpcUrl) });
const wallet = createWalletClient({ account, chain: baseSepolia, transport: http(rpcUrl) });

const chainId = await pub.getChainId();
if (chainId !== baseSepolia.id) throw new Error(`Mauvaise chaîne: ${chainId}`);

console.log("réseau    :", baseSepolia.name, `(chainId ${chainId})`);
console.log("déployeur :", account.address);
console.log("solde     :", formatEther(await pub.getBalance({ address: account.address })), "ETH\n");

// Gardiens : seul le premier est contrôlé. Les deux autres sont des repères, sans
// clé connue — un seuil à 2 approbations n'est donc PAS exécutable sur ce déploiement.

const out: any = { network: "base-sepolia", chainId, deployer: account.address, contracts: {} };

async function deploy(name: string, args: any[]) {
  const artifact = JSON.parse(readFileSync(resolve(root, `build/${name}.json`), "utf8"));
  const hash = await wallet.deployContract({
    abi: artifact.abi,
    bytecode: artifact.bytecode as Hex,
    args,
  });
  console.log(`${name}`);
  console.log(`   tx : ${hash}`);
  const r = await pub.waitForTransactionReceipt({ hash });
  if (r.status !== "success" || !r.contractAddress) throw new Error(`${name} : déploiement échoué`);

  // attendre que le code soit visible du noeud avant d'enchaîner
  for (let i = 0; i < 30; i++) {
    const code = await pub.getCode({ address: r.contractAddress });
    if (code && code !== "0x") break;
    await new Promise((res) => setTimeout(res, 2000));
  }
  const code = await pub.getCode({ address: r.contractAddress });

  console.log(`   adresse : ${r.contractAddress}`);
  console.log(`   bloc    : ${r.blockNumber}   gaz : ${r.gasUsed}`);
  console.log(`   code on-chain : ${code ? (code.length - 2) / 2 : 0} octets`);
  console.log(`   explorateur : https://sepolia.basescan.org/address/${r.contractAddress}\n`);

  out.contracts[name] = {
    address: r.contractAddress,
    deployTx: hash,
    blockNumber: r.blockNumber.toString(),
    gasUsed: r.gasUsed.toString(),
    constructorArgs: args.map((a) => (typeof a === "bigint" ? a.toString() : a)),
  };
  return r.contractAddress;
}

// StructuredBudget a été déployé lors d'un premier passage (nonce 46) ; on le
// consigne au lieu de le redéployer.
const ALREADY = process.env.SB_ADDRESS as Address | undefined;
if (ALREADY) {
  const code = await pub.getCode({ address: ALREADY });
  console.log("StructuredBudget (déjà déployé)");
  console.log(`   adresse : ${ALREADY}`);
  console.log(`   code on-chain : ${code ? (code.length - 2) / 2 : 0} octets`);
  console.log(`   explorateur : https://sepolia.basescan.org/address/${ALREADY}\n`);
  out.contracts["StructuredBudget"] = { address: ALREADY, note: "déployé au nonce 46" };
} else {
  await deploy("StructuredBudget", []);
}

const guardians = [account.address, "0x000000000000000000000000000000000000dEaD", "0x000000000000000000000000000000000000bEEF"];
await deploy("MandateWithException", [
  guardians,
  parseEther("0.5"), // maxExceptionAmount
  parseEther("0.2"), // bigThreshold
  2n, // bigApprovals
]);

console.log("solde restant :", formatEther(await pub.getBalance({ address: account.address })), "ETH");
writeFileSync(resolve(root, "build/deployment-demos.json"), JSON.stringify(out, null, 2));
console.log("→ build/deployment-demos.json");
