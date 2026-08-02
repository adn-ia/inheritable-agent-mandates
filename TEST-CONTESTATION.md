# Test interne — provenance déclarée (socle) vs. contestation par un tiers

Base Sepolia (chainId `84532`), testnet, contrats non audités, preuve de concept.
**Aucune valeur réelle en jeu.**

Ce document présente d'abord **les sorties brutes**, telles que les contrats les ont rendues.
L'interprétation vient ensuite, et ne porte que sur ces sorties.

## Contrats

| | Adresse | Rôle dans le test |
|---|---|---|
| `ProvenanceRegistry` | [`0x202f4eef39b57901061a7353595b72c61eacf5df`](https://sepolia.basescan.org/address/0x202f4eef39b57901061a7353595b72c61eacf5df) | **socle, non modifié** — déjà déployé, réutilisé tel quel |
| `ContestationRegistry` | [`0x236b71b033dc93634ce170d51dcd313bda19b233`](https://sepolia.basescan.org/address/0x236b71b033dc93634ce170d51dcd313bda19b233) | couche séparée, append-only |

Déploiement de la couche : tx [`0xb6f97198…f8a52c`](https://sepolia.basescan.org/tx/0xb6f97198f7265fdb60d224502c1fa2e692f183ec2c16cb7667fb49d984f8a52c).
`base()` lue sur le contrat déployé : `0x202F4EEf39B57901061a7353595b72c61EaCf5Df`.

L'isolation du socle est **structurelle** : la couche ne connaît la base que par une variable
`immutable`, et son interface ne déclare qu'une fonction, `parentsOf`, en `view`. Il n'existe aucun
chemin de code par lequel elle puisse écrire dans le socle.

Un contrat orphelin, [`0x2bd445e6…cb5b0`](https://sepolia.basescan.org/address/0x2bd445e621cc0d76c4a37bbd5bcc853affbcb5b0),
a été déployé lors d'une première tentative interrompue (le nœud RPC n'avait pas encore le code au
moment de la première lecture). Il est vide et inutilisé. Le test complet tourne sur
`0x236b71b0…9b233`.

## Montage

`runId 1785700345421`. Le socle étant write-once, chaque exécution sale ses `programKey`.

Le protocole pose une **vérité-terrain expérimentale** : *nous* savons que D dérive de A, et que la
déclaration de D omet A ; C est posé sans lien à A. Cette vérité-terrain est une convention du test,
**pas** une donnée que la chaîne peut vérifier.

| | programKey | parents déclarés | tx |
|---|---|---|---|
| A | `0x56b840ef…09bece` | (aucun) | [`0x9d72c3c2…569002`](https://sepolia.basescan.org/tx/0x9d72c3c21a2d99c45f9d6ebaaeed966d9a07f7e6727c8a043ade9a9dce569002) |
| B | `0x5d0ed84d…ffe71b` | A | [`0xf44457f0…1997a7`](https://sepolia.basescan.org/tx/0xf44457f095fdda61d813a3d2616481cc660c85cad6ff9ee96ba81d23c41997a7) |
| D | `0x0cf07eae…35f41f` | **(aucun — omet A)** | [`0xd036e960…b3e0bb`](https://sepolia.basescan.org/tx/0xd036e960b2c41f54511516071f9b0a8b43aaf7b3266e37f1d554c19fe5b3e0bb) |
| C | `0x9359386e…921fe5` | (aucun) | [`0x29ee0375…443bbe`](https://sepolia.basescan.org/tx/0x29ee037548088827f63d464d1658a1406702f4779ea931e4d0eaa254f6443bbe) |
| E | `0xfa89937c…f44a94` | B | [`0xd11958e9…cecce4`](https://sepolia.basescan.org/tx/0xd11958e90c064f53a5f0b1e5d4f81ae754130450e4d30739e53e9e8d72cecce4) |

E n'est pas dans le protocole d'origine : il a été ajouté pour disposer d'un ancêtre commun réel
situé au-delà d'une génération, ce que P5 demande sans en préciser la forme.

Auteur des enregistrements : `0x448Cc1c5689D9dFA2474265053A8FDF4bEb3B0Ae`.
Tiers assertant : `0xf0238A67A5C7deBa8E669bf54E6ec9178182951A` — adresse distincte.

---

## Sorties brutes

| | Lecture exécutée | Rendu |
|---|---|---|
| **P1** | `shareLineage(B, D, 2)` — socle seul | `false` |
| **P2** | `shareLineageWithContest(B, D, 2)` — après `assertParent(D, A)` par le tiers | `true` |
| **P3a** | `recordOf(D)` + `parentsOf(D)`, avant vs. après contestation | **identique** |
| **P3b** | `register(D, [A], …)` de nouveau sur le socle | simulation : `programKey already registered` · tx **`reverted`** |
| **P4** | `shareLineageWithContest(B, C, 2)` — après `assertParent(C, A)` par le tiers | `true` |
| **P5** | `shareLineageWithContest(E, D, maxDepth)` — `maxDepth` = 1 / 2 / 3 | `false` / `true` / `true` |

Détail de P3a, octet à octet :

```
avant : recordOf(D)  = [0xa829821f…1bebd8, 0x448Cc1c5…3B0Ae, 2, true]   parentsOf(D) = []
après : recordOf(D)  = [0xa829821f…1bebd8, 0x448Cc1c5…3B0Ae, 2, true]   parentsOf(D) = []
```

Assertions et lectures complémentaires :

```
assertParent(D, A)   tx 0xa6e15131…8732b8   asserter 0xf0238A67…82951A   index 0
assertParent(C, A)   tx 0xd5a3464c…3f5da6   asserter 0xf0238A67…82951A   index 1
P3b (revert)         tx 0x6214f2c6…f95ae9

assertedParentsOf(D) = A          parentsOf(D) sur le socle = (vide)
assertedParentsOf(C) = A          parentsOf(C) sur le socle = (vide)
assertionCount()     = 2
```

---

## Interprétation — écrite après coup, à partir des sorties ci-dessus

### Ce que le socle seul a fait

En P1, la lecture rend `false`. La lignée que la vérité-terrain du test dit réelle, mais que D n'a
pas déclarée, n'apparaît pas. Le socle rend ce qui a été déclaré ; l'omission reste une omission.

### Ce que la couche de contestation a fait

En P2, après une arête assertée par un tiers, la lecture augmentée rend `true` : le lien omis
apparaît. Et P3a / P3b montrent que le socle n'a pas bougé pendant ce temps. Autrement dit, sur ce
graphe, **la contestation a récupéré une lignée omise sans muter la base**.

En P4, après une arête assertée sur C — que le test pose sans lien à A — la lecture rend **également
`true`**.

**Les deux lectures rendent la même chose.** Le contrat ne distingue pas une assertion que le test
tient pour vraie (D→A) d'une assertion qu'il tient pour fausse (C→A) : il traverse ce qui a été
asserté, sans pouvoir vérifier quoi que ce soit. La différence entre P2 et P4 n'existe que dans la
vérité-terrain que *nous* avons posée, laquelle n'est nulle part sur la chaîne.

Ce résultat est **observé, pas prédit** : aucune valeur attendue n'était écrite dans le contrat, le
script ou les logs. P4 aurait pu rendre `false` — c'est le contrat qui a décidé.

### Sur le vocabulaire sensibilité / spécificité

Les sorties le permettent, à condition de le rapporter à la vérité-terrain **du test** et non à la
réalité : par rapport à la convention posée, le socle seul n'a pas fait apparaître un lien tenu pour
réel (P1), et la couche de contestation a fait apparaître à la fois ce lien (P2) et un lien tenu pour
inexistant (P4).

Lu ainsi, **la contestation ouverte rachète de la sensibilité au prix de la spécificité.** Gagner
l'un et s'exposer à l'autre relèvent ici du **même mécanisme**, dans la même exécution — pas de deux
réglages qu'on pourrait doser séparément.

### Sur la question « laquelle des deux options est meilleure »

**Ce test ne dit pas « B gagne ».** Ce qu'il montre est un **déplacement du curseur** : le socle seul
échoue par faux négatif (la lignée omise reste invisible) ; la couche ouverte corrige ce faux négatif
et ouvre la porte au faux positif. Le défaut change de nature, il ne disparaît pas.

Quel réglage est préférable dépend du coût relatif d'une omission et d'une assertion infondée —
grandeur qui **n'a pas été mesurée ici**. La question que ces sorties laissent ouverte est celle
d'une contestation **pondérée ou authentifiée** (caution, réputation de l'assertant, seuil de
concordance) : une **autre conception**, non implémentée et non testée dans ce document.

### Ce que le test établit sur l'architecture

P3a et P3b sont les deux résultats qui portent une garantie plutôt qu'une observation. Le socle est
**identique octet à octet** après contestation, et la tentative de le réécrire **reverte**. Comme la
base ne peut pas bouger, tout effet observé en P2 et P4 est imputable à une assertion précise —
`index 0` et `index 1`, avec leur auteur et leur transaction. On voit l'effet **et** la cause.

C'est le seul apport que ce test démontre plutôt qu'il ne l'illustre : non pas que la contestation
répare quoi que ce soit, mais que ses effets restent **traçables** parce que le témoin est immobile.

### Sur la borne de profondeur

P5 rend `false` à `maxDepth = 1`, puis `true` à 2 et 3. Sur ce graphe, A se trouve à deux sauts de E
(E déclare B, B déclare A), et l'arête assertée place A à un saut de D. La borne est donc réellement
exercée : à profondeur 1 la traversée s'arrête avant l'ancêtre commun et le dit, à profondeur 2 elle
l'atteint. **Elle ne remonte pas au-delà de ce qu'on lui autorise.**

---

## Limites

La contestation testée ici est **ouverte et non gardée** : n'importe quelle adresse peut asserter
n'importe quelle arête, au seul coût du gaz. Toute variante — pondérée, cautionnée, authentifiée,
révocable, avec réputation de l'assertant — serait une **autre conception**, et n'a **pas** été
testée ici. Les sorties ci-dessus ne disent rien de ces variantes.

En particulier, **P4 ne démontre que le comportement de la contestation ouverte.** Il ne dit rien de
ce que rendrait une contestation gardée, et ne doit pas être lu comme une propriété de la
contestation en général.

Une seule exécution, un seul graphe, cinq nœuds. Rien n'autorise à généraliser au-delà.

La provenance reste **déclarée**, dans les deux options. Le socle garantit qu'une déclaration est
permanente, signée et attribuable — pas qu'elle est vraie. La couche de contestation ajoute des
assertions elles aussi permanentes, signées et attribuables — et pas davantage vérifiées. Aucun des
deux contrats ne peut établir une lignée réelle ; ils enregistrent qui a dit quoi, et quand.

Enfin, contrats et test ont le même auteur, dans la même session. Les sorties sont brutes et
reproductibles on-chain, ce qui permet à quiconque de les recalculer sans nous faire confiance —
mais une relecture par quelqu'un d'une autre lignée vaudrait plus que ce document.

## Reproduire

```bash
npm install
npx tsx scripts/compile.ts ContestationRegistry
npx tsx scripts/test-contestation.ts        # déploie la couche, exécute P1→P5
```

Le socle n'est pas redéployé : le script lit son adresse dans `build/deployment-provenance.json`.
Chaque exécution sale ses `programKey` avec un `RUN_ID` (surchargeable) — sans quoi tous les
`register` reverteraient, le socle étant write-once.

Sorties complètes de cette exécution : `build/test-contestation-results.json`.
