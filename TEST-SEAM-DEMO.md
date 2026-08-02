# Démonstrateur — un compteur ERC-8312 qui consulte le mandat avant d'avancer

Suite du [test de couture](TEST-SEAM.md). Celui-ci avait montré le trou : après un gel côté mandat,
le metering d'ERC-8312 continue d'autoriser la dépense — *« it meters but does not enforce »*.

Ici on construit **notre propre** compteur, `MandateAwareCursor`, qui ajoute le crochet manquant.
Intégration locale sous Foundry, aucun déploiement testnet. Non audité, preuve de concept, aucune
valeur réelle en jeu.

> **Sa source n'est ni modifiée ni copiée.** Seule la **signature** de son interface
> `IBoundedAgentAction` est redéclarée chez nous — ce qu'un standard expose par définition. Son
> implémentation n'est jamais reprise, et son dépôt reste hors du nôtre.

---

## Sorties brutes

Montage : mandat parent `agentId 1` (plafond 1 ETH), enfant `agentId 2` (plafond 0,4 ETH,
`child ⊆ parent` imposé par notre contrat).

### N1 — comptage normal, avant tout gel

```
capabilityRoot = keccak(cap, actif, registre de mandats, agentId)
   0x04c37858907c42f240ae29cafe0208292f0cb3f74753aca24e5cd68021ce9bd3

registerEnvelope        : aboutit
   agentIdOf(enveloppe) : 2
   isActive()           : true

advanceCursor(0.05 ETH) : aboutit
   spent                : 0.05 ETH
   remaining            : 0.35 ETH
```

### N2 — conformité à son interface gelée

```
notre compteur, supportsInterface(0x3985961d) : true
                supportsInterface(0x01ffc9a7) : true
                supportsInterface(0xffffffff) : false

son registre,   supportsInterface(0x3985961d) : true
```

Contrôle séparé, l'identifiant **calculé** depuis notre redéclaration :

```
type(IBoundedAgentAction).interfaceId  →  0x3985961d
```

### N3 — le chaperon

```
freeze(parent)
mandate.isActive(enfant)          : false
notre cursor, isActive(enveloppe) : false
advanceCursor après le gel        : REVERTE — MandateInactive(agentId)
   spent                          : 0.05 ETH   (inchangé)
```

### N4 — contraste, son registre non modifié, même gel

```
son registerEnvelope              : aboutit
son isActive()                    : true
son advanceCursor, mandat gelé    : ABOUTIT
   son spent                      : 0.05 ETH

(mandate.isActive(enfant) vaut toujours false)
```

### N5 — plafond hérité, notre compteur

```
plafond du mandat pour l'enfant   : 0.4 ETH
plafond demandé pour l'enveloppe  : 100 ETH

registerEnvelope(cap = 100 ETH)   : REVERTE — CapExceedsMandate(requested, mandateCap)
```

### N6 — plafond hérité, son registre non modifié

```
registerEnvelope(cap = 100 ETH)   : ABOUTIT
   son bound cap                  : 100 ETH
   son remaining                  : 100 ETH
```

### Non-régression, après l'ajout du contrôle de plafond

```
supportsInterface(0x3985961d)     : true
comptage normal — spent           : 0.05 ETH
comptage normal — remaining       : 0.35 ETH
```

N1 à N4 rendent exactement les mêmes valeurs qu'avant l'ajout.

### Contrôles

```
MandateAwareCursor compile SEUL, sans sa source  : 4 793 octets (solc 0.8.36)
   dont le crochet de plafond                    : +310 octets (4 483 → 4 793)
suites d'intégration (seam + démo)               : 3 tests, 0 échec
son src/ et test/                                : intacts, aucun octet changé
son dépôt dans notre index                       : aucun fichier
```

---

## Interprétation — écrite après coup, à partir des sorties ci-dessus

### Ce qui est illustré par construction — pas une découverte

**N3.** Nous avons écrit nous-mêmes, dans notre contrat, la ligne qui refuse :

```solidity
if (!mandate.isActive(r.agentId)) revert MandateInactive(r.agentId);
```

Le refus observé est donc **entraîné par le montage**. Il montre à quoi ressemblerait la couture
soudée ; il ne démontre rien qu'on n'ait décidé. Toute lecture du type « on a vérifié que le gel
arrête la dépense » serait fausse : on a codé que le gel arrête la dépense, puis on l'a exécuté.

Le contraste avec N4 garde néanmoins sa valeur, à condition de nommer l'asymétrie : **notre refus
est codé, le sien est observé.** Son registre, non modifié, laisse passer la dépense sur une lignée
que le mandat déclare gelée — ça, c'est une mesure, pas une construction.

**N5 relève exactement du même statut.** Le refus d'une enveloppe à 100 ETH pour un enfant plafonné
à 0,4 vient d'une ligne que nous avons écrite :

```solidity
(uint256 mandateCap,,,) = mandate.mandateOf(agentId);
if (cap > mandateCap) revert CapExceedsMandate(cap, mandateCap);
```

Là encore, rien n'est découvert : nous décidons de refuser, puis nous l'exécutons. **N6 est le fait.**
Son registre, non modifié, accepte pour ce même enfant une enveloppe de 100 ETH et lui ouvre
immédiatement 100 ETH de réserve. C'est le trou (b) du seam test, mesuré une seconde fois et remis
à côté du remède.

### Ce qui est réellement établi — le code pouvait le rater

**N1 — le comptage normal est préservé.** Hors gel, notre compteur se comporte comme le sien :
0,05 dépensé sur un plafond de 0,4, il reste 0,35. Ajouter un crochet d'enforcement aurait pu fausser
la comptabilité ; les chiffres disent que non.

**N2 — le chaperon reste conforme.** `supportsInterface(0x3985961d)` rend `true`, et surtout cet
identifiant **n'est pas écrit en dur** : le contrat retourne `type(IBoundedAgentAction).interfaceId`,
calculé depuis notre propre redéclaration. Un paramètre de travers dans cette redéclaration, et la
valeur calculée aurait divergé de la sienne — N2 aurait rendu `false`. La réponse `false` sur
`0xffffffff` confirme au passage le comportement ERC-165 attendu.

Ces deux points forment le résultat qui compte : **le chaperon peut être ajouté sans casser le
compteur.** Ce n'était pas acquis d'avance.

**Et il tient au second ajout.** Après le contrôle de plafond, `supportsInterface(0x3985961d)` rend
toujours `true`, et le comptage normal rend toujours 0,05 dépensé pour 0,35 restant — les mêmes
chiffres qu'avant, au wei près. Le coût est de **310 octets** de bytecode (4 483 → 4 793). Un second
crochet pouvait très bien casser ce que le premier avait préservé ; les sorties disent que non.

### Le crochet, et ce qu'il rend visible

Le seam test avait relevé un fait structurel : sa struct `Envelope` ne porte aucun champ d'identité
d'agent, et sous le profil Budget Substrate le `capabilityRoot` est figé à `keccak(cap, asset)` — il
n'existe donc **aucun endroit où accrocher un mandat**.

Notre `capabilityRoot` engage en plus l'adresse du registre de mandats et l'`agentId`, et
l'enveloppe conserve celui-ci : `agentIdOf` rend `2`, l'identifiant de l'enfant. C'est le champ
absent de sa structure.

**Ce même crochet ferme les deux manques du seam test, et il n'en faut pas deux.** Le **gel**
(point c) devient consultable parce que le compteur sait de quel agent il mesure la dépense : c'est
`mandate.isActive(agentId)` en N3. Le **plafond hérité** (point b) devient vérifiable par la même
lecture : c'est `mandate.mandateOf(agentId)` en N5. Deux manques, deux appels, **un seul `agentId`
retenu dans l'enveloppe**.

C'est aussi ce qui montre pourquoi le standard ne peut pas faire ces contrôles lui-même. Ce n'est
pas un oubli de conception : une enveloppe qui ne sait pas de quel agent elle porte l'autorité n'a
aucun moyen d'aller demander au mandat s'il est gelé, ni quel plafond il porte. Le crochet
d'identité n'est pas une commodité — c'est ce sans quoi la question ne peut même pas être posée.

---

## Limites

**Notre câblage est une proposition, pas la sienne.** `MandateAwareCursor` est notre contrat, écrit
pour montrer une forme. Rien n'indique que ce soit le design qu'il retiendrait, ni que ce soit le
bon.

**N3 est codé, pas découvert.** Répété ici parce que c'est la confusion la plus facile à faire en
lisant le tableau des sorties.

**Sa source n'est ni modifiée ni copiée** : seule la signature d'interface est redéclarée, et son
dépôt reste cloné à part, hors de celui-ci.

Une seule exécution, un seul scénario par point. Contrat et test ont le même auteur, de notre côté —
la seule chose qui limite ce biais est que N4 s'exécute contre **son** code, pas le nôtre.

Enfin, un compteur conforme à une interface n'est pas un système sûr. Ce document rapporte qu'un
crochet d'identité peut être ajouté sans rompre la conformité ni le comptage. Il ne dit rien de la
non-contournabilité réelle, qui reste — selon ses propres termes — une obligation du substrat.

## Reproduire

```bash
cd integration
git clone https://github.com/ERC8312/bounded-agent-actions.git
cd bounded-agent-actions && forge install foundry-rs/forge-std && cd ..
forge test --match-contract SeamDemoTest -vv
```

`integration/bounded-agent-actions/` est gitignoré : sa source ne rentre pas dans ce dépôt. Notre
compteur est [`contracts/MandateAwareCursor.sol`](contracts/MandateAwareCursor.sol) et compile seul,
sans elle.
