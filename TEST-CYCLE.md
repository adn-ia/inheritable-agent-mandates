# Test on-chain — cycle d'arêtes assertées

Base Sepolia (chainId `84532`), testnet, contrats non audités, preuve de concept.
**Aucune valeur réelle en jeu.**

Question posée : que fait la traversée de `shareLineageWithContest` face à un **cycle** dans les
arêtes assertées ? Le cycle a été créé, les lectures lancées, les issues rapportées telles quelles.
Aucune valeur attendue n'a été écrite dans le contrat, le script ou les logs.

Ce document présente **les sorties brutes** d'abord. L'interprétation vient ensuite, et ne porte que
sur elles.

## Contrats — réutilisés, aucun déploiement

| | Adresse |
|---|---|
| `ProvenanceRegistry` (socle) | [`0x202f4eef39b57901061a7353595b72c61eacf5df`](https://sepolia.basescan.org/address/0x202f4eef39b57901061a7353595b72c61eacf5df) |
| `ContestationRegistry` | [`0x236b71b033dc93634ce170d51dcd313bda19b233`](https://sepolia.basescan.org/address/0x236b71b033dc93634ce170d51dcd313bda19b233) |

`runId 1785703547116`. Le socle étant write-once, chaque exécution sale ses `programKey`.
Compte : `0x448Cc1c5689D9dFA2474265053A8FDF4bEb3B0Ae`.

---

## Sorties brutes

### Nœuds enregistrés dans le socle

Quatre `register`, parents `[]`, tous `success`, 73 741 de gaz chacun.

| | programKey | tx |
|---|---|---|
| P | `0x62ac0125…bd80e2` | [`0xa4e64f43…8acc760`](https://sepolia.basescan.org/tx/0xa4e64f432c4c40915d6ced9217e3bdb28384b912f14230df4807d33498acc760) |
| Q | `0x0c0c554c…e6f565` | [`0xd410b9d2…3d0dbce`](https://sepolia.basescan.org/tx/0xd410b9d2d2186ddbbc94e567f62820b76afcd431da241dea87f6717233d0dbce) |
| Z | `0x4b37d94e…8186f1` | [`0xf824276f…ea5189`](https://sepolia.basescan.org/tx/0xf824276fdf6bc339d538ca6677ec30fe14ce578792f9edf4521a95f5eeea5189) |
| P2 | `0x6f9ba0f3…c3c1f8` | [`0xf3323b3e…c8c3d0`](https://sepolia.basescan.org/tx/0xf3323b3e37dfd779bcbc7f50ad8be68fe89b74f01fb2cbc0601ec3b1eac8c3d0) |

### Le cycle — créé uniquement dans la contestation

| Assertion | tx | issue | gaz | asserter | index |
|---|---|---|---|---|---|
| `assertParent(P, Z)` | [`0xafb39ac5…5eb9f7`](https://sepolia.basescan.org/tx/0xafb39ac5d8cad3cafa5779cb60024f9c852446ac9c05fab48a9638103d5eb9f7) | `success` | 140 709 | `0x448Cc1c5…3B0Ae` | 2 |
| `assertParent(Z, P)` | [`0xcd8260e7…a42b83`](https://sepolia.basescan.org/tx/0xcd8260e7a0e7e2372accb1bf38c72ad4f8d0ae9cd0e76788da295c7dbca42b83) | `success` | 140 709 | `0x448Cc1c5…3B0Ae` | 3 |

Remonter l'ascendance de P mène à Z, et celle de Z revient à P.

### T1 / T2 — `shareLineageWithContest(P, Q, maxDepth)`

| `maxDepth` | issue | gaz |
|---|---|---|
| 1 | `false` | 43 861 |
| 2 | `false` | 53 257 |
| 3 | `false` | 53 257 |
| 8 | `false` | 53 257 |
| 16 | `false` | 53 257 |

### T3 — auto-boucle

```
assertParent(P2, P2)
   issue simulation : reverted — "self parent"
   tx 0x1f55ae04…f47e38b7 → reverted   gaz 23 720

shareLineageWithContest(P2, Q, 3)
   issue : false
   gaz   : 40 407
```

### Lectures complémentaires

```
assertedParentsOf(P)  = Z          assertionCount()  = 4
assertedParentsOf(Z)  = P
assertedParentsOf(P2) = (vide)
parentsOf(P) sur le socle = (vide)
parentsOf(Z) sur le socle = (vide)
```

---

## Interprétation — écrite après coup, à partir des sorties ci-dessus

### T1 / T2 — ce que la traversée a fait face au 2-cycle

À toutes les profondeurs demandées — 1, 2, 3, 8, 16 — la lecture **a rendu une valeur** (`false`).
Aucun revert, aucun dépassement de gaz, aucun échec RPC.

Le gaz vaut 43 861 à profondeur 1, puis **53 257 à partir de la profondeur 2 et jusqu'à 16** —
identique à trois profondeurs différentes. Une traversée qui re-parcourrait la boucle à chaque
génération autorisée verrait son coût croître avec `maxDepth` ; ce n'est pas ce que les chiffres
montrent. Sur ce graphe, **la traversée est bornée : le cycle ne la fait ni diverger, ni coûter
davantage au-delà de la deuxième génération.** Rien dans ces sorties ne suggère qu'un cycle assertté
puisse servir à rendre la lecture impraticable.

Ce résultat a été obtenu en lançant le test, pas en lisant le code. L'explication tient à deux
mécanismes déjà présents dans `ContestationRegistry` — la liste des nœuds déjà visités, qui empêche
de repasser sur P et Z, et la borne `MAX_NODES = 64` — mais ce sont des explications *a posteriori*
d'un comportement observé, pas des valeurs qui auraient été attendues.

### T3 — ce que le test n'a pas éprouvé

`assertParent(P2, P2)` a été **refusé à l'écriture**, avec la raison exacte `self parent`. Ce refus
vient d'un `require` déjà présent dans le contrat, antérieur à ce test.

Conséquence à énoncer franchement : **T3 n'a pas éprouvé la traversée d'une auto-boucle**, puisque
aucune arête `P2→P2` n'a jamais existé. La lecture qui suit s'exécute sur un nœud sans arête assertée
— elle ne dit rien du cas visé. **Le seul cycle réellement traversé dans ce test est le 2-cycle
de T1.**

Cela met en évidence une asymétrie dans le contrat : le cycle de longueur 1 est **bloqué à
l'écriture**, tandis que les cycles plus longs sont **acceptés à l'écriture et encaissés à la
lecture**. Les deux chemins mènent à un résultat exploitable, mais par deux mécanismes différents, à
deux endroits différents.

### Une conséquence non mesurée ici

`MAX_NODES = 64` borne le coût de la traversée — c'est ce que T1/T2 montrent. La même borne plafonne
la couverture : sur un graphe dont l'ascendance combinée dépasserait 64 nœuds, la traversée
s'arrêterait avant d'avoir tout vu, et pourrait rendre `false` là où un ancêtre commun existe plus
loin.

**Ce cas n'a pas été testé dans cette exécution.** Le graphe ici compte quatre nœuds. C'est un test
à faire, pas un résultat de ce run — et il n'est mentionné que parce que la borne qui produit le bon
comportement en T1 est la même que celle qui produirait ce comportement-là.

### Ce que la borne fait à la question elle-même

Dans ce test, toutes les profondeurs rendent `false` : le contraste n'y est pas visible. Il l'est
dans l'exécution précédente ([`TEST-CONTESTATION.md`](TEST-CONTESTATION.md), P5), où la **même
paire** est rendue `false` à `maxDepth = 1` et `true` à `maxDepth = 2`. Aucune donnée n'avait changé
entre les deux appels ; seule la profondeur demandée différait.

Ce que la lecture rend n'est donc pas une propriété de la paire, mais une propriété de la paire **à
une profondeur donnée**. La conséquence dépasse le coût en gaz : une réponse « ces deux-là sont
indépendants » n'a de sens que rapportée à l'horizon sur lequel on a regardé, et cet horizon est un
paramètre de la question, pas une caractéristique du monde. Une borne courte ne rend pas seulement
la traversée moins chère — elle rend la question plus facile, et la réponse plus rassurante.

---

## Limites

Une seule exécution, un seul graphe, quatre nœuds, un cycle de longueur 2. Rien n'autorise à
généraliser au-delà.

La contestation est **ouverte et non gardée** : n'importe quelle adresse peut asserter n'importe
quelle arête, au seul coût du gaz. Toute variante pondérée, cautionnée ou authentifiée serait une
autre conception, non testée ici.

La vérité-terrain — « P et Q sont indépendants », « le cycle est artificiel » — est une convention
**hors chaîne**, posée par le protocole de test. Aucun contrat ne peut la vérifier.

Le socle n'a pas été touché : `parentsOf(P)` et `parentsOf(Z)` y restent vides, le cycle ne vit que
dans la couche de contestation.

Contrat et test ont le même auteur, dans la même session. Les issues sont brutes et les lectures
reproductibles on-chain par quiconque, sans avoir à nous faire confiance — mais une relecture par
quelqu'un d'une autre lignée vaudrait plus que ce document.

## Reproduire

```bash
npm install
npx tsx scripts/test-cycle.ts
```

Aucun déploiement : le script utilise les deux contrats déjà en place. Chaque exécution sale ses
`programKey` avec un `RUN_ID` (surchargeable) — sans quoi les `register` reverteraient, le socle
étant write-once.

Sorties complètes de cette exécution : `build/test-cycle-results.json`.
