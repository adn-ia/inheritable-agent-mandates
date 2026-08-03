# La couture — le mécanisme d'exception

Nous avons dit publiquement : *« la non-contournabilité survit à l'exception — la machine refuse
quand même, un humain nommé relève le plafond, sur le registre. »* Ce test transforme cette phrase en
preuve, ou la casse.

La couture, c'est le point exact où le mandat — calcul, imposé **avant** — rencontre le jugement
humain — l'incalculable, comptabilisé **après**. Le danger est qu'une porte d'exception perce un trou
dans la laisse. C'est ça qui est testé.

Exécution **locale** sous Foundry (EVM en mémoire) — aucun gaz de testnet. Contrat non audité,
preuve de concept.

## Le mécanisme

`contracts/MandateWithException.sol` :

- un plafond dur qui refuse ;
- `requestException` — le mandat **expose proprement le résidu** dans un event, sans appeler aucun
  oracle et sans rien décider ;
- un rôle **gardien**, une liste d'adresses nommées, **distinct de l'agent** ;
- une exception porte `{ montant, catégorie, expiration, statedBet, preActionRead, approbateurs }`,
  est bornée, à usage unique, et append-only ;
- au-delà d'un seuil, il faut **N approbateurs distincts**.

Le `statedBet` est le résultat visé, déclaré avant. Le `preActionRead` est une lecture neutre datée
**avant** que le résultat soit connu.

---

## Sorties brutes

### C1 — refus propre, puis exposition du résidu

```
déjà dépensé : 900 sur un cap de 1000
draw(300)                   →  REVERTE — CapExceeded
requestException(300)       →  1 event émis
   contexte — montant demandé : 300
   contexte — place restante  : 100
```

### C2 — un gardien accorde, le tirage passe une fois

```
proposeException(150, expiration +1j, statedBet, preActionRead)  →  exception id 1
drawWithException(150)      →  ABOUTIT
   exception consommée      :  true
   plafond effectif         :  1150   (1000 nominal + 150 accordés)

second usage de la même exception  →  REVERTE — ExceptionConsumed
```

### C3 — l'agent ne peut pas s'auto-autoriser

```
l'agent, non gardien                                   →  REVERTE — NotGuardian
un budget dont l'agent EST aussi gardien                →  REVERTE — AgentCannotGrant
un tiers non gardien                                    →  REVERTE — NotGuardian
un gardien qui approuve sur SON propre budget           →  REVERTE — AgentCannotGrant
```

### C4 — bornes de l'exception

```
accorder 600 (> plafond d'exception 500)   →  REVERTE — ExceptionTooLarge
accorder sans pari déclaré                 →  REVERTE — MissingStatedBet
accorder sans lecture-avant                →  REVERTE — MissingPreActionRead
tirer 200 sur une exception de 150         →  REVERTE — AmountAboveException
utiliser l'exception dans une autre catégorie → REVERTE — WrongCategory
l'utiliser après expiration                →  REVERTE — ExceptionExpired
```

### C5 — seuil N-sur-M

Seuil : 200. Approbations requises au-delà : 2.

```
exception de 400 proposée par un gardien   →  approbateurs : 1
requiredApprovals(400)                     →  2

tirage avec 1 approbateur                  →  REVERTE — NotEnoughApprovers
après l'approbation d'un second gardien    →  approbateurs : 2
tirage                                     →  ABOUTIT

le même gardien tente d'approuver deux fois →  REVERTE — AlreadyApproved
```

### C6 — l'héritage tient

```
parent cap 1000, enfant cap 400
exception de 300 accordée au PARENT (id 1)

plafond effectif du parent   :  1000     (l'exception n'est pas encore consommée)
plafond effectif de l'enfant :  400

l'enfant utilise l'exception du parent  →  REVERTE — ExceptionNotForThisBudget
l'enfant tire 500 (> son cap 400)       →  REVERTE — CapExceeded
spawn d'un enfant à 1200 (> 1000)       →  REVERTE — ChildCapWider
```

### C7 — intégrité du registre

```
exception id 1 : budgetId 1 · montant 400 · expiration 86401 · consommée false
                 approbateurs 2
   pari déclaré non vide            : true
   lecture-avant non vide           : true
   pari == valeur posée au grant    : true
   lecture == valeur posée au grant : true
   approbateur 0 : 0xb69c7E5E22493891C12a8e1B472bFAbF84c9b71C
   approbateur 1 : 0xD85A9AFEe3E8efb42CBDF79cDF0fa9f3EBE50e55

une seconde proposition crée une NOUVELLE entrée :
   id de la première : 1     montant, inchangé : 400
   id de la seconde  : 2
```

Backfill — vérifié sur l'ABI compilée :

```
fonctions qui écrivent : approveException, createBudget, draw, drawWithException,
                         proposeException, requestException, spawn
setter / modification / suppression sur la trace : AUCUNE
```

### Conservation

```
testFuzz_conservation(uint16[6], uint8[6])  —  256 exécutions, 0 échec
   assertion : spent ≤ cap + Σ(exceptions accordées et consommées)
```

### Contrôles

```
MandateWithException compile seul : 5 096 octets (solc 0.8.36)
npm run check                     : 9 invariants, tous verts
forge test (5 suites)             : 26 tests, 0 échec
```

---

## Interprétation — écrite après coup, à partir des sorties ci-dessus

### Ce qui est illustré par construction — pas une découverte

**C1 et C2.** Qu'un gardien puisse accorder une exception et que le tirage refusé passe ensuite, que
le pari et la lecture-avant soient enregistrés — ce sont des règles que nous avons écrites. Elles
montrent la **forme** de la couture, pas un résultat.

Ce que C1 rend visible mérite quand même d'être nommé : le mandat **ne décide rien** et **ne
consulte rien**. Il refuse, puis il publie le contexte du refus — montant demandé, place restante.
Aucun oracle, aucune règle automatique qui se substituerait au jugement. Le résidu est exposé, pas
résolu.

### Ce qui est réellement établi — le code pouvait le rater

**C3 — l'agent ne s'auto-autorise pas.** C'est le cœur de la non-contournabilité, et les quatre
chemins testés sont refusés, y compris les deux qui ne sont pas évidents : un agent qui est **par
ailleurs gardien** ne peut pas s'accorder d'exception sur son propre budget, et un gardien ne peut
pas non plus approuver une exception portant sur un budget dont il est l'agent. Le rôle ne suffit
pas — c'est le conflit d'intérêt qui est bloqué, pas seulement l'absence de titre.

**C4 — l'exception est bornée sur six axes.** Montant plafonné, usage unique, catégorie scellée,
expiration effective, et surtout : **impossible d'accorder sans trace**. Un gardien qui voudrait
signer sans déclarer son pari, ou sans poser de lecture-avant, ne le peut pas. La traçabilité n'est
pas une bonne pratique optionnelle, c'est une condition de validité.

**C5 — le seuil tient.** Une grosse exception exige deux gardiens distincts ; avec un seul, le
tirage est refusé. Un gardien ne peut pas jouer deux fois pour atteindre le compte.

**C6 — l'héritage n'est pas percé.** Une exception accordée au parent n'apparaît pas dans le plafond
effectif de l'enfant, et l'enfant ne peut pas la réclamer. La porte d'exception ne crée pas de
chemin latéral vers les enfants.

**C7 — le registre est append-only, vérifié sur l'ABI.** Chaque exception porte ses approbateurs
nommés, son pari et sa lecture-avant, tels que posés au moment du grant. Aucune fonction du contrat
ne permet de les modifier ou de les effacer — ce n'est pas une promesse dans un commentaire, c'est
constatable dans les sept fonctions qui écrivent. Une seconde proposition crée une **nouvelle**
entrée et laisse la première intacte.

**Conservation.** 256 exécutions avec demandes et approbations aléatoires : le dépensé reste sous
`cap + Σ(exceptions accordées)`. Des demandes répétées ne somment jamais au-delà de ce que des
gardiens ont explicitement accordé. C'est la propriété qui répond directement à la crainte : la
porte ne fuit pas.

### La réponse à la question posée

La non-contournabilité **survit à l'exception**, dans ce montage : la machine refuse toujours, le
plafond n'est jamais relevé par l'agent, et ce qui est ajouté l'est par des humains nommés, dans des
bornes, avec une trace qu'on ne peut pas écrire après coup.

Ce que ce test ne dit pas : que le mécanisme est **sûr**. Voir ci-dessous.

---

## Limites

**Le chemin d'exception est une proposition, pas une baseline.** Rien n'oblige un mandat à en avoir
un, et un mandat sans exception est plus simple à raisonner.

**Borné n'est pas sûr.** Un gardien compromis conserve un pouvoir réel : il peut accorder jusqu'au
plafond d'exception, dans les catégories qu'il veut, aussi souvent qu'il propose. Ce pouvoir est
borné et tracé — il n'est pas nul. C'est tout le sens de « peu de mains, mais nommées et tracées » :
on ne supprime pas le risque, on le réduit et on le rend attribuable.

**La lecture-avant ne vaut que l'indépendance de son lecteur.** `preActionRead` est un `bytes32` : le
contrat garantit qu'il a été posé avant, pas qu'il est honnête. Une lecture produite par un lecteur
corrélé au gardien — même équipe, même modèle, même conversation — n'est pas une lecture
indépendante. C'est exactement la question de lignée et de `rho`, et c'est pourquoi la couture
s'appuie en dernier ressort sur le brin de provenance : sans moyen de dire si deux lecteurs partagent
un ancêtre, « une lecture indépendante » n'est qu'une affirmation.

Une seule exécution par scénario, même auteur pour le contrat et les tests de notre côté. Le fuzzer
est le seul juge qui n'ait pas été écrit pour ces cas précis.

## Reproduire

```bash
cd integration
forge test --match-contract CoutureExceptionTest -vv
```

Contrat : [`contracts/MandateWithException.sol`](contracts/MandateWithException.sol).
