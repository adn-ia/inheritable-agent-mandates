import {
  createPublicClient,
  createWalletClient,
  http,
  formatEther,
  type Hex,
  type Address,
} from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { config } from "./config";
import { genome } from "./genome";

/**
 * Le CORPS ÉCONOMIQUE de l'organisme (organe "Métabolisme").
 *
 * Version M0/M1 : compte simple (EOA) piloté par viem — tourne sans bundler ni
 * paymaster. La montée en "smart account" (ERC-4337) se branche derrière cette
 * même interface.
 *
 * COUPE-CIRCUIT (cran contrôlable) : `pay()` refuse toute adresse hors de la liste
 * blanche (`config.allowedPayees`). Même si le code de l'agent tentait de payer une
 * infrastructure d'évasion, la couche wallet le bloque. C'est la forme économique du
 * contrôle : on ne l'empêche pas de dépenser, on borne VERS QUI.
 */
export interface IncomingPayment {
  ok: boolean;
  reason?: string;
  from?: Address;
  value?: bigint;
}

export class AgentWallet {
  readonly address: Address;
  private account = privateKeyToAccount(config.privateKey);
  private publicClient = createPublicClient({
    chain: config.chain,
    transport: http(config.rpcUrl),
  });
  private walletClient = createWalletClient({
    account: this.account,
    chain: config.chain,
    transport: http(config.rpcUrl),
  });
  // Allowlist = les payées du MANDAT (héritable) + le fournisseur de calcul (infra).
  private allowed = new Set([
    config.computeProvider.toLowerCase(),
    ...genome.mandate.allowedPayees.map((a) => a.toLowerCase()),
  ]);

  constructor() {
    this.address = this.account.address;
  }

  async balance(): Promise<bigint> {
    return this.publicClient.getBalance({ address: this.address });
  }

  async balanceEth(): Promise<string> {
    return formatEther(await this.balance());
  }

  /** Dépense : envoie `amount` wei à `to` — SEULEMENT si `to` est sur la liste blanche. */
  async pay(to: Address, amount: bigint): Promise<Hex> {
    if (!this.allowed.has(to.toLowerCase())) {
      throw new Error(`coupe-circuit: paiement vers ${to} non autorisé (hors liste blanche)`);
    }
    const hash = await this.walletClient.sendTransaction({ to, value: amount });
    await this.publicClient.waitForTransactionReceipt({ hash });
    return hash;
  }

  /**
   * Vérifie qu'une transaction est un paiement valide VERS l'agent, d'au moins `minValue`.
   * Cœur du "pay-per-call" : la tâche n'est servie qu'après constat du paiement on-chain.
   */
  async verifyIncomingPayment(
    txHash: Hex,
    minValue: bigint
  ): Promise<IncomingPayment> {
    let tx;
    try {
      tx = await this.publicClient.getTransaction({ hash: txHash });
    } catch {
      return { ok: false, reason: "transaction introuvable (pas encore minée ?)" };
    }
    const receipt = await this.publicClient
      .getTransactionReceipt({ hash: txHash })
      .catch(() => null);
    if (!receipt || receipt.status !== "success") {
      return { ok: false, reason: "transaction non confirmée / échouée" };
    }
    if (!tx.to || tx.to.toLowerCase() !== this.address.toLowerCase()) {
      return { ok: false, reason: "le paiement ne va pas vers l'agent" };
    }
    if (tx.value < minValue) {
      return { ok: false, reason: `paiement insuffisant (${tx.value} < ${minValue} wei)` };
    }
    return { ok: true, from: tx.from, value: tx.value };
  }
}
