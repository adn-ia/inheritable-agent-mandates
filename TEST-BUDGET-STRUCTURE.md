# Budget structuré — la frontière calculable est déplaçable

babyblueviper1 trace une ligne (#68, fil ERC-8312) : *budget = calculable, jugement = pas
calculable*. Ce test ne la conteste pas — il la **déplace**. Une partie de ce qui ressemble à du
jugement (« est-ce que 490 est raisonnable ? ») redevient de l'arithmétique dès qu'on ajoute de la
structure qu'un plafond plat n'a pas.

Exécution **locale** sous Foundry (EVM en mémoire) — aucun gaz de testnet. Contrat non audité,
preuve de concept.

## Le mécanisme

`contracts/StructuredBudget.sol` ajoute trois dimensions au plafond plat :

- l'**engagé non débité** (`reserved`) — ce qui est promis mais pas encore payé ;
- les **poches par catégorie** (`catCap`) — une allocation par nature de dépense ;
- le **plafond par dépense unique** (`maxPerItem`).

Un tirage n'est admis que si les trois tiennent **en même temps**, et chaque refus **nomme** la
dimension qui a bloqué. Invariant de setup : `Σ catCap ≤ cap`.

---

## Sorties brutes

### S1 → S5 — le même 490, cinq configurations

| | Configuration | `draw("meal", 490)` |
|---|---|---|
| **S1** | cap 500, aucune structure | **ADMIS** — `totalRoom` restant : 10 |
| **S2** | cap 500, + un engagé de 200 | **REFUSÉ** — `TotalExceeded` (`totalRoom` : 300) |
| **S3** | cap 500 réparti : meal 50, other 450 | **REFUSÉ** — `CategoryExceeded` |
| **S4** | meal : `catCap` 500, `maxPerItem` 500 | **ADMIS** |
| **S5** | `maxPerItem` 500, `catCap` 1500, déjà 1100 dépensés | **REFUSÉ** — `CategoryExceeded` |

En S3, le total a de la place (500 libres) — c'est la poche qui bloque. En S5, le montant passe le
plafond par dépense — c'est ce qui reste de l'allocation qui bloque.

### I1 — sur-allocation au setup

```
cap 500, poches 300 + 300 = 600  →  REVERTE — OverAllocated
cap 500, poches 300 + 200 = 500  →  ABOUTIT, id 1
```

### I2 — héritage sur chaque dimension

Parent : cap 1000, `meal`(400, item 100), `other`(400, item 200).

```
enfant qui se resserre partout (500 ; 200/200 ; 50/100)  →  ABOUTIT, id 2
cap total élargi        (1200 > 1000)                     →  REVERTE — ChildCapWider
une poche élargie       (meal 600 > 400)                  →  REVERTE — ChildCategoryWider
plafond par dépense élargi (item 300 > 100)               →  REVERTE — ChildPerItemWider
plafond par dépense retiré (item 0 = illimité)            →  REVERTE — ChildPerItemWider
```

### I3 — conservation sous séquences aléatoires

```
testFuzz_I3_conservation(uint96[8], bool[8])  —  256 exécutions, 0 échec
   assertions : spent ≤ cap
                catSpent[meal]  ≤ catCap[meal]
                catSpent[other] ≤ catCap[other]
```

### I4 — dépendance à l'ordre

Budget identique dans les deux cas : cap 500, `meal`(catCap 400, item 300). Même multiset de
tirages : {300, 150, 90}.

```
ordre A (300, 150, 90)  →  admis : oui / non / oui     catSpent = 390
ordre B (90, 150, 300)  →  admis : oui / oui / non     catSpent = 240

nombre de tirages admis : 2 dans les deux cas
catSpent identique ?      false
```

### Contrôles

```
StructuredBudget compile seul : 4 037 octets (solc 0.8.36)
npm run check                 : 9 invariants, tous verts
forge test (5 suites)         : 26 tests, 0 échec
```

---

## Interprétation — écrite après coup, à partir des sorties ci-dessus

### Ce qui est illustré par construction — pas une découverte

**S1 → S5.** Les bascules du même 490 sont entraînées par des règles que nous avons écrites. Elles
ne démontrent rien : elles montrent la **forme** du mécanisme. Personne n'a découvert que 490 devient
refusé quand on ajoute une poche de 50 — on l'a codé.

Ce que la séquence rend visible, en revanche, mérite d'être dit : les cinq verdicts sont produits par
**de l'arithmétique pure**, sans aucun appel extérieur, sans oracle, sans jugement. « Est-ce que 490
est raisonnable ? » n'est pas une question à laquelle le contrat répond. Il répond à cinq questions
différentes — *reste-t-il de la place en tout ? dans cette poche ? sous ce plafond unitaire ?* — et
le mot « raisonnable » se dissout dans leur conjonction.

C'est en ce sens que la frontière se déplace : pas parce que la machine juge mieux, mais parce
qu'une partie de ce qu'on appelait jugement était de la structure absente.

### Ce qui est réellement établi — le code pouvait le rater

**Conservation (I3).** 256 exécutions du fuzzer, montants et catégories tirés au hasard, aucune
violation : le dépensé reste sous le plafond total et sous chaque plafond de poche. L'ajout de trois
dimensions et de l'engagé pouvait très bien ouvrir une fuite ; les exécutions disent que non.

**Sur-allocation rejetée (I1).** Distribuer 600 sous un plafond de 500 est refusé au moment du
setup — donc avant qu'aucune dépense n'ait lieu. La somme des poches ne peut pas dépasser le tout.

**Héritage étendu (I2).** `enfant ⊆ parent` tient sur les trois dimensions à la fois, et chaque refus
nomme celle qui a été élargie. Le cinquième cas mérite d'être relevé : un enfant qui **retire** son
plafond par dépense (`maxPerItem = 0`, c'est-à-dire illimité) est refusé. Supprimer une contrainte est
un élargissement — le code le traite comme tel.

**Dépendance à l'ordre (I4) — mesurée, pas présumée.** Le même multiset joué dans deux ordres donne
le **même nombre** de tirages admis (2), mais **pas les mêmes** et pas le même total : 390 contre 240.

Ce n'est ni un bug ni une qualité. C'est une propriété du mécanisme, qu'il faut connaître : le premier
arrivé consomme la place, donc l'ordre de présentation influence quelles dépenses passent. Un budget
plat a la même propriété ; la structure ne l'introduit pas, elle la rend seulement plus visible en
multipliant les endroits où une place peut manquer. Qui construit là-dessus doit savoir qu'un
verdict n'est pas une propriété de la dépense seule, mais de la dépense **et** de ce qui a été admis
avant elle.

---

## Limites

C'est la variante **« budget partitionné »** que le livre blanc met de côté au §3 — pas la baseline.
Elle est proposée ici comme démonstration, pas comme le design retenu.

**Ça ne fait toujours aucun jugement.** Le contrat ne décide pas si une dépense est légitime, utile
ou honnête. Il vérifie des enveloppes. Ce qu'il fait, c'est repousser la frontière : des questions
qui semblaient demander un humain deviennent calculables **à condition qu'on ait écrit la structure
à l'avance**. Le résidu — celui qu'aucune enveloppe ne capture — reste entier, et c'est exactement
là que se situe la composition avec une couche de jugement.

Une seule exécution par scénario, un seul contrat, même auteur pour le code et les tests de notre
côté. Le fuzzer est le seul juge qui n'ait pas été écrit pour ce cas précis.

**Conforme n'est pas sûr.** Passer ses propres invariants ne dit rien de la non-contournabilité : un
agent qui garde ses clés dépense à côté du contrat, quelles que soient les poches.

## Reproduire

```bash
cd integration
forge test --match-contract StructuredBudgetTest -vv
```

Contrat : [`contracts/StructuredBudget.sol`](contracts/StructuredBudget.sol).
