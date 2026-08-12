import "dotenv/config";
import { parseEther, getAddress, type Hex, type Address } from "viem";
import { base, baseSepolia } from "viem/chains";

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
 * Réseaux connus. `baseSepolia` reste le banc de preuve : c'est là que tourne l'agent et
 * que la batterie complète est exercée, gratuitement.
 *
 * `base` (mainnet, chainId 8453) n'existe que pour publier un contrat de RÉFÉRENCE, non
 * audité, qui ne détient aucun fonds. Le déploiement s'y fait avec une clé dédiée
 * (`MAINNET_DEPLOYER_KEY`), distincte de `PRIVATE_KEY` : l'agent ne touche jamais au
 * mainnet, et la clé mainnet ne fait jamais tourner l'agent.
 */
export const networks = {
  baseSepolia: {
    chain: baseSepolia,
    rpcUrl: process.env.RPC_URL ?? "https://sepolia.base.org",
  },
  base: {
    chain: base,
    rpcUrl: process.env.MAINNET_RPC_URL ?? "https://mainnet.base.org",
  },
} as const;

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
