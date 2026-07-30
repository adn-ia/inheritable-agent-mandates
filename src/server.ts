import express, { type Request, type Response } from "express";
import { formatEther, type Hex } from "viem";
import { config } from "./config";
import type { AgentWallet } from "./wallet";
import type { Ledger } from "./ledger";
import { runTask } from "./task";
import { geneId } from "./genome";
import { guardianVerdict } from "./guardian";

/**
 * M0 — L'ENDPOINT PAYANT (organe "Marché").
 *
 * POST /task ne sert la tâche qu'APRÈS avoir constaté un paiement on-chain :
 *   1) le client envoie `TASK_PRICE_ETH` à l'adresse de l'agent,
 *   2) il rappelle /task avec l'en-tête `x-payment-tx: <hash>`.
 * Vérification de la tx, refus du rejeu, puis exécution. x402 fait maison.
 */
export function createServer(wallet: AgentWallet, ledger: Ledger) {
  const app = express();
  app.use(express.json());

  app.get("/", (_req: Request, res: Response) => {
    res.json({
      species: "adn-ia",
      geneId: geneId(),
      agent: wallet.address,
      guardian: config.guardianAddress,
      alive: ledger.alive,
      how: "POST /task avec en-tête x-payment-tx après avoir payé l'agent. Voir /status.",
    });
  });

  app.get("/status", async (_req: Request, res: Response) => {
    res.json({
      agent: wallet.address,
      onchainBalanceEth: await wallet.balanceEth(),
      priceEth: formatEther(config.taskPrice),
      control: await guardianVerdict(),
      ...ledger.snapshot(),
    });
  });

  app.post("/task", async (req: Request, res: Response) => {
    if (!ledger.alive) {
      return res.status(503).json({ error: "organisme dormant", agent: wallet.address });
    }

    const txHash = req.header("x-payment-tx") as Hex | undefined;
    if (!txHash) {
      return res.status(402).json({
        error: "paiement requis",
        payTo: wallet.address,
        priceEth: formatEther(config.taskPrice),
        priceWei: config.taskPrice.toString(),
        chainId: config.chain.id,
        then: "renvoyer la requête avec l'en-tête x-payment-tx: <hash>",
      });
    }
    if (ledger.isPaymentUsed(txHash)) {
      return res.status(402).json({ error: "ce paiement a déjà été utilisé (anti-rejeu)" });
    }

    const check = await wallet.verifyIncomingPayment(txHash, config.taskPrice);
    if (!check.ok) {
      return res.status(402).json({ error: "paiement invalide", reason: check.reason });
    }

    try {
      const output = runTask({ text: (req.body?.text as string) ?? "" });
      ledger.recordIncome(txHash, check.value ?? config.taskPrice);
      return res.json({ paidFrom: check.from, ...output });
    } catch (err) {
      return res.status(400).json({ error: String((err as Error).message) });
    }
  });

  return app;
}
