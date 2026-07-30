import { AgentWallet } from "../src/wallet";
import { config } from "../src/config";

/** Affiche l'adresse et le solde de l'agent, + le lien faucet si vide. */
const wallet = new AgentWallet();
const balance = await wallet.balanceEth();

console.log("agent :", wallet.address);
console.log("réseau:", config.chain.name);
console.log("solde :", balance, "ETH");

if (balance === "0") {
  console.log("\n⚠️  Solde à 0 — alimente au faucet Base Sepolia :");
  console.log("   https://www.alchemy.com/faucets/base-sepolia");
}
