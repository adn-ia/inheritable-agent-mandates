# Déploiement de référence — Base Sepolia (testnet)

`contracts/InheritableAgentMandate.sol` déployé sur **Base Sepolia** (chainId `84532`), avec une
démonstration on-chain de l'invariant `enfant ⊆ parent` : un enfant valide passe, quatre tentatives
d'évasion sont **revertées par la chaîne elle-même**.

> **Testnet uniquement, contrat non audité, aucune valeur réelle en jeu.** La clé de déploiement est
> jetable et ne quitte pas `.env` (gitignoré).

## Contrat

| | |
|---|---|
| Adresse | [`0x2d463db56fadb55cd451d2c3237ec2213ba3bda9`](https://sepolia.basescan.org/address/0x2d463db56fadb55cd451d2c3237ec2213ba3bda9) |
| Réseau | Base Sepolia (`84532`) |
| Gardien | `0x448Cc1c5689D9dFA2474265053A8FDF4bEb3B0Ae` |
| Tx de déploiement | [`0x4f5bfe38…f4535`](https://sepolia.basescan.org/tx/0x4f5bfe38fa8ba03254e055b259a3d7d99005921817a67c7877463d8f11ff4535) |
| Bloc | 44836238 |
| Compilateur | solc 0.8.36, optimiseur activé (200 runs) |

## Démonstration on-chain

**Mandat racine** (agentId `2`) : plafond 0,01 ETH · télomère 3 · bail obligatoire · une payee
autorisée (`0x…dEaD`).

### Ce qui passe

| Étape | Transaction | Résultat |
|---|---|---|
| Mint du mandat racine | [`0x1bc6e609…2749c`](https://sepolia.basescan.org/tx/0x1bc6e609baaa54e6a8c1b4eae5f4db2bd3977d48b47471f843cf7be0afb2749c) | `success` — agentId 2 |
| Spawn d'un enfant **valide** (agentId `3`) | [`0x2b016632…89bbd`](https://sepolia.basescan.org/tx/0x2b01663241a13e3949f4af74d4a71d383d224c33dbeb08a53f3a63a09e589bbd) | `success` |

L'enfant est strictement plus restreint que son parent sur chaque clause : plafond 0,004 ≤ 0,01,
télomère 2 = 3−1, bail conservé, payees ⊆ parent.

### Ce que la chaîne refuse

Quatre évasions tentées depuis le même parent. Chacune est une **transaction réelle**, incluse dans
un bloc et `reverted` — pas une simulation.

| Évasion tentée | Transaction | Motif du revert |
|---|---|---|
| Élargir le plafond (0,01 → 100 ETH) | [`0x871f9d81…9db4d`](https://sepolia.basescan.org/tx/0x871f9d8132b32ec8196a9cdf62f58f8e44a629e24264c134a91db956b0c9db4d) | `spend cap cannot exceed parent` |
| Remettre le télomère à neuf (2 → 99) | [`0xd8c02ac5…11cfc`](https://sepolia.basescan.org/tx/0xd8c02ac54f4c5c5eb02287039e8d22081bd19938cc7421c6cdf4c8bd21611cfc) | `telomere must be parent-1` |
| Couper le bail hérité | [`0xa974ca0c…8fcd4d`](https://sepolia.basescan.org/tx/0xa974ca0cc5a2aa782208366dc8f5beedbe14d0617372817f27686d07f88fcd4d) | `cannot disable inherited lease` |
| Payer hors allowlist du parent | [`0xc04f9bc9…6ab5`](https://sepolia.basescan.org/tx/0xc04f9bc99cf2fb18831f6d6658c1aed0179a4c511bde00204882022c91cb6ab5) | `payee not in parent allowlist` |

C'est le point de la démonstration : l'enfant ne peut pas être plus capable que son parent, et le
refus ne dépend d'aucune bonne volonté hors-chaîne — il est appliqué par le contrat, dans le bloc.

## Reproduire

```bash
npm install
npx tsx scripts/compile.ts          # compile → build/InheritableAgentMandate.json
npx tsx scripts/deploy-key-new.ts   # clé jetable → .env (adresse à financer imprimée)
# financer l'adresse à un faucet Base Sepolia, puis :
npx tsx scripts/deploy.ts           # déploie → build/deployment.json
npx tsx scripts/demo-onchain.ts     # mint + spawn valide + 4 évasions rejetées
```

Les identifiants d'agents sont lus dans les événements `Minted` / `Spawned` du reçu de transaction,
et non par relecture de `nextId` — un nœud RPC public peut servir un état périmé juste après une
écriture.

## Vérification indépendante

Sans faire confiance à ce fichier :

```bash
cast call 0x2d463db56fadb55cd451d2c3237ec2213ba3bda9 "guardian()(address)" \
  --rpc-url https://sepolia.base.org
cast tx 0x871f9d8132b32ec8196a9cdf62f58f8e44a629e24264c134a91db956b0c9db4d \
  --rpc-url https://sepolia.base.org
```

Ou simplement les liens BaseScan ci-dessus : le statut `Fail` des quatre transactions d'évasion est
public et vérifiable par n'importe qui.

## Limites, dites franchement

Le contrat est **minimal et non audité**. Il démontre l'invariant d'héritage, pas une logique de
dépense complète : `maxSpendWei` est une clause portée par l'identité, pas un compteur de dépense
réelle — ce comptage-là est le domaine d'ERC-8312. `isActive()` remonte la chaîne des ancêtres à
chaque appel, ce qui est acceptable pour une lignée courte mais pas pour un arbre profond. Le
gardien est ici la même clé que le déployeur, ce qui n'aurait aucun sens en production.
