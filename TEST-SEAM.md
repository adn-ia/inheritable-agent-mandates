# Test de couture — `InheritableAgentMandate` face au registre de référence ERC-8312

Réponse concrète à l'invitation de blockbird (#61 sur le fil ERC-8312) : *« point your prototype's
mandate at a capabilityRoot in a conforming registry and open whatever breaks »*.

Intégration **locale sous Foundry**, aucun déploiement testnet. Contrats non audités, preuve de
concept, aucune valeur réelle en jeu.

> **Sa source n'a jamais été modifiée.** Elle est clonée dans un dossier séparé, importée telle
> quelle, et n'entre pas dans ce dépôt. Aucun patch n'a été appliqué chez lui pour forcer la
> compatibilité : quand ça ne rentre pas, le refus **est** le résultat.

## Ce qui est intégré

| | Origine |
|---|---|
| `EnvelopeRegistry`, `AggregateBudgetCursor` | [`ERC8312/bounded-agent-actions`](https://github.com/ERC8312/bounded-agent-actions), commit `afab44c`, non modifié |
| `InheritableAgentMandate` | ce dépôt, [`contracts/InheritableAgentMandate.sol`](contracts/InheritableAgentMandate.sol) |

Outillage : Foundry 1.7.1, `forge-std` v1.16.2, compilation sous **son** profil (`solc 0.8.24`,
`evm_version = cancun`, optimiseur 200 runs).

---

## Sorties brutes

### Baseline — sa suite, sur son dépôt non modifié

```
forge install foundry-rs/forge-std     →  forge-std v1.16.2
forge test                             →  61 tests passed, 0 failed, 0 skipped (5 suites)
```

Relancée après notre intégration : **61 / 0** à nouveau. `src/` et `test/` sont restés intacts,
octet pour octet. Seuls `foundry.toml` (`libs = []` → `["lib"]`) et le pointeur de submodule ont
changé — produits par `forge install`, la commande de son propre README.

### Compilation de l'intégration

```
Compiling 28 files with Solc 0.8.24 — Compiler run successful!
[PASS] test_seam() (gas: 926864)
```

### a. `capabilityRoot` lié à l'identité de notre mandat

```
capabilityRoot proposé (hash liant agent + clauses) :
   0x6b044773ef24431e53c3e5d6ad3c913da98051e8524cbd66d513fe78750276b7

registerEnvelope(principal, ce root, 0, initData) :
   REVERTE — CapabilityMismatch()
```

La forme prescrite par le profil, pour comparaison :

```
registerEnvelope(keccak256(abi.encode(cap, asset))) :  ABOUTIT
   bound cap   = 1 ETH
   bound asset = 0x0000000000000000000000000000000000000000
   isActive    = true
   advanceCursor(0.1 ETH) : ABOUTIT
   spent       = 0.1 ETH
   remaining   = 0.9 ETH
```

### b. Enfant sous notre mandat, puis enveloppe pour cet enfant

```
mandat parent  agentId 1 · plafond 1 ETH
spawn enfant   agentId 2 · plafond 0.4 ETH   (child ⊆ parent, imposé par notre contrat)

registerEnvelope pour l'enfant, cap = 100 ETH :  ABOUTIT
```

Sur son profil agrégé, autre axe :

```
AggregateBudgetCursor.createRoot(cap = 1 ETH)
   delegate(nodeCap = 0.4 ETH)            → nodeId 1
   delegate depuis ce nœud plafonné       → REVERTE — CappedNodeCannotDelegate()
```

### c. Gel en cascade côté mandat, dépense côté 8312

```
avant freeze — mandate.isActive(enfant) = true    envelope.isActive() = true
freeze(parent)
après freeze — mandate.isActive(enfant) = false   envelope.isActive() = true
               envelope.remaining()     = 0.4 ETH

advanceCursor(0.05 ETH) après le gel :  ABOUTIT
   spent = 0.05 ETH
```

---

## Interprétation — écrite après coup, à partir des sorties ci-dessus

### (a) Une racine « opaque » à un niveau, épinglée à l'autre

L'interface de base `IBoundedAgentAction` traite `capabilityRoot` comme un `bytes32` opaque : elle
ne l'inspecte jamais. Le **profil Budget Substrate**, lui, en fixe la préimage —
`EnvelopeRegistry.sol` ligne 81 :

```solidity
if (capabilityRoot != keccak256(abi.encode(cap, asset))) revert CapabilityMismatch();
```

Conséquence observée : un `capabilityRoot` dérivé de l'identité de notre mandat est refusé. Les
**types** s'alignent parfaitement — c'est un `bytes32` de part et d'autre — mais la préimage
n'appartient pas à l'intégrateur sous ce profil.

La question que ça pose, et que nous n'avons pas les moyens de trancher seuls : **l'opacité
revendiquée est-elle celle de l'interface, ou celle du profil ?** Si c'est l'interface, un substrat
tiers peut faire porter au root ce qu'il veut, et il faudrait un profil distinct pour l'exprimer. Si
c'est le profil qui fait autorité en pratique, alors « opaque » décrit le contrat de base mais pas
ce qu'un intégrateur rencontre. C'est une question ouverte pour l'auteur, pas un défaut constaté.

### (b) Deux couches, deux contraintes qui ne se parlent pas

Notre contrat impose `child ⊆ parent` au spawn : l'enfant est plafonné à 0,4 ETH sous un parent à
1 ETH. Le registre a néanmoins accepté, pour ce même principal, une enveloppe plafonnée à **100 ETH**.

Rien dans les sorties ne suggère que le registre ait connaissance du mandat — et rien ne le
prévoyait : la structure `Envelope` ne porte aucun champ d'identité d'agent. **La contrainte
d'héritage n'est pas partagée entre les couches** : ce que notre contrat interdit à un enfant, le
metering l'ignore.

Sur son propre terrain, la règle symétrique existe et fonctionne : un nœud plafonné ne peut pas
déléguer du tout (`CappedNodeCannotDelegate()`). Les deux disciplines vont dans le même sens —
contraindre vers le bas — mais sur des axes différents et sans point de contact observé ici.

### (c) « Meters but does not enforce », vérifié plutôt que cité

Après `freeze(parent)`, notre contrat rend `isActive(enfant) = false` : la lignée est gelée de notre
côté. L'enveloppe correspondante reste `isActive() = true`, conserve 0,4 ETH de réserve, et
`advanceCursor` **aboutit** — la dépense est comptée normalement.

C'est exactement ce que son README annonce : *« It meters but does not enforce… non-bypassability is
a substrate obligation. »* La phrase n'est pas un avertissement de prudence rédactionnelle, elle
décrit un comportement qu'on peut exécuter. Un gel prononcé par le substrat ne traverse pas vers le
compteur tant que rien ne les relie explicitement.

### Ce que cette vérification vaut, et ce qu'elle ne vaut pas

Un bémol qui compte. **Aucune de ses cinq suites n'est un harnais abstrait** : ce sont des tests
concrets contre ses propres contrats, sans `abstract contract` qu'une implémentation tierce pourrait
hériter pour se faire valider. Sa conformité s'exécute donc sur son code, pas sur le nôtre.

Ce que nous avons obtenu est plus modeste que ce qu'on aurait pu espérer : **son code non modifié
accepte ou refuse nos appels**, et c'est son jugement, pas le nôtre. C'est une vérification par une
autre lignée, mais **partielle** — pas une suite de conformité braquée sur notre implémentation.

---

## Limites

Une seule intégration, un seul scénario par axe. Rien n'autorise à généraliser.

**Aucun déploiement testnet** : tout tourne en local sous Foundry. Les résultats sont reproductibles
par quiconque exécute les mêmes commandes, mais rien n'est ancré sur une chaîne publique.

Côté nous, contrat et test ont le même auteur, dans la même session. Côté lui, la source n'a pas été
modifiée — c'est la seule chose qui garantisse que les refus observés viennent de son code et non
d'un ajustement de notre part.

Une compose propre ne prouverait pas davantage que l'inverse : que des interfaces s'emboîtent ne dit
rien de la sûreté du système assemblé. Ce document rapporte des emboîtements et des refus, pas une
évaluation de sécurité.

## Reproduire

Le test d'intégration vit dans ce dépôt ; **la source de blockbird n'y est pas** et doit être clonée
à côté.

```bash
# 1. Foundry
curl -L https://foundry.paradigm.xyz | bash && foundryup

# 2. Son dépôt, cloné DANS integration/ (gitignoré, jamais committé ici)
cd integration
git clone https://github.com/ERC8312/bounded-agent-actions.git
cd bounded-agent-actions && forge install foundry-rs/forge-std && forge test   # baseline
cd ..

# 3. Le test de couture
forge test -vv
```

Le `foundry.toml` d'`integration/` importe sa source en lecture seule via le remapping `bounded/`,
et notre contrat via `adn/` → `../contracts/` — donc aucune copie dupliquée qui pourrait dériver.
`integration/bounded-agent-actions/` est dans le `.gitignore` : sa source ne rentre pas dans ce
dépôt. Aucun de ses fichiers n'est modifié par cette procédure, hormis ce que `forge install` écrit
lui-même (`foundry.toml`, pointeur de submodule).
