# Simulation privée — `ProvenanceRegistry` v2 : les deux options de chaque axe

**Document local, non committé.** Le code de simulation vit **hors du dépôt**
(`ProvenanceRegistryV2.sol`, `ProvenanceRegistryV2Domain.sol`, deux suites Foundry). Ni
`contracts/ProvenanceRegistry.sol` ni l'instance déployée à `0x202f4eef…f5df` n'ont été touchés.

Exécution locale, `forge test`, **aucun gaz de testnet**. Rien n'est committé, poussé ni posté.

Base commune : copie de v1 + le champ **`implementationCommit`** dans `Record`, `register`,
`recordOf` et l'event. Le reste — write-once, parent inconnu rejeté, self-parent rejeté,
`MAX_NODES = 64` — est inchangé.

---

# AXE 1 — `heritageCluster` : dérivé vs stocké

Les deux options sont implémentées **dans le même contrat**, pour être lues sur le même graphe :

- **A — dérivé** : `sameHeritageCluster(a, b, maxDepth)` renvoie exactement `shareLineage`.
- **B — stocké** : champ `heritageCluster` auto-déclaré ; `sameStoredCluster(a, b)` compare les tags.

## Sorties brutes

### Le scénario, les deux options côte à côte

Graphe : `X` et `Y` ont `A` pour ancêtre commun **à profondeur 2** ; `Z` est indépendant.
Tags déclarés : **les trois portent le même**, `cluster-1`.

| `maxDepth` | dérivé `(X,Y)` | dérivé `(X,Z)` | stocké `(X,Y)` | stocké `(X,Z)` |
|---|---|---|---|---|
| 1 | `false` | `false` | `true` | `true` |
| 2 | `true` | `false` | `true` | `true` |
| 3 | `true` | `false` | `true` | `true` |

Le stocké ne dépend d'aucune profondeur — il rend la même chose partout.

### 1 — le dérivé est-il identique à `shareLineage` ?

```
testFuzz_1_derive_identique_a_shareLineage(uint8, uint8)  —  256 exécutions, 0 échec
   assertion : sameHeritageCluster(a,b,d) == shareLineage(a,b,d)
```

### 2 — la profondeur inverse le verdict du dérivé

```
maxDepth 0 → false
maxDepth 1 → false
maxDepth 2 → true
maxDepth 3 → true
```

### 3 — faux positif du stocké

`Y` et `Z` : **aucun ancêtre commun**, mais le même tag déclaré.

```
shareLineage(Y,Z, 8)        : false
dérivé  sameHeritageCluster : false
stocké  sameStoredCluster   : true      ← écart
```

### 4 — faux négatif du stocké

`X` et `Y` **partagent** `A`, mais déclarent des tags différents.

```
shareLineage(X,Y, 8)        : true
dérivé  sameHeritageCluster : true
stocké  sameStoredCluster   : false     ← écart

variante, tags laissés à zéro :
shareLineage(X,Y, 8)        : true
stocké  sameStoredCluster   : false     ← écart
```

### 5 — ce que chaque option coûte à falsifier

```
le stocké peut-il être posé SANS aucun parent ?
   parentsOf(A).length : 0
   parentsOf(Z).length : 0
   sameStoredCluster(A,Z) : true
   shareLineage(A,Z, 8)   : false

le dérivé peut-il rater un lien réel non déclaré en parent ?
   M déclare A ; N ne déclare rien alors que (vérité-terrain du test) il dérive de A
   dérivé sameHeritageCluster(M,N, 8) : false
   stocké sameStoredCluster(M,N)      : false
```

### 6 — coût en gaz, même graphe

```
dérivé, maxDepth 3 : 12 953
dérivé, maxDepth 8 : 12 959
stocké             :  1 447
```

## Tableau comparatif — axe 1

| | **A — dérivé** | **B — stocké** |
|---|---|---|
| **Attrape** | tout lien exprimé par une chaîne de parents, jusqu'à `maxDepth` | tout ce qui porte le même tag, sans limite de profondeur |
| **Rate** | un lien réel **non déclaré** comme parent (mesuré : `M,N → false`) ; un ancêtre **au-delà de `maxDepth`** (mesuré : `false` à 1, `true` à 2) | un lien réel dont les auteurs ont mis des tags différents ou nuls (mesuré, deux fois) |
| **Fabrique** | rien : la lecture ne peut pas inventer un lien absent du graphe | un cluster **sans aucune ascendance** — mesuré avec zéro parent déclaré des deux côtés |
| **Coût à falsifier** | il faut mentir sur un **parent**, ce qui est un fait vérifiable par recoupement | il suffit d'**écrire un mot** dans un champ libre, sans rien déclarer d'autre |
| **Coût en gaz** | ~12 950, quasi plat de la profondeur 3 à 8 | ~1 450, soit **9× moins cher** |
| **Dépend de** | la profondeur demandée — le verdict change avec `maxDepth` | rien : réponse stable, mais stable sur une déclaration |

---

# AXE 2 — namespace : instances séparées vs tag de domaine

## Sorties brutes

### Option A — deux instances séparées

```
attestataire enregistré dans l'instance 2
l'instance 1 tente de le déclarer comme parent
   issue : REVERTE — "unknown parent"

lecture croisée depuis l'instance 1 :
   shareLineage(interpréteur, attestataire, 8) : false   (les clés n'y existent pas)
```

### Option B — tag de domaine, **sans** verrou

```
collision : même id brut sous deux domaines → clés distinctes : true
les deux enregistrés dans la MÊME instance

LE TEST QUI COMPTE — un interpréteur déclare l'attestataire comme PARENT
   issue : ABOUTIT
   shareLineage(enfant-interpréteur, attestataire, 8) : true
```

### Option B-bis — tag de domaine **avec** verrou `domaine(parent) == domaine(enfant)`

```
domainOf(attestataire) == DOM_ATTEST : true
domainOf(interpréteur) == DOM_INTERP : true

même tentative cross-domaine
   issue : REVERTE — CrossDomainParent(childDomain, parentDomain)

contrôle — un parent du MÊME domaine passe-t-il toujours ?
   issue : ABOUTIT
   shareLineage(interp-3, interp-1, 8) : true
```

### Coût de déploiement

```
deux instances séparées, gaz cumulé : 1 302 418
une instance avec verrou de domaine :   580 727
```

## Tableau comparatif — axe 2

| | **A — instances séparées** | **B — tag de domaine seul** | **B-bis — tag + verrou** |
|---|---|---|---|
| **Collision d'`id`** | impossible : espaces disjoints | évitée — clés distinctes mesurées | évitée |
| **Lignée cross-domaine** | **impossible** — `unknown parent` | **POSSIBLE** — mesurée : `register` aboutit et `shareLineage` rend `true` | **impossible** — `CrossDomainParent` |
| **Ce qui l'empêche** | l'architecture : la clé n'existe pas dans l'autre instance | rien | un `require` au `register` |
| **Coût de déploiement** | 1 302 418 gaz | 580 727 gaz | 580 727 gaz |
| **Coût de lecture croisée** | impossible par construction | possible, donc à surveiller | bloquée à l'écriture |
| **Ce qu'il reste à faire confiance** | rien : l'isolation est structurelle | l'honnêteté de qui déclare les parents | le verrou lui-même, une ligne de code |

---

# Interprétation — déduite des mesures

## Axe 1 — le compromis, en chiffres

Les deux options **ne mesurent pas la même chose**, et le scénario côte à côte le montre sans
ambiguïté : sur le même graphe, avec le même tag posé partout, le dérivé distingue `X,Y` (ancêtre
réel) de `X,Z` (aucun lien), tandis que le stocké rend `true` aux deux.

**Le stocké fabrique.** C'est le résultat le plus net : deux nœuds sans **aucun** parent déclaré, qui
posent le même mot dans un champ libre, sont rendus « du même cluster ». Il n'y a rien derrière —
`shareLineage` rend `false`, `parentsOf` est vide des deux côtés. Le coût de fabrication d'un faux
cluster est **un mot**.

**Le dérivé rate.** Deux limites mesurées, de nature différente. La première est réparable : un lien
au-delà de `maxDepth` réapparaît si on remonte plus loin — le verdict dépend de la question posée,
pas du graphe. La seconde ne l'est pas : un lien réel que personne n'a déclaré comme parent est
**invisible**, et aucune profondeur ne le fera apparaître.

**Le gaz penche pour le stocké** — 1 447 contre 12 953, neuf fois moins. Mais le dérivé est quasi
plat entre les profondeurs 3 et 8 (12 953 → 12 959), donc le coût ne dérape pas avec la profondeur
sur ce graphe.

**Ce que les mesures suggèrent, sans trancher pour vous.** Les deux options échouent, mais pas dans
le même sens. Le dérivé se trompe **par omission** — il ne voit que ce qui a été déclaré comme
parent. Le stocké se trompe **par affirmation** — il croit ce qu'on lui écrit. Pour un usage où le
cluster sert à *repérer une corrélation qu'on ne veut pas manquer*, un faux positif fabriqué en un
mot est plus dangereux qu'un faux négatif : il permet à quiconque de se déclarer apparenté, ou de
noyer un vrai cluster dans un tag partagé.

Une troisième voie apparaît dans les sorties sans avoir été demandée : les deux lectures peuvent
coexister — c'est le cas dans le contrat de simulation, qui les expose toutes les deux. `clusterOf`
resterait alors une **déclaration** lisible comme telle, et `sameHeritageCluster` la **dérivation**
vérifiable. Rien dans ces mesures n'oblige à n'en garder qu'une.

## Axe 2 — la question est tranchée par la mesure

L'hypothèse à confirmer ou infirmer était : *le tag de domaine seul n'empêche pas la lignée
cross-domaine*. **Elle est confirmée, et de la façon la plus directe** : l'interpréteur a déclaré
l'attestataire comme parent, `register` a abouti, et `shareLineage` rend `true`. Un interpréteur et
un attestataire sont devenus cousins dans le registre, sans qu'aucune règle ne s'y oppose.

Le tag fait ce pour quoi il est fait — éviter les collisions d'identifiants, mesuré — et **rien de
plus**. Il ne porte aucune sémantique d'isolation tant qu'on ne l'accompagne pas d'un `require`.

Les instances séparées obtiennent l'isolation **gratuitement, au sens architectural** : il n'existe
aucun chemin de code par lequel un parent d'une autre instance pourrait être accepté, puisque la clé
n'y existe pas. Le refus n'est pas une règle qu'on a écrite, c'est une conséquence.

Le verrou de domaine obtient le même refus, mais **par une ligne de code** — donc quelque chose qui
peut être oublié dans une réimplémentation, ou retiré. En contrepartie, il coûte **2,2× moins cher**
à déployer que deux instances (580 727 contre 1 302 418) et garde tout dans un seul registre, ce qui
simplifie la lecture pour un consommateur tiers.

**Ce que les mesures disent, et pas plus :** le tag seul est insuffisant, ce n'est plus une opinion.
Entre les deux options qui, elles, fonctionnent, l'arbitrage porte sur ce qu'on préfère : une
isolation structurelle plus chère, ou une isolation par règle deux fois moins chère mais qui repose
sur une ligne qu'il faut maintenir.

---

# Limites

**C'est une copie de simulation, non déployée.** Rien de ce qui est mesuré ici ne dit comment se
comporterait le registre en production, ni ce que coûterait une migration depuis l'instance actuelle.

**Le registre reste déclaré, pas vérifié**, dans toutes les options. Aucune ne rend une lignée vraie :
elles rendent une lignée permanente, signée et attribuable. Le dérivé n'est pas « la vérité » — c'est
la lecture d'un graphe que des auteurs ont déclaré.

Un seul graphe par scénario, cinq à six nœuds. Le fuzz de l'axe 1 (256 exécutions) est la seule
mesure qui balaie autre chose qu'un cas choisi à la main.

Contrat et tests ont le même auteur. Les sorties sont brutes et reproductibles, mais personne d'une
autre lignée ne les a encore regardées.

**Rien n'est figé.** Ce document est fait pour choisir, pas pour justifier un choix déjà fait.

## Reproduire

```bash
cd <dossier de simulation>/provv2
forge test --match-contract Axe1ClusterTest  -vv
forge test --match-contract Axe2NamespaceTest -vv
```
