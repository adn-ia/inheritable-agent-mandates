# 🧬 ADN-IA — containment **héritable** pour agent on-chain (M0 + M1 + M3)

> **Inheritable Agent Mandates** — control clauses bound to an agent's on-chain identity,
> non-strippably inherited by spawned children (`child ⊆ parent`). Testnet only (Base Sepolia).
> Canonical write-up: [`whitepaper/inheritable-agent-mandates.md`](whitepaper/inheritable-agent-mandates.md) ·
> draft standard: [`eip/inheritable-agent-mandate.md`](eip/inheritable-agent-mandate.md).

On associe une chaîne crypto à une IA, **la chaîne étant l'ADN** : le code immuable qui
définit et prouve son identité (`geneId`). Un runtime le lit et le rend vivant ; un
métabolisme le nourrit ou le laisse mourir ; un humain garde la clé qui le maintient en vie.

Et surtout — c'est la partie que la recherche a trouvée **non construite** à la mi-2026 —
les **clauses de contrôle sont inscrites dans l'identité** et **héritées par l'enfant au
spawn**, sans pouvoir être élargies ni arrachées. C'est la « 3ᵉ patte ».

Tout est en **testnet (Base Sepolia)**. Aucun argent réel.

---

## Les documents

- **Livre blanc** (EN, canonique) — [`whitepaper/inheritable-agent-mandates.md`](whitepaper/inheritable-agent-mandates.md)
- **EIP — brouillon de standard** — [`eip/inheritable-agent-mandate.md`](eip/inheritable-agent-mandate.md)
- **Explications grand public** — [FR](vulgarise/Une-IA-en-laisse_FR.pdf) · [EN](vulgarise/Keeping-an-AI-on-a-leash_EN.pdf)
- **Licence** — [CC0](LICENSE.md)

### Contrats et démos on-chain (Base Sepolia, testnet, non audités)

| Contrat | Ce qu'il fait | Démo + hashs |
|---|---|---|
| [`contracts/InheritableAgentMandate.sol`](contracts/InheritableAgentMandate.sol) | `spawn()` impose `enfant ⊆ parent`, identité non transférable, `freeze` en cascade | [**`DEPLOY.md`**](DEPLOY.md) |
| [`contracts/ProvenanceRegistry.sol`](contracts/ProvenanceRegistry.sol) | registre de lignée **write-once** : le hash porte l'identité, la provenance est déclarée à part | [**`DEMO-PROVENANCE.md`**](DEMO-PROVENANCE.md) |

Les deux documents donnent l'adresse déployée, **les hashs de transaction vérifiables** sur
`sepolia.basescan.org`, et une commande de repro. Chacun distingue explicitement ce qui est
**prouvé** (un invariant que la chaîne fait respecter) de ce qui est seulement **illustré**.

#### Tests internes — question provenance / contestation

Deux expériences menées autour du `ProvenanceRegistry`, sur testnet. Ce ne sont **pas** des organes
du système : ce sont des tests, avec leurs sorties brutes et leurs limites écrites noir sur blanc.

- [`TEST-CONTESTATION.md`](TEST-CONTESTATION.md) — une couche séparée, append-only, permet à un
  tiers d'asserter une lignée que l'auteur a omise, **sans jamais modifier le socle**. Le test
  montre aussi que le contrat ne distingue pas une assertion fondée d'une assertion infondée.
- [`TEST-CYCLE.md`](TEST-CYCLE.md) — comportement de la traversée face à un cycle d'arêtes
  assertées : coût et terminaison relevés à cinq profondeurs.

Dans les deux cas, le socle déployé n'est ni modifié ni redéployé, et le contrat de contestation
utilisé reste un **artefact d'expérience**, non un composant du dispositif.

---

## La 3ᵉ patte — ce que personne n'assemble

Un contrôle d'agent utile a besoin de trois choses ensemble. Les acteurs existants en ont
au mieux deux :

| | Identité on-chain | Clauses de contrôle | **Hérité par l'enfant** |
|---|:---:|:---:|:---:|
| ERC-8004 | ✅ | ❌ | ❌ |
| ERC-8312 (Bounded Agent Actions) | ✅ (via 8004) | ✅ | ◐ (dépense agrégée seulement) |
| ERC-8226 / thirdweb mandate | ❌ | ✅ | ❌ |
| CDP / MetaMask / thirdweb keys | ❌ | ✅ (par instance) | ❌ |
| custodian-kernel | ❌ | ✅ | ✅ (off-chain) |
| **ADN-IA (ce repo)** | ✅ | ✅ | ✅ (mandat entier) |

ERC-8312 transporte bien quelque chose jusqu'à l'enfant — un plafond de dépense agrégé sur l'arbre
de délégation. Ce qui reste non couvert est le **reste** du mandat : payees, expiry, gel en cascade,
compteur de génération, soudés à l'identité. C'est la revendication resserrée du white paper.

Le mandat (`genome.mandate`) fait partie du génome, donc du `geneId` : l'identité **est** le
hash de {politique + mandat}. Conséquences : l'IA ne peut pas s'arracher ses clauses sans
changer d'identité, et tout enfant hérite du mandat au spawn — une génération en moins,
jamais élargi. La version on-chain de référence est `contracts/InheritableAgentMandate.sol`
(identité non transférable ≈ soulbound, `spawn()` impose enfant ⊆ parent, `freeze` en cascade).

---

## Démo de la 3ᵉ patte (hors-ligne, 30 s)

```bash
npm install
npm run wallet:new        # → PRIVATE_KEY (agent)
npm run guardian:new      # → GUARDIAN_ADDRESS (+ GUARDIAN_PRIVATE_KEY à part)
cp .env.example .env      # colle PRIVATE_KEY, GUARDIAN_ADDRESS, GUARDIAN_PRIVATE_KEY

npm run guardian -- spawn # le gardien autorise la reproduction
npm run reproduce         # naissance d'un enfant + rejet des évasions
```

Sortie attendue : trois verrous franchis (autorisation gardien, télomère, fitness), un enfant
né avec `télomère=7` (hérité de 8−1) et le même plafond/bail, puis **trois tentatives
d'évasion rejetées** (remettre son télomère à neuf, couper le bail, doubler le plafond).

---

## Les organes

| Organe | Fichier | Rôle |
|---|---|---|
| 🧬 Génome + **Mandat** | `src/genome.ts`, `src/mandate.ts` | politique + clauses de contrôle, inscrites dans `geneId` |
| 🪪 Identité | `src/identity.ts` | registre façon ERC-8004 (agentId + lignée) |
| 👶 Lignée | `src/lineage.ts` | spawn contrôlé + `verifyDescendant` (non-arrachabilité) |
| ⚙️ Ribosome | le runtime (`tsx`) | lit le génome et l'exécute |
| 🌐 Marché (M0) | `src/server.ts` | endpoint payant, paiement vérifié on-chain |
| ❤️ Métabolisme (M1) | `src/wallet.ts`, `src/metabolism.ts` | gagne / dépense seul, meurt si le solde s'épuise |
| 🔒 Contrôle | `src/guardian.ts` | substrat : bail de vie, arrêt, embargo (clé humaine) |
| 🧫 Sélection | `src/ledger.ts` | comptabilité + fitness (porte de reproduction) |
| ⛓️ On-chain (réf.) | `contracts/InheritableAgentMandate.sol` | enfant ⊆ parent imposé par le protocole |

---

## Faire vivre l'organisme (M0 + M1)

```bash
# alimente l'agent au faucet Base Sepolia, puis :
npm run guardian -- lease 24   # sans bail, il naît dormant
npm start
```

Le nourrir : `GET /status` pour le prix + l'adresse, paie l'agent on-chain, puis
`POST /task` avec l'en-tête `x-payment-tx: <hash>`. Le cœur bat (`❤️`) à chaque loyer payé ;
sous le seuil, `💀 MORT`.

Piloter le gardien : `npm run guardian -- <lease [h] | embargo | kill | spawn>`
(lever un embargo/arrêt : supprimer `data/embargo.json` / `data/kill.json`).

---

## Ce que chaque chose prouve

- **M0** — `/task` refuse sans paiement vérifié → l'organisme se nourrit.
- **M1** — le loyer est prélevé à chaque battement ; sous le seuil → il meurt de ses dépenses.
- **Contrôle** — couper le bail (ou `kill`) → dormant ; `embargo` → dépenses gelées.
- **M3 (3ᵉ patte)** — l'enfant hérite du mandat, ne peut pas l'élargir, et toute évasion
  change son `geneId` → échoue au portail `verifyDescendant`.

```
enfant ⊆ parent  ⇔  télomère = parent−1  ∧  plafond ≤ parent  ∧  payees ⊆ parent  ∧  bail ≥ parent
```

---

## Limites honnêtes

- **Substrat pas encore vraiment externe.** Contrôle et agent tournent dans le même process ;
  en vrai il faut une infra distincte de confiance (attestation/ZKML). Le proto montre la forme.
- **Le contrôle tient tant que l'organisme ne peut pas s'évader.** Un agent capable d'écrire du
  code arbitraire, de déployer et de se financer seul peut se reproduire hors de ce cadre. Seule
  l'écologie (infra, argent, surveillance) l'arrête, et à un coût.
- **Les contrats sont déployés en testnet, mais non audités.** `InheritableAgentMandate.sol` et
  `ProvenanceRegistry.sol` tournent sur Base Sepolia (voir [`DEPLOY.md`](DEPLOY.md) et
  [`DEMO-PROVENANCE.md`](DEMO-PROVENANCE.md)) : les invariants sont vérifiables on-chain, pas
  seulement affirmés. Ça ne remplace pas un audit, et rien n'a de valeur réelle.
- **La provenance est déclarée, pas vérifiée.** Le registre garantit qu'une lignée déclarée est
  permanente, signée et attribuable — pas qu'elle est vraie. Mentir reste possible, mais devient
  visible et imputable.
- **Transférabilité.** ERC-8004 rend l'agentId transférable (rien ne persiste au transfert) ;
  la non-arrachabilité complète suppose une identité soulbound — probablement une extension d'EIP,
  pas juste un module. Le contrat de référence choisit déjà de ne pas exposer de transfert.

---

## Étapes suivantes

- **M2 — résurrection** : génome sur Arweave, tuer le process, ré-instancier ailleurs.
- **Audit** : les deux contrats sont déployés en testnet et testés on-chain, mais **non audités**.
- **Standard** : l'EIP brouillon existe ([`eip/`](eip/inheritable-agent-mandate.md)) ; reste à ouvrir
  un fil de discussion dédié et à renseigner son champ `discussions-to:`.
- **Relecture externe** : contrats et tests ont le même auteur. Une relecture par quelqu'un d'une
  autre lignée vaudrait plus que n'importe quel document de ce dépôt.

### Non-contournabilité — le prochain chantier

L'interface, le compteur et le mandat ne peuvent pas être non-contournables à eux seuls : rien ne
force la valeur à passer par eux (un agent qui garde ses clés dépense à côté). La
non-contournabilité s'obtient au niveau du **substrat**, en faisant du mandat la seule porte — soit
par **custody** (le substrat détient les actifs, l'agent n'a pas les clés de l'argent), soit par une
**porte d'exécution** (compte AA / ERC-4337-7579 dont l'unique chemin passe par un module qui vérifie
le mandat).

**Question ouverte :** ancrer le mandat dans un tel substrat pour que la non-contournabilité soit une
**propriété**, pas une promesse.

**Plafond honnête :** un agent capable de code arbitraire et d'auto-financement s'échappe de toute
cage unique ; le résidu est borné par le coût et l'écologie, pas nul — « moins probable, plus
visible ».

