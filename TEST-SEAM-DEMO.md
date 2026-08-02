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

### Contrôles

```
MandateAwareCursor compile SEUL, sans sa source  : 4 483 octets (solc 0.8.36)
suites d'intégration (seam + démo)               : 2 tests, 0 échec
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

### Le crochet, et ce qu'il rend visible

Le seam test avait relevé un fait structurel : sa struct `Envelope` ne porte aucun champ d'identité
d'agent, et sous le profil Budget Substrate le `capabilityRoot` est figé à `keccak(cap, asset)` — il
n'existe donc **aucun endroit où accrocher un mandat**.

Notre `capabilityRoot` engage en plus l'adresse du registre de mandats et l'`agentId`, et
l'enveloppe conserve celui-ci : `agentIdOf` rend `2`, l'identifiant de l'enfant. C'est le champ
absent de sa structure.

Ce crochet est ce qui rend adressables les deux manques mesurés dans le seam test. Le **gel** (point
c) devient consultable parce que le compteur sait de quel agent il mesure la dépense. Le **plafond
hérité** (point b) devient vérifiable pour la même raison : un compteur qui connaît l'`agentId` peut
interroger le mandat, là où une enveloppe anonyme ne le peut pas. Le premier est démontré ici ; le
second ne l'est pas — il découle du même crochet, mais nous ne l'avons pas exécuté.

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
