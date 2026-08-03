# Section 5 — un compteur de lignée adossé à un mandat soulbound

Suite du [test de couture](TEST-SEAM.md) et de son [démonstrateur](TEST-SEAM-DEMO.md). blockbird
(#64) a redirigé : les deux comportements que nous avions mesurés comme manquants — le gel, le
plafond hérité — existent bien, mais dans la **Section 5** (`IAggregateBudget`, profil « lignée »),
pas dans la Section 4 (profil plat, sans arbre). Sa phrase : *« Aim it at Section 5 and it becomes
the identity layer the lineage profile leaves open. »*

Ce document fait cela. Intégration locale sous Foundry, aucun déploiement testnet. Non audité,
preuve de concept, aucune valeur réelle en jeu.

> **Sa source n'est ni modifiée ni copiée dans ce dépôt.** Seule la **signature** de son interface
> est redéclarée chez nous. Son dépôt est cloné à part et gitignoré.

## Ce que la Section 5 laisse ouvert

Le profil porte déjà le gel (`revoke` coupe le sous-arbre) et l'atténuation (`nodeCap`). Deux choses
restent dehors, et ce sont celles que notre mandat vient combler :

- **le pont** — rien ne relie l'état d'un mandat externe à `revoke` : *« a freeze doesn't revoke a
  node, someone calls revoke »* ;
- **l'identité** — un nœud est une `address`, qui peut changer de mains.

---

## Sorties brutes

### Baseline — sa suite sur son dépôt non modifié

```
commit afab44c (inchangé après git fetch)
forge test  →  61 tests passed, 0 failed, 0 skipped
```

### N1 — conservation

```
cap racine 100 ETH · fan-out : 2 enfants de la racine + 1 petit-enfant plafonné à 30

draws 40 + 20 + 25            → spentRoot     85 ETH
                                 remainingRoot 15 ETH

draw de 20 (total 105 > 100)  → REVERTE — RootCapExceeded()
   spentRoot après             : 85 ETH   (inchangé)
   somme des draw admis ≤ cap  : true
```

### N2 — conformité

```
notre cursor, supportsInterface(0xc7cabe86) : true
              supportsInterface(0x01ffc9a7) : true
              supportsInterface(0xffffffff) : false
              supportsInterface(0xdeadbeef) : false

son cursor,   supportsInterface(0xc7cabe86) : true
```

L'identifiant est **calculé**, jamais écrit en dur — vérifié séparément :

```
type(IAggregateBudget).interfaceId  →  0xc7cabe86
```

#### Le blocage — sa suite n'est pas portable telle qu'elle est livrée

Sa `AggregateBudgetConformance.t.sol` est typée par interface (`IAggregateBudget internal agg`) et
documente : *« To conformance-test a different implementation, change `deploy()` »*. Tentative de la
pointer sur notre implémentation par héritage, sans toucher son fichier :

```
Error (4334): Trying to override non-virtual function. Did you forget to add "virtual"?
  --> bounded-agent-actions/test/AggregateBudgetConformance.t.sol:29:5
   |
29 |     function deploy() internal returns (IAggregateBudget) {
```

Le mot `virtual` n'apparaît nulle part dans le fichier.

#### Le contournement, hors de son dépôt et du nôtre

Copie jetable dans un dossier de travail, avec **un seul mot ajouté**. Écart complet, vérifié par
`diff` contre son original :

```
29c29
<     function deploy() internal virtual returns (IAggregateBudget) {
---
>     function deploy() internal returns (IAggregateBudget) {
```

Son fichier n'a pas bougé pendant l'opération :

```
sur disque          : 7504e535284f0134cdebd6bae9a0dbb027776cff41f5736eeb2ecc991685aa18
version committée   : 7504e535284f0134cdebd6bae9a0dbb027776cff41f5736eeb2ecc991685aa18
```

#### Ses neuf tests de conformité, pointés sur notre implémentation

```
[PASS] test_Conformance_AdvertisesInterfaceIds
[PASS] test_Conformance_AttenuationAloneIsInsufficient
[PASS] test_Conformance_DeepChainMetersRoot
[PASS] test_Conformance_InterfaceIdIsStable
[PASS] test_Conformance_OnlyNodeAgentDraws
[PASS] test_Conformance_OnlyParentAgentDelegates
[PASS] test_Conformance_RevocationDoesNotRefund
[PASS] test_Conformance_SiblingsShareOneMeter
[PASS] test_Conformance_ViewsAreCoherent

9 passed; 0 failed; 0 skipped
```

### N3 — le pont

```
alice adossée à l'agentId 1
avant gel : draw(10) aboutit         → spentRoot 10 ETH

freeze(mandat d'alice) — SANS aucun appel à revoke
   mandate.isActive : false
   isPathActive     : true
   draw après gel   : REVERTE — MandateFrozen(agent, agentId)
   spentRoot        : 10 ETH   (inchangé)
```

### N3b — la vue additive, à côté de la vue spec-exacte

```
avant gel  — isPathActive : true    isDrawable : true
freeze(mandat), sans revoke
après gel  — isPathActive : true    isDrawable : false
             draw          : REVERTE — MandateFrozen(agent, agentId)

après un revoke explicite, en plus du gel
             isPathActive : false   isDrawable : false

nœud sans mandat adossé (comportement de référence)
             isPathActive : true    isDrawable : true
```

Ses neuf tests de conformité, relancés **après** l'ajout de `isDrawable` :

```
9 passed; 0 failed; 0 skipped
```

Gaz identique à l'unité près sur les neuf. `type(IAggregateBudget).interfaceId` vaut toujours
`0xc7cabe86` — l'ajout est hors interface, donc l'empreinte ne dérive pas. Son fichier de
conformité n'a pas bougé : SHA-256 `7504e535…85aa18`, identique à la version committée.

### N4 — contraste, son cursor non modifié

```
mandate.isActive : false        son isPathActive : true
son draw, mandat gelé          : ABOUTIT
   son spentRoot               : 10 ETH

après revoke manuel — son isPathActive : false
```

### Identité

```
bob tente d'adosser son adresse à l'agentId d'alice : REVERTE — NotMandateOwner()
alice l'adosse    : boundAgentId(alice) = 1
                    boundAgentId(bob)   = 0

ABI complète du mandat :
   freeze, guardian, isActive, mandateOf, mint, nextId, ownerOf, parentOf,
   payeeAllowed, spawn
   → aucune fonction transfer, approve ou permit
```

### Contrôles

```
MandateAwareAggregateCursor compile SEUL, sans sa source : 5 602 octets (solc 0.8.36)
nos suites d'intégration (seam + démo + section 5)       : 8 tests, 0 échec
son src/ et test/                                        : intacts, octet pour octet
son dépôt dans notre index                               : aucun fichier
```

---

## Interprétation — écrite après coup, à partir des sorties ci-dessus

### Ce qui est réellement établi

**Ses neuf tests de conformité passent sur notre implémentation.** C'est le résultat qui compte, et
c'est le premier de cette session à ne pas venir de nous : ses assertions, son vocabulaire, sa
définition de ce qui est normatif. Jusqu'ici, nos tests internes étaient écrits par la même main que
le code qu'ils vérifiaient. Ici, la propriété de conservation, la frontière de non-conformité par
amplification, la révocation sans remboursement, la cohérence des vues — tout cela est jugé par du
code que nous n'avons pas écrit.

**La conservation tient malgré notre crochet.** N1 le montre indépendamment : sur un arbre avec
fan-out et un nœud plafonné, la somme des tirages admis reste sous le plafond de la racine, et le
tirage qui aurait porté le total à 105 est refusé. Ajouter une consultation externe dans `draw`
pouvait très bien casser cet invariant ; les chiffres disent que non.

**L'identifiant d'interface est calculé, pas déclaré.** `0xc7cabe86` sort de notre redéclaration.
Une divergence d'un seul paramètre l'aurait fait dériver, et `test_Conformance_InterfaceIdIsStable`
— l'un des neuf — l'aurait attrapé.

### Ce qui est illustré par construction — pas une découverte

**N3.** Le refus après gel vient d'une ligne que nous avons écrite :

```solidity
if (!mandate.isActive(agentId)) revert MandateFrozen(agent, agentId);
```

Nous décidons de refuser, puis nous l'exécutons. Ce que N3 montre, c'est **la forme** du pont : un
gel prononcé sur le mandat coupe les tirages du sous-arbre **sans qu'aucun `revoke` ne soit appelé**.
Il ne démontre pas que cela fonctionne — il montre à quoi cela ressemblerait.

**Le soulbound.** L'adossement passe par `bindAgent`, qui exige d'être le détenteur de l'`agentId`, et
le mandat n'expose aucune fonction de transfert. C'est une propriété **par absence** : elle tient
parce que le contrat ne contient pas le code qui permettrait de la violer. Vérifiable dans l'ABI, mais
construite par nous.

**N4 est la mesure.** Son cursor, non modifié, laisse passer le tirage sur une lignée dont le mandat
est gelé, et il faut un `revoke` manuel pour l'arrêter. Ça, ce n'est pas une construction : c'est
exactement ce qu'il décrit lui-même quand il écrit *« a freeze doesn't revoke a node, someone calls
revoke »*. Notre refus est codé ; son comportement est observé.

### Une friction utile, à lui remonter telle quelle

Sa suite de conformité est pensée pour être portable, et elle l'est **presque**. Elle pilote bien à
travers le type d'interface, elle documente le point d'extension, et son commentaire dit exactement
quoi faire. Il manque un mot : `deploy()` n'est pas `virtual`, donc l'héritage ne peut pas la
re-cibler. Une implémentation tierce doit éditer son fichier pour se faire tester par lui — ce qui
est précisément ce qu'une suite portable cherche à éviter.

Nous n'avons pas touché son dépôt : la copie était jetable, hors de son arbre et du nôtre, et le
SHA-256 de son fichier est resté identique à la version committée pendant toute l'opération. Le
correctif tient en un mot-clé, et il lui appartient.

### L'écart entre la vue et la transaction — réglé de façon additive

En N3, `isPathActive` rend `true` alors que `draw` reverte. Le pont agit dans `draw`, pas dans la
vue de chemin : un consommateur qui lirait `isPathActive` pour décider s'il peut dépenser recevrait
une réponse démentie par la transaction suivante.

Deux façons de traiter ça. Faire rendre `false` à `isPathActive` dès que le mandat est gelé aurait
supprimé l'écart — mais en changeant la sémantique d'une vue que la Section 5 définit **par la
révocation seule**. Ce serait redéfinir un terme du profil depuis l'extérieur, et probablement casser
sa conformité.

Nous avons pris l'autre voie : **`isPathActive` garde son sens exact**, et une vue **additive**,
`isDrawable(rootId, nodeId)`, répond à l'autre question — *ce nœud peut-il tirer maintenant ?* Elle
rend `true` seulement si le chemin est actif **et** que le mandat adossé à l'agent l'est aussi.

N3b montre les deux côte à côte : mandat gelé, `isPathActive = true` (le chemin n'est pas révoqué,
c'est exact) et `isDrawable = false` (le tirage échouerait, c'est exact aussi). Après une révocation
explicite, les deux tombent à `false`. Sur un nœud sans mandat adossé, les deux rendent `true` — le
comportement de la référence.

Deux vues, deux sens, aucun tordu. Et la vérification qui compte : **ses neuf tests de conformité
passent toujours après l'ajout**, avec le même gaz, et `type(IAggregateBudget).interfaceId` reste
`0xc7cabe86` — parce que `isDrawable` vit hors de l'interface. Un ajout additif ne pouvait pas
casser la conformité *en théorie* ; la sortie le confirme *en pratique*.

---

## Limites

**Notre câblage est une proposition, pas la sienne.** `MandateAwareAggregateCursor` est notre
contrat. Rien n'indique que ce soit le design qu'il retiendrait.

**N3 est codé, pas découvert.** Répété ici parce que c'est la confusion la plus facile en lisant le
tableau des sorties.

**Sa source n'est ni modifiée ni copiée dans ce dépôt** : seule la signature d'interface est
redéclarée, et la copie jetable de sa suite vivait hors des deux arbres.

Une seule exécution par scénario. Contrat et test ont le même auteur de notre côté — sauf,
justement, les neuf tests de conformité, qui sont les siens.

**Conforme n'est pas sûr.** Passer une suite de conformité dit que les interfaces et les invariants
normatifs sont respectés. Ça ne dit rien de la non-contournabilité réelle, qui reste — selon ses
propres termes — une obligation du substrat.

## Reproduire

```bash
cd integration
git clone https://github.com/ERC8312/bounded-agent-actions.git
cd bounded-agent-actions && forge install foundry-rs/forge-std && forge test   # baseline
cd ..
forge test --match-contract Section5Test -vv
```

Pour rejouer sa suite de conformité contre notre implémentation, il faut ajouter `virtual` à
`deploy()` — à faire dans une copie hors de son dépôt, pas chez lui.

`integration/bounded-agent-actions/` est gitignoré. Notre compteur est
[`contracts/MandateAwareAggregateCursor.sol`](contracts/MandateAwareAggregateCursor.sol) et compile
seul, sans sa source.
