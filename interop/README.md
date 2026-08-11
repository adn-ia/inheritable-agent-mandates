# Interop — ERC-8370 confronté aux standards voisins

Ce dossier contient des **mesures**, pas des démonstrations. Chaque script s'exécute contre
du code réellement déployé sur Base Sepolia — pas un fork, pas un mock. Règle du dossier :
rien n'est affirmé publiquement qui ne soit d'abord passé par une transaction.

| # | exercice | contre quoi | ce qu'on a trouvé |
|---|---|---|---|
| 1 | [composition ERC-8004](#la-question) | registres ERC-8004 déployés | la réputation survit à la vente de l'identité |
| 2 | [le scénario du clone](#le-scénario-du-clone--ce-quun-nullifieur-ne-voit-pas) | brouillon *Unclonable Credentials* | un clone partage le budget, il ne le multiplie pas |

---

# 1 · Composer ERC-8370 avec ERC-8004

Le script s'exécute contre les registres **ERC-8004 réellement déployés** sur Base Sepolia.

| registre | adresse |
|---|---|
| IdentityRegistry | [`0x8004A818BFB912233c491871b3d84c89A494BD9e`](https://sepolia.basescan.org/address/0x8004A818BFB912233c491871b3d84c89A494BD9e) |
| ReputationRegistry | [`0x8004B663056A597Dffe9eCcC1965A193B7388713`](https://sepolia.basescan.org/address/0x8004B663056A597Dffe9eCcC1965A193B7388713) |

## La question

ERC-8004 donne aux agents une identité portable. ERC-8370 attache à une identité des
clauses de contrôle (plafond de dépense, télomère, gel) qui doivent survivre à tout.

Les deux se composent-ils ? Concrètement : **si l'identité d'un agent change de mains,
qu'est-ce qui suit le jeton ?**

L'identité ERC-8004 est un ERC-721 transférable. Ce n'est pas un défaut — c'est un choix
assumé, et leur spécification décrit ce que le transfert emporte. On a voulu vérifier ce
qui se passe quand on y greffe des clauses de contrôle.

## Reproduire

```bash
node interop/erc8004-composition.mjs
```

Requiert `PRIVATE_KEY` dans `.env` (Base Sepolia, ~0,001 ETH de test suffit). Le script
refuse de tourner si `chainId != 84532`.

Trois rôles distincts, parce que leur registre refuse l'auto-notation : un **vendeur** qui
possède l'agent, un **client** tiers qui le note, un **acheteur** qui l'acquiert. Les deux
derniers sont des comptes jetables dérivés de graines publiques codées en dur et financés
par le script — testnet uniquement, à ne jamais réutiliser.

## Le run de référence — agent `8902`, blocs 45318524-45318531

```
  ETAT AVANT LA VENTE
    ownerOf     : 0x448Cc1c5689D9dFA2474265053A8FDF4bEb3B0Ae
    agentWallet : 0x448cc1c5689d9dfa2474265053a8fdf4beb3b0ae
    mandate     : {"maxSpendWei":"1000","telomere":3,"frozen":false}
    reputation  : count 1 · somme 95

  ETAT APRES LA VENTE
    ownerOf     : 0x7C21483FD8d0434EAd1bF616ABB75E2D796cec71
    agentWallet : (vide)
    mandate     : {"maxSpendWei":"1000","telomere":3,"frozen":false}
    reputation  : count 1 · somme 95

══ CE QUE LA VENTE A EMPORTE ══════════════════════════════════════
  agentWallet       : EFFACE ( defini -> vide )
  clause de controle: SURVIT INTACTE
  reputation        : SURVIT INTACTE ( count 1 somme 95 -> count 1 somme 95 )
  reecriture par l'acheteur : ACCEPTEE, aucun refus
    clause finale   : {"maxSpendWei":"999999999","telomere":255,"frozen":false}
```

| étape | transaction |
|---|---|
| `register()` → agent 8902 | [`0x069e1bb7…`](https://sepolia.basescan.org/tx/0x069e1bb78ba92aba7e2afa1b9a080b70350efeaf7896f0f7de668de355bfc362) |
| `setMetadata(.., "mandate", ..)` — plafond 1000, télomère 3 | [`0x6fb03b5a…`](https://sepolia.basescan.org/tx/0x6fb03b5a8f78d89ffd8604b0c373917186e079bc4825bce3691f0740c507c322) |
| `giveFeedback(95)` par le client tiers | [`0xb8104e39…`](https://sepolia.basescan.org/tx/0xb8104e39f8c8e804d72e328d94a25633490eafdd8a286e391f5b662a0502545e) |
| `transferFrom` — la vente | [`0x1ad9194b…`](https://sepolia.basescan.org/tx/0x1ad9194befdd876a341bc1db964df5c2bb2326cf448071881a29132605fe7d5f) |
| `setMetadata(.., "mandate", ..)` **par l'acheteur** — plafond 999 999 999, télomère 255 | [`0x5182ed26…`](https://sepolia.basescan.org/tx/0x5182ed26263027bc159edd27a87d6763360cf6178e980c45232dbc0283f0fedd) |

## Ce qu'on a mesuré

**1. `agentWallet` est bien effacé au transfert.** Conforme à leur spécification. Rien à
signaler.

**2. Une clause attachée via leur extension metadata survit au transfert — et devient
réécrivable.** Le nouveau propriétaire a porté le plafond de 1 000 à 999 999 999 et le
télomère de 3 à 255, en une transaction, sans le moindre refus.

Le risque n'est donc pas que les clauses disparaissent à la vente. C'est qu'elles
**persistent en donnant l'apparence de tenir**, pendant que celui qui les subit a désormais
le droit de les récrire. Une clause de contrôle qui obéit à celui qu'elle contraint n'est
plus une clause de contrôle.

**3. La réputation suit le jeton.** C'est le point qui nous paraît le plus important, et il
dépasse la question des mandats.

Le `ReputationRegistry` indexe sur `agentId` :

```solidity
// agentId => clientAddress => feedbackIndex => Feedback (1-indexed)
mapping(uint256 => mapping(address => mapping(uint64 => Feedback))) _feedback;
```

`agentId` est un NFT transférable, et le contrat n'a aucun hook de transfert — zéro
occurrence de `_update` ou équivalent. Le jeton change de mains, les avis restent collés
au numéro.

Conséquence directe : **acheter l'identité, c'est acheter la réputation.** On construit un
historique propre, on vend le jeton, l'acheteur hérite de la confiance accumulée sans
l'avoir méritée. Le marché secondaire devient un contournement de la réputation.

Ce n'est pas théorique — c'est la ligne `reputation : SURVIT INTACTE` ci-dessus.

À noter : leur registre **refuse déjà** qu'on se note soi-même (`Self-feedback not
allowed`). Le garde anti-auto-notation existe. C'est ce qui rend l'écart notable : on ne
peut pas fabriquer sa propre réputation, mais on peut acheter celle d'un autre.

Leurs *Security Considerations* couvrent quatre points — sybil, permanence des pointeurs,
incitations des validateurs, capacités non garanties cryptographiquement. Le transfert de
réputation n'y figure pas.

## Ce que ça ne dit pas

Ce n'est pas un rapport de vulnérabilité et rien ici n'est exploité contre qui que ce soit.
Aucun fonds réel n'est en jeu : Base Sepolia, agents créés pour l'occasion.

C'est possiblement un choix de conception assumé de leur part — une identité qui se vend
avec son historique peut être exactement ce qu'on veut dans certains usages. Mais alors
cela mérite d'être écrit dans la spécification, parce que quiconque lit un score ERC-8004
suppose aujourd'hui qu'il a été gagné par celui qui le porte.

## Ce que ça a changé chez nous

Ce test a d'abord infirmé une phrase de notre propre spécification. ERC-8370 justifiait son
identité non transférable en affirmant qu'un transfert « détache ce qui y était lié ». La
mesure dit l'inverse : les clauses survivent. La justification était fausse, la conclusion
tenait pour une autre raison — la réécriture. La phrase a été corrigée dans
`eip/inheritable-agent-mandate.md` (commit `2d070f6`) avant toute publication de ces
résultats, et aucun contrat n'a été modifié.

---

# 2 · Le scénario du clone — ce qu'un nullifieur ne voit pas

`node interop/clone-vs-identity-cap.mjs`

Second exercice d'interopérabilité, contre un fil différent : *[IDEA/DRAFT] ERC —
Unclonable Agent Execution Credentials via Zero Knowledge Nullifiers*. Ce brouillon rend un
credential d'agent à usage unique via un nullifieur en connaissance nulle. Après discussion
dans le fil, sa garantie est énoncée précisément comme **« at most once, with no ordering »** :
un clone qui a copié la mémoire de l'agent gagne la course par construction, parce qu'il
n'attend pas la boucle de raisonnement de l'agent.

La question que cela laisse ouverte, et que ce script mesure : **le clone a gagné quoi ?**

## Le run de référence — agent 3, `MandateGateV3` Base Sepolia

| | montant | nonce | commitment | résultat |
|---|---|---|---|---|
| agent légitime | 4 000 000 000 000 000 wei | 1001 | `0x7e5dc801…9e71` | [`success`](https://sepolia.basescan.org/tx/0xb2c08b18ee6c1ea65ce4442b74e2004cb7d1577b07140dd5405fd4304bf6ede8) |
| clone | 1 wei | 1002 | `0xc10d1c6b…fc57` | [`reverted`](https://sepolia.basescan.org/tx/0x0261afb21216b7307ab496a110433370d32086fbbb43e8bc67676ee98c4ebc3d) — `over effective cap` |

**Rien n'a été rejoué.** Le clone présente une action différente, un salt différent, un
commitment différent, un verdict signé à neuf et un nonce inutilisé. Un registre de
nullifieurs aurait vu deux consommations parfaitement légitimes et accepté les deux.

Il n'obtient rien quand même, parce que la borne est soudée à l'identité et non au credential :

```solidity
require(spent[agentId] + amount <= effectiveCap(agentId), "over effective cap");
```

`effectiveCap` est le minimum le long de la lignée, et `spent` cumule sur toutes les
exécutions quel que soit le nombre de credentials émis. **N clones du même agent partagent un
seul budget** — l'inverse de l'intuition qu'invitent les systèmes à credentials, où N
credentials se lisent naturellement comme N budgets.

## La limite, dite d'emblée

Cela borne **une identité**, pas la consommation agrégée d'une lignée : un parent et son
enfant, chacun sous son propre plafond, peuvent ensemble dépasser celui du parent — mesuré et
consigné dans `DEPLOYMENTS.md`. Pour un clone qui engendre à son tour, la réponse est le gel
en cascade, pas le plafond.

## Rejouer

Le script exige que `PRIVATE_KEY` soit le gardien du gate (il appelle `setIssuer` et lit le
crédit) et refuse toute chaîne autre que Base Sepolia. Le plafond de l'agent 3 étant désormais
consommé, le script le détecte et s'arrête plutôt que de rejouer un scénario vide : pour
recommencer, engendrer un agent neuf, le créditer, puis relancer. Un tiers rejoue contre son
propre déploiement, ou lit simplement les deux transactions ci-dessus.
