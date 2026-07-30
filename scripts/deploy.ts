import "dotenv/config";
import { readFileSync, writeFileSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { createPublicClient, createWalletClient, http, formatEther, type Hex } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { baseSepolia } from "viem/chains";

/**
 * Déploie InheritableAgentMandate sur Base Sepolia. TESTNET UNIQUEMENT.
 * Le déployeur est le gardien du contrat. L'adresse déployée est écrite dans
 * build/deployment.json pour que la démo la reprenne.
 */
const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const artifact = JSON.parse(
  readFileSync(resolve(root, "build/InheritableAgentMandate.json"), "utf8")
);

const account = privateKeyToAccount(process.env.PRIVATE_KEY as Hex);
const rpcUrl = process.env.RPC_URL ?? "https://sepolia.base.org";

const pub = createPublicClient({ chain: baseSepolia, transport: http(rpcUrl) });
const wallet = createWalletClient({ account, chain: baseSepolia, transport: http(rpcUrl) });

const chainId = await pub.getChainId();
if (chainId !== baseSepolia.id) {
  throw new Error(`Mauvaise chaîne: ${chainId}. Attendu Base Sepolia (${baseSepolia.id}).`);
}

const balance = await pub.getBalance({ address: account.address });
console.log("réseau    :", baseSepolia.name, `(chainId ${chainId})`);
console.log("déployeur :", account.address);
console.log("solde     :", formatEther(balance), "ETH");
if (balance === 0n) throw new Error("Solde nul — finance l'adresse à un faucet Base Sepolia.");

// gardien = déployeur
const hash = await wallet.deployContract({
  abi: artifact.abi,
  bytecode: artifact.bytecode as Hex,
  args: [account.address],
});
console.log("\ntx déploiement :", hash);

const receipt = await pub.waitForTransactionReceipt({ hash });
if (receipt.status !== "success" || !receipt.contractAddress) {
  throw new Error("Déploiement échoué: " + receipt.status);
}

const address = receipt.contractAddress;
console.log("✅ contrat déployé :", address);
console.log("   bloc            :", receipt.blockNumber);
console.log("   gaz             :", receipt.gasUsed);
console.log("   explorateur     : https://sepolia.basescan.org/address/" + address);

writeFileSync(
  resolve(root, "build/deployment.json"),
  JSON.stringify(
    {
      network: "base-sepolia",
      chainId,
      address,
      guardian: account.address,
      deployTx: hash,
      blockNumber: receipt.blockNumber.toString(),
    },
    null,
    2
  )
);
console.log("   → build/deployment.json");
