import "dotenv/config";
import { parseEther, getAddress, type Hex, type Address } from "viem";
import { baseSepolia } from "viem/chains";

function required(name: string): string {
  const v = process.env[name];
  if (!v || v.trim() === "" || v.startsWith("0x...")) {
    throw new Error(
      `Variable d'environnement manquante: ${name}. Copie .env.example vers .env et remplis-la.`
    );
  }
  return v;
}

function ethEnv(name: string, fallback: string): bigint {
  return parseEther((process.env[name] ?? fallback) as `${number}`);
}

const computeProvider = getAddress(
  process.env.COMPUTE_PROVIDER ?? "0x000000000000000000000000000000000000dEaD"
);

/**
 * config = l'INFRASTRUCTURE (clés, réseau, prix, rythme, gardien).
 * Les CLAUSES DE CONTRÔLE héritables (plafond, allowlist, bail, télomère) ne sont PAS
 * ici : elles vivent dans le mandat du génome (genome.mandate), pour être inscrites dans
 * l'identité et héritées par les enfants.
 */
export const config = {
  chain: baseSepolia,
  rpcUrl: process.env.RPC_URL ?? "https://sepolia.base.org",
  privateKey: required("PRIVATE_KEY") as Hex,

  // Économie / infra (wei)
  taskPrice: ethEnv("TASK_PRICE_ETH", "0.00002"),
  computeCost: ethEnv("COMPUTE_COST_ETH", "0.000005"),
  deathThreshold: ethEnv("DEATH_THRESHOLD_ETH", "0.000001"),
  computeProvider,
  metabolismIntervalMs: Number(process.env.METABOLISM_INTERVAL_S ?? "30") * 1000,
  port: Number(process.env.PORT ?? "8080"),

  // Gardien humain (clé publique seulement — l'agent ne détient jamais la privée)
  guardianAddress: getAddress(required("GUARDIAN_ADDRESS")) as Address,
} as const;
