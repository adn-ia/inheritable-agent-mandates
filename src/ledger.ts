import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";
import { formatEther } from "viem";

/**
 * Le REGISTRE comptable + le juge de survie (organe "Sélection").
 *
 * Le solde réel vit on-chain ; ce registre trace l'histoire (revenus, dépenses,
 * tâches, transactions déjà encaissées) et calcule la FITNESS :
 *   profit_par_tâche = (revenus - dépenses) / tâches_servies
 * Persisté sur disque : l'histoire survit à un redémarrage.
 */
const LEDGER_PATH = "data/ledger.json";

interface LedgerState {
  bornAt: number;
  alive: boolean;
  revenueWei: string;
  spendWei: string;
  tasksServed: number;
  usedTxHashes: string[];
}

export class Ledger {
  private s: LedgerState;
  private used: Set<string>;

  constructor() {
    if (existsSync(LEDGER_PATH)) {
      this.s = JSON.parse(readFileSync(LEDGER_PATH, "utf8")) as LedgerState;
    } else {
      this.s = {
        bornAt: Date.now(),
        alive: true,
        revenueWei: "0",
        spendWei: "0",
        tasksServed: 0,
        usedTxHashes: [],
      };
    }
    this.used = new Set(this.s.usedTxHashes);
  }

  private persist() {
    this.s.usedTxHashes = [...this.used];
    mkdirSync(dirname(LEDGER_PATH), { recursive: true });
    writeFileSync(LEDGER_PATH, JSON.stringify(this.s, null, 2));
  }

  get alive() {
    return this.s.alive;
  }

  isPaymentUsed(txHash: string) {
    return this.used.has(txHash.toLowerCase());
  }

  recordIncome(txHash: string, amount: bigint) {
    this.used.add(txHash.toLowerCase());
    this.s.revenueWei = (BigInt(this.s.revenueWei) + amount).toString();
    this.s.tasksServed += 1;
    this.persist();
  }

  recordSpend(amount: bigint) {
    this.s.spendWei = (BigInt(this.s.spendWei) + amount).toString();
    this.persist();
  }

  die() {
    this.s.alive = false;
    this.persist();
  }

  totalSpendWei(): bigint {
    return BigInt(this.s.spendWei);
  }

  fitnessWei(): bigint {
    if (this.s.tasksServed === 0) return 0n;
    const net = BigInt(this.s.revenueWei) - BigInt(this.s.spendWei);
    return net / BigInt(this.s.tasksServed);
  }

  snapshot() {
    const revenue = BigInt(this.s.revenueWei);
    const spend = BigInt(this.s.spendWei);
    return {
      alive: this.s.alive,
      ageSeconds: Math.floor((Date.now() - this.s.bornAt) / 1000),
      tasksServed: this.s.tasksServed,
      revenueEth: formatEther(revenue),
      spendEth: formatEther(spend),
      netEth: formatEther(revenue - spend),
      fitnessEthPerTask: formatEther(this.fitnessWei()),
    };
  }
}
