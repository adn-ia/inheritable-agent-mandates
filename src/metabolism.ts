import { formatEther } from "viem";
import { config } from "./config";
import type { AgentWallet } from "./wallet";
import type { Ledger } from "./ledger";
import { guardianVerdict } from "./guardian";
import { genome } from "./genome";

/**
 * M1 — LE MÉTABOLISME (le cœur qui bat), sous contrôle.
 *
 * À chaque battement, AVANT toute dépense, on consulte le substrat de contrôle :
 *   - arrêt / bail expiré  → mort.
 *   - embargo              → gel : aucune dépense ce battement.
 * Puis, si l'organisme est en vie et non gelé, il paie lui-même son loyer de calcul,
 * dans la double limite du plafond de dépense et de son solde. S'il ne peut plus payer,
 * il meurt — de ses propres dépenses.
 */
export function startMetabolism(wallet: AgentWallet, ledger: Ledger): NodeJS.Timeout {
  const beat = async () => {
    if (!ledger.alive) return;

    // Le substrat décide d'abord.
    const verdict = await guardianVerdict();
    if (verdict.state === "dead") {
      ledger.die();
      console.log(`💀 MORT — ${verdict.reason}. Le génome, lui, persiste.`);
      return;
    }
    if (verdict.state === "embargoed") {
      console.log(`🧊 GEL — ${verdict.reason} (aucune dépense ce battement).`);
      return;
    }

    try {
      // Plafond de dépense à vie — inscrit dans le mandat (donc hérité par les enfants).
      const maxSpend = BigInt(genome.mandate.maxSpendWei);
      if (ledger.totalSpendWei() + config.computeCost > maxSpend) {
        console.log(
          `🛑 plafond de dépense atteint (${formatEther(maxSpend)} ETH) — mise en pause.`
        );
        return;
      }

      const balance = await wallet.balance();
      if (balance < config.computeCost + config.deathThreshold) {
        ledger.die();
        console.log(
          `💀 MORT — solde ${formatEther(balance)} ETH sous le minimum vital. L'organisme s'endort.`
        );
        return;
      }

      const hash = await wallet.pay(config.computeProvider, config.computeCost);
      ledger.recordSpend(config.computeCost);

      const snap = ledger.snapshot();
      console.log(
        `❤️  battement — loyer ${formatEther(config.computeCost)} ETH payé (${hash.slice(0, 10)}…) | solde ~${await wallet.balanceEth()} ETH | net ${snap.netEth} | fitness ${snap.fitnessEthPerTask}/tâche`
      );
    } catch (err) {
      ledger.die();
      console.log(
        `💀 MORT — incapable de payer son calcul (${String((err as Error).message).slice(0, 100)}).`
      );
    }
  };

  setTimeout(beat, 2000);
  return setInterval(beat, config.metabolismIntervalMs);
}
