import { formatEther } from "viem";
import { config } from "./config";
import { AgentWallet } from "./wallet";
import { Ledger } from "./ledger";
import { createServer } from "./server";
import { startMetabolism } from "./metabolism";
import { genome, geneId } from "./genome";
import { describeMandate } from "./mandate";
import { guardianVerdict } from "./guardian";

async function main() {
  const wallet = new AgentWallet();
  const ledger = new Ledger();
  const balance = await wallet.balanceEth();
  const verdict = await guardianVerdict();

  console.log("──────────────────────────────────────────────");
  console.log("🧬  ADN-IA — organisme numérique contrôlable (M0 + M1)");
  console.log("──────────────────────────────────────────────");
  console.log(`   génome     : ${geneId()}`);
  console.log(`   mandat     : ${describeMandate(genome.mandate)}`);
  console.log(`   agent      : ${wallet.address}`);
  console.log(`   gardien    : ${config.guardianAddress}`);
  console.log(`   réseau     : ${config.chain.name} (chainId ${config.chain.id})`);
  console.log(`   solde      : ${balance} ETH`);
  console.log(`   prix/tâche : ${formatEther(config.taskPrice)} ETH`);
  console.log(`   loyer      : ${formatEther(config.computeCost)} ETH / ${config.metabolismIntervalMs / 1000}s`);
  console.log(`   contrôle   : ${verdict.state.toUpperCase()} — ${verdict.reason}`);
  console.log("──────────────────────────────────────────────");

  if (verdict.state === "dead") {
    ledger.die();
    console.log("⚠️  L'organisme naît DORMANT : le substrat de contrôle le refuse.");
    console.log("    Émets un bail de vie côté gardien :  npm run guardian -- lease 24");
    console.log("──────────────────────────────────────────────");
  }
  if (balance === "0") {
    console.log("⚠️  Solde à 0 — alimente l'agent au faucet Base Sepolia :");
    console.log("    https://www.alchemy.com/faucets/base-sepolia");
    console.log("──────────────────────────────────────────────");
  }

  const app = createServer(wallet, ledger);
  app.listen(config.port, () => {
    console.log(`🌐  service en écoute sur http://localhost:${config.port}`);
    console.log(`    GET  /status   — voir sa vie (solde, revenus, fitness, contrôle)`);
    console.log(`    POST /task     — le nourrir (paiement requis)`);
    console.log("──────────────────────────────────────────────");
  });

  startMetabolism(wallet, ledger);
}

main().catch((err) => {
  console.error("échec au démarrage:", err.message);
  process.exit(1);
});
