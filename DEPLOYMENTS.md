# Déploiements — Base Sepolia

Tous les contrats de ce dépôt qui tournent sur une chaîne publique. **Réseau de test
uniquement**, `chainId 84532`. Contrats **non audités**, preuves de concept, **aucune valeur réelle
en jeu**.

Déployeur : `0x448Cc1c5689D9dFA2474265053A8FDF4bEb3B0Ae` — clé jetable, générée pour ce projet, qui
n'a jamais détenu autre chose que du testnet. Les trois clés gardiennes de `MandateWithException`
sont du même type : jetables, testnet, écrites dans `.env` (gitignoré) et jamais affichées.

## Contrats en ligne

| Contrat | Adresse | Code | Documenté dans |
|---|---|---|---|
| [`InheritableAgentMandate`](contracts/InheritableAgentMandate.sol) | [`0x2d463db56fadb55cd451d2c3237ec2213ba3bda9`](https://sepolia.basescan.org/address/0x2d463db56fadb55cd451d2c3237ec2213ba3bda9) | 3 148 o | [`DEPLOY.md`](DEPLOY.md) |
| [`ProvenanceRegistry`](contracts/ProvenanceRegistry.sol) (v1) | [`0x202f4eef39b57901061a7353595b72c61eacf5df`](https://sepolia.basescan.org/address/0x202f4eef39b57901061a7353595b72c61eacf5df) | 2 772 o | [`DEMO-PROVENANCE.md`](DEMO-PROVENANCE.md) |
| [`ProvenanceRegistryV2`](contracts/ProvenanceRegistryV2.sol) | [`0xa9d346b71747a424255c0187377276b7b22009e5`](https://sepolia.basescan.org/address/0xa9d346b71747a424255c0187377276b7b22009e5) | 2 924 o | ci-dessous |
| [`ContestationRegistry`](contracts/ContestationRegistry.sol) | [`0x236b71b033dc93634ce170d51dcd313bda19b233`](https://sepolia.basescan.org/address/0x236b71b033dc93634ce170d51dcd313bda19b233) | 2 800 o | [`TEST-CONTESTATION.md`](TEST-CONTESTATION.md) · [`TEST-CYCLE.md`](TEST-CYCLE.md) |
| [`StructuredBudget`](contracts/StructuredBudget.sol) | [`0x50fCE593013725BB9ebc837433c4604dCb897f46`](https://sepolia.basescan.org/address/0x50fCE593013725BB9ebc837433c4604dCb897f46) | 4 005 o | [`TEST-BUDGET-STRUCTURE.md`](TEST-BUDGET-STRUCTURE.md) |
| [`MandateWithException`](contracts/MandateWithException.sol) | [`0x8ce2a6c8c5d97c6fe71d2d07bae3a9e816a032bd`](https://sepolia.basescan.org/address/0x8ce2a6c8c5d97c6fe71d2d07bae3a9e816a032bd) | 4 445 o | [`TEST-COUTURE-EXCEPTION.md`](TEST-COUTURE-EXCEPTION.md) |
| [`InheritableAgentMandateV2`](contracts/InheritableAgentMandateV2.sol) | [`0x344cda78e7208684edf9a6241f5b95b1698e576a`](https://sepolia.basescan.org/address/0x344cda78e7208684edf9a6241f5b95b1698e576a) | 3 714 o | ci-dessous |

Une première instance de `MandateWithException` a été déployée à
[`0x6bfe54b2…3c51`](https://sepolia.basescan.org/address/0x6bfe54b247def01bd7c678333a04b018fb0b3c51)
avec deux adresses gardiennes sans clé connue — donc inopérable au-delà du seuil. Elle est
**remplacée** par l'instance ci-dessus et ne doit pas être citée.

## `InheritableAgentMandateV2` — la clause `validUntil`

```
adresse : 0x344cda78e7208684edf9a6241f5b95b1698e576a
tx      : 0xada54441cc97e2a57946188a86c8dcd54c3f4320869c08864ab97c61d3bda0bc
bloc    : 45051712 · gaz 879 347 · code 3 714 octets
gardien : 0x448Cc1c5689D9dFA2474265053A8FDF4bEb3B0Ae (le déployeur)
```

`InheritableAgentMandate` **v1** ([`0x2d463db5…`](https://sepolia.basescan.org/address/0x2d463db56fadb55cd451d2c3237ec2213ba3bda9))
reste en ligne, inchangé, et [`DEPLOY.md`](DEPLOY.md) continue de le décrire exactement. V2 est une
**instance séparée** : v1 n'a pas de `validUntil` et n'en aura pas. Différences : la clause
`validUntil` (uint64, `0` = pas d'expiration), sa monotonie imposée au `spawn`, sa vérification
**locale** dans `isActive`, et `mandateRoot()` qui l'inclut dans le hash d'identité.

### Cascade complète — 16 générations, gel du génésis

Chaîne de 17 nœuds, `agentId` 1 (génésis) → 17 (profondeur 16), sans expiration.
Mint du génésis [`0x2edac76f…`](https://sepolia.basescan.org/tx/0x2edac76fa02e1fef2b4fb2863b4b086ca7be2e72d71c27565639f8088ceb7e70),
puis 16 `spawn`, jusqu'à [`0x2d85ed1e…`](https://sepolia.basescan.org/tx/0x2d85ed1ecde6236346bcf9b36bd750a78fd9def5fc7f5d64bd664c8c679d0b1e).

| Étape | Transaction | `isActive(17)` — profondeur 16 |
|---|---|---|
| avant gel | — | `true` |
| `freeze(1)` sur le génésis | [`0x3ec24e04…`](https://sepolia.basescan.org/tx/0x3ec24e04a6b6f034b4eb03695c59dfd0f9ebd2061b0bb921c272c8afb2f48ce0) | **`false`** |

Le gel d'un seul nœud, la racine, éteint une descendance à 16 générations sans qu'aucune
transaction ne touche les 16 autres.

### Direction — gel d'un ancêtre du milieu

Chaîne de 9 nœuds, `agentId` 18 → 26. `freeze(22)` (profondeur 4) :
[`0xeb6d0398…`](https://sepolia.basescan.org/tx/0xeb6d0398555dfd1b6b36abcc25c1810d1a7eeacbaf9f365584828a2f736ace82)

| profondeur | 0 | 2 | 3 | **4 (gelé)** | 5 | 6 | 8 |
|---|---|---|---|---|---|---|---|
| `agentId` | 18 | 20 | 21 | **22** | 23 | 24 | 26 |
| avant | `true` | `true` | `true` | `true` | `true` | `true` | `true` |
| après | `true` | `true` | `true` | **`false`** | `false` | `false` | `false` |

Le gel descend et ne remonte pas.

### `validUntil` — les deux refus, on-chain

Parent `agentId` 27, `validUntil = t0 + 3600` avec `t0 = 1785871828`
([`0xbdd86292…`](https://sepolia.basescan.org/tx/0xbdd8629261fa2f5553f10e1f2bd0957320c79711311a7c5c8f036f9e6e00fd84)).

| Tentative | Transaction | Issue |
|---|---|---|
| Enfant à `t0 + 7200` (plus tard que le parent) | [`0xcf2951a4…`](https://sepolia.basescan.org/tx/0xcf2951a44f7f86856e7390e77b4f3427ae8e326370fd8b72360154821c2f8fae) | **`reverted`** — `validUntil cannot exceed parent` |
| Enfant à `0` (retrait de l'expiration héritée) | [`0x8a172fd2…`](https://sepolia.basescan.org/tx/0x8a172fd23b9fcccd3209bd8d1aa6329a8d9cc140a1e58449814e3daeaca161e5) | **`reverted`** — `validUntil cannot exceed parent` |
| Enfant à `t0 + 1800` (resserrement) | [`0xe7d0fbb8…`](https://sepolia.basescan.org/tx/0xe7d0fbb8ad0d456450e26c2f2fc3ee7393e0c7145100084aae1778bb1c5200d0) | `success` — `agentId` 28 |

Les deux refus sont des transactions **incluses dans des blocs**, pas des simulations. La raison est
lisible en rejouant l'appel (voir plus bas).

### Un nœud expire vraiment, et avant son parent

| `agentId` | `validUntil` | mint | `isActive` |
|---|---|---|---|
| 29 | `1785871926` (échéance courte, réellement attendue) | [`0xb24e295b…`](https://sepolia.basescan.org/tx/0xb24e295b40c994355d5804d2e73075e74993788daeca25fb9e1c4b28a8a2842a) | `true` avant, **`false`** après |
| 30 | `1785871835` (déjà dépassé au mint) | [`0x334afeca…`](https://sepolia.basescan.org/tx/0x334afecafcf4d9142eca483acdb909ac1a20c299a656cc8e506264d0ebf5a6a6) | **`false`** |

La lecture la plus parlante n'a pas été construite, c'est le temps qui l'a produite. À
`timestamp = 1785874850` :

```
parent 27 · validUntil 1785875428 (à venir) → isActive true
enfant 28 · validUntil 1785873628 (passé)   → isActive false
```

L'enfant est mort, le parent vit. C'est la propriété qui autorise le check local : un nœud expire
toujours avant ou en même temps que ses ancêtres, donc lire son seul champ suffit — inutile de
marcher la lignée pour l'expiration, contrairement au gel. **Cette lecture est datée** : passé
`1785875428`, les deux valent `false` et la démonstration ne se rejoue plus telle quelle.

### Non-strippabilité — `mandateRoot` inclut `validUntil`

Deux mandats identiques en tout point sauf l'échéance :

| `agentId` | `validUntil` | mint | `mandateRoot` |
|---|---|---|---|
| 31 | `1785872936` | [`0x39a0115a…`](https://sepolia.basescan.org/tx/0x39a0115a8376862ba67e191b56b5e83c322e03dae8654c6de543091267376605) | `0xf642d65d903cf8f38affb0d79441285b6df0895bbd19b872a4f9b6cc05564548` |
| 32 | `1785873936` | [`0x59d48f31…`](https://sepolia.basescan.org/tx/0x59d48f31cb60121bd07149c48c77f29b881981f7876a674cac38cb7b1ee01cd4) | `0xc49a182168fc1b88d29210ea78dbf489a933bb018d6ac993594f28a46cdee6c2` |

Racines distinctes : retirer ou repousser l'échéance produit un autre hash, donc ne peut pas se
faire passer pour le même mandat. C'est le trou laissé ouvert en v1, où le hash de couture omettait
la clause.

### Gaz de `isActive` — mesuré, et son extrapolation

Mesures `cast estimate` sur la chaîne A, réseau réel :

| profondeur | 1 | 2 | 4 | 8 | 12 | 16 |
|---|---|---|---|---|---|---|
| `agentId` | 2 | 3 | 5 | 9 | 13 | 17 |
| gaz | 28 780 | 33 202 | 42 045 | 60 142 | 77 864 | 95 586 |

Marginal entre profondeurs successives : **≈ 4 421 à 4 524 gaz par génération**, soit
**4 454 en moyenne** sur 1 → 16 — constant, comme attendu d'une boucle qui fait le même travail à
chaque tour.

**Ce chiffre corrige une mesure locale antérieure de ~407 gaz/génération**, qui était fausse par
construction : elle mesurait des appels successifs dans une même transaction, donc des slots de
stockage **déjà chauds**. Vérifié en local avec `vm.cool` :

| profondeur | 1 | 8 | 16 | marginal |
|---|---|---|---|---|
| slots froids | 10 099 | 40 990 | 76 294 | **≈ 4 413/gén.** |
| slots chauds | 2 103 | 4 994 | 8 297 | ≈ 413/gén. |

Le froid local (4 413) et le réseau réel (4 454) concordent ; le chaud (413) explique l'ancien
chiffre. Chaque génération coûte deux `SLOAD` froids (`mandateOf[cur].frozen` et `parentOf[cur]`),
soit 4 200 gaz, plus la boucle.

> **Mesuré vs extrapolé — à ne pas confondre.**
> **Mesuré :** la cascade correcte jusqu'à 16 générations, la direction du gel, les deux refus
> `validUntil`, l'expiration réelle, et le marginal de ~4 454 gaz/génération entre les profondeurs
> 1 et 16.
> **Extrapolé :** le pire cas. Le télomère est un `uint16`, plafond 65 535 générations ; à ce
> marginal, une lecture de `isActive` à cette profondeur coûterait **≈ 292 millions de gaz**
> (65 535 × 4 454). Ce nombre est de **l'arithmétique, pas une mesure** — déployer 65 535 `spawn`
> serait absurde, et rien ici ne l'a fait. Ce que le testnet établit, c'est que la cascade est
> correcte et que le marginal est constant sur la plage observée ; la projection au-delà en dépend.
>
> Conséquence, elle aussi extrapolée : bien avant le plafond du télomère, une lecture sur une
> lignée très profonde dépasse les limites de gaz usuelles d'un `eth_call`. C'est un **coût de
> lecture**, pas un contournement du gel : personne ne devient actif en devenant illisible. Le
> télomère est ce qui **borne** ce pire cas ; il ne ferme aucun trou de sécurité, il plafonne une
> facture.

### Lectures reproductibles

```bash
C=0x344cda78e7208684edf9a6241f5b95b1698e576a
R=https://sepolia.base.org

# cascade : génésis gelé, toute la chaîne A est éteinte
cast call $C 'isActive(uint256)(bool)' 17 --rpc-url $R   # profondeur 16 → false
cast call $C 'isActive(uint256)(bool)' 2  --rpc-url $R   # profondeur 1  → false

# direction : chaîne B, gel à la profondeur 4 (agentId 22)
cast call $C 'isActive(uint256)(bool)' 21 --rpc-url $R   # au-dessus → true
cast call $C 'isActive(uint256)(bool)' 22 --rpc-url $R   # le gelé   → false
cast call $C 'isActive(uint256)(bool)' 26 --rpc-url $R   # en dessous → false

# validUntil : le hash d'identité change avec l'échéance
cast call $C 'mandateOf(uint256)(uint256,uint64,uint16,bool,bool)' 31 --rpc-url $R
cast call $C 'mandateOf(uint256)(uint256,uint64,uint16,bool,bool)' 32 --rpc-url $R
cast call $C 'mandateRoot(uint256)(bytes32)' 31 --rpc-url $R
cast call $C 'mandateRoot(uint256)(bytes32)' 32 --rpc-url $R

# le refus, rejoué : la raison exacte du revert
F=0x448Cc1c5689D9dFA2474265053A8FDF4bEb3B0Ae
P=0x000000000000000000000000000000000000dEaD
cast call $C 'spawn(uint256,address,(uint256,uint64,uint16,bool,bool),address[])' \
  27 $F '(100000000000000000000,1785879028,4,true,false)' "[$P]" --from $F --rpc-url $R
# → execution reverted: validUntil cannot exceed parent

# gaz, à refaire soi-même
for d in 2 3 5 9 13 17; do cast estimate $C 'isActive(uint256)' $d --rpc-url $R; done
```

Attention aux nœuds datés : 28, 29, 30, 31 et 32 ont des échéances désormais passées, `isActive` y
rend `false` définitivement. Le parent 27 expire à `1785875428` — avant cet instant il se lit
`true`, après `false` ; c'est lui qui portait la démonstration « enfant mort, parent vivant », qui
ne se rejoue donc plus une fois l'échéance franchie. Les chaînes A et B, elles, n'ont aucune
expiration et restent lisibles à l'identique.

## `ProvenanceRegistryV2` — l'instance du namespace « fidélité »

```
adresse : 0xa9d346b71747a424255c0187377276b7b22009e5
tx      : 0x1270c4609ad4214e8a0bac4175f43184c9f1fc28ba572a7deaecf32eba4d3426
bloc    : 45024766        gaz : 679 287
chainId : 84532
```

Deux changements par rapport à v1, et deux seulement : le champ **`implementationCommit`** à côté de
`specCommit`, et l'alias de lecture **`sameHeritageCluster(a, b, maxDepth)`** qui renvoie exactement
`shareLineage`.

Le cluster est **dérivé**, pas stocké : aucun champ auto-déclaré. Un tag libre aurait permis à deux
nœuds sans la moindre ascendance d'être rendus « du même cluster » pour le prix d'un mot ; la
dérivation ne peut pas inventer un lien absent du graphe. En contrepartie, elle ne voit que ce qui a
été déclaré comme parent, et son verdict dépend de la profondeur demandée.

Le namespace est assuré par **des instances séparées**, pas par un tag de domaine : cette instance-ci
est celle des interpréteurs. Un tag seul évite les collisions d'identifiants mais n'empêche pas une
lignée de traverser les domaines — une instance distincte rend ce chemin inexistant plutôt
qu'interdit.

**v1 reste en place** à `0x202f4eef…f5df`, inchangée et toujours fonctionnelle. v2 ne la remplace
pas : c'est une instance distincte, pour un usage distinct.

### Exercé on-chain

Petit arbre : `X` et `Y` déclarent chacun un parent qui déclare `A` — leur ancêtre commun est donc à
**deux générations**. `Z` est enregistré sans parent.

| Nœud | Parents | Transaction |
|---|---|---|
| `A` | — | [`0xbbb02600…8ed5d2`](https://sepolia.basescan.org/tx/0xbbb0260087fea64bf9e33e5fb5564d14cdab39529e48a53b1d2d74b2b98ed5d2) |
| `M` | A | [`0x8a888954…889e84`](https://sepolia.basescan.org/tx/0x8a8889547c5e641365a2115c5c62fdce831b0043b8511eeafefe8614e5889e84) |
| `N` | A | [`0x1b5a1ff6…6dfc7f`](https://sepolia.basescan.org/tx/0x1b5a1ff6980e82f0bc7d6291287034008ae7618e8d0a0d95d71a9e08726dfc7f) |
| `X` | M | [`0xc537d7a9…9bf5e4`](https://sepolia.basescan.org/tx/0xc537d7a9fde0164e63d0b8c299e93da8053957bec34f00151becde45769bf5e4) |
| `Y` | N | [`0xd342e790…97655a`](https://sepolia.basescan.org/tx/0xd342e790834f3a4b01b20c2a277c6ef540a6dde59c828e7e744a577ea097655a) |
| `Z` | — | [`0x80c6e2ad…e80829`](https://sepolia.basescan.org/tx/0x80c6e2ad60802b675dbadac88857867d613635f60da28f7a4c8d112f59e80829) |

Deux refus, **transactions réelles incluses dans un bloc** — pas des simulations :

| Tentative | Transaction | Issue |
|---|---|---|
| Ré-enregistrer `A`, déjà pris | [`0x09e36ec4…de3c1b`](https://sepolia.basescan.org/tx/0x09e36ec47e76f0e0e9ef707f3cc45028be57f9f7c9c9e1710c2db0e35ede3c1b) | **`reverted`** — `programKey already registered` |
| Déclarer un parent inexistant | [`0x53553d82…76ba6b`](https://sepolia.basescan.org/tx/0x53553d82f555d1f49777501bb0cfa9a3e82e0a83c7c1c6babf7b8c030476ba6b) | **`reverted`** — `unknown parent` |

### Lectures reproductibles

```bash
C=0xa9d346b71747a424255c0187377276b7b22009e5
RPC=https://sepolia.base.org
X=0x1395e57b38581c3a07dd28557757c2e31f7e450b6956cdeebffdec5c87dbb14d
Y=0xa1e16c0174748792394539dfefb3aac9f4d6674577bdc0ef71270ae348f38378
Z=0x2c6edb0e7f192004d7f359f8d272d5fc63ce2fa3bdcf6c584097ecd1f9db560f

cast call $C 'recordOf(bytes32)(bytes32,bytes32,address,uint8,bool)' $X --rpc-url $RPC
cast call $C 'sameHeritageCluster(bytes32,bytes32,uint8)(bool)' $X $Y 1 --rpc-url $RPC
cast call $C 'sameHeritageCluster(bytes32,bytes32,uint8)(bool)' $X $Y 2 --rpc-url $RPC
cast call $C 'sameHeritageCluster(bytes32,bytes32,uint8)(bool)' $X $Z 1 --rpc-url $RPC
cast call $C 'sameHeritageCluster(bytes32,bytes32,uint8)(bool)' $X $Z 2 --rpc-url $RPC
```

Ce que ces commandes rendent :

```
recordOf(X)
   specCommit           0x97b5c17b40398efcba9711dac94bbf13809f3f5d9100a0304a0507edfd8b5ffa
   implementationCommit 0x190d2f0852079865df9bd6f121569b45090f8bdd9ce65cbd449003b59606a1c9
   author               0x448Cc1c5689D9dFA2474265053A8FDF4bEb3B0Ae
   reviewMethod         0        exists  true

sameHeritageCluster(X, Y, 1) → false
sameHeritageCluster(X, Y, 2) → true      ← la famille apparaît à la profondeur de A
sameHeritageCluster(X, Z, 1) → false
sameHeritageCluster(X, Z, 2) → false     ← Z ne devient jamais cousin
```

> **Ce que cet exercice prouve, et ce qu'il ne prouve pas.** La preuve falsifiable est **le fuzz
> local** — 256 exécutions comparant l'alias à `shareLineage` sur toutes les paires et profondeurs,
> plus les invariants de v1 rejoués. Cet exercice on-chain sert deux autres choses : la
> **reproductibilité publique** — n'importe qui peut relancer les `cast call` ci-dessus sans nous
> faire confiance — et **deux refus constatables** dans des blocs, plutôt qu'affirmés.

## Les deux déploiements précédents

### `StructuredBudget`

```
adresse : 0x50fCE593013725BB9ebc837433c4604dCb897f46
chainId : 84532
arguments de constructeur : aucun
lecture de contrôle       : nextId() → 1
                            totalRoom(1) → revert NoSuchBudget() (0x86e2c541)
```

### `MandateWithException`

```
adresse : 0x8ce2a6c8c5d97c6fe71d2d07bae3a9e816a032bd
tx      : 0x7e591cae32dcc2527b3415fd83057a730d180b30eda68ad812c4c3056c5eb622
gaz     : 1 159 716
chainId : 84532

arguments de constructeur :
   guardians          = [0x3D7261F2…9fB4, 0x9A280D95…5DC7, 0xE0CaF858…1da8]
   maxExceptionAmount = 0.5 ETH
   bigThreshold       = 0.2 ETH
   bigApprovals       = 2

lectures de contrôle :
   guardianCount()              → 3
   isGuardian(gardien 1/2/3)    → true / true / true
   isGuardian(déployeur)        → false
   requiredApprovals(0.1 ETH)   → 1
   requiredApprovals(0.3 ETH)   → 2
```

Les trois gardiens sont des **clés jetables réellement contrôlées**, générées pour ce déploiement,
écrites dans `.env` (gitignoré) et jamais affichées. Chacune est financée d'un filet de gaz de
0,002 ETH pour pouvoir signer ses approbations. Le déployeur, agent du budget de démonstration,
**n'est pas gardien** — la séparation des rôles est donc effective on-chain, pas seulement dans le
code.

```
gardien 1 : 0x3D7261F26BD059aB6F486a9f925b31C00A839fB4
gardien 2 : 0x9A280D95760726d57A9c453d865D710E598D5DC7
gardien 3 : 0xE0CaF85879c7109E52f506a99eCF457f67DF1da8
```

#### Le seuil N-sur-M, exercé on-chain

Budget 1 : agent = déployeur, plafond 1 ETH, dont 0,9 déjà dépensé. Exception demandée : **0,3 ETH**,
au-dessus du seuil de 0,2 — donc **deux approbateurs distincts requis**.

| Étape | Transaction | Issue |
|---|---|---|
| Le gardien 1 propose (0,3 ETH) | [`0x98b3de83…7bbdc`](https://sepolia.basescan.org/tx/0x98b3de833d63487c711234c3584f2b2a43971d87b75fd4848a92c6dce957bbdc) | `success` — exception 1, 1 approbateur |
| Tirage avec **un seul** approbateur | [`0xe6f58fdd…b2529`](https://sepolia.basescan.org/tx/0xe6f58fddb28fe93c2debf84cd66ee60d83fc7dddcdc786063290bfc5d27b2529) | **`reverted`** |
| Le gardien 1 approuve **une seconde fois** | [`0xd92eecc7…d5d111`](https://sepolia.basescan.org/tx/0xd92eecc75a0d5a9fc05fb0a051c89c92f53b8e42f2da9b5b9591df8695d5d111) | **`reverted`** |
| Le gardien 2 approuve | [`0xe66aa50a…df58de`](https://sepolia.basescan.org/tx/0xe66aa50a259209cc78502c535578b0c79566debe184002865e5f7a4214df58de) | `success` — 2 approbateurs |
| Tirage avec **deux** approbateurs | [`0x52e2d13d…35ffec`](https://sepolia.basescan.org/tx/0x52e2d13d9ff568d8047782e269f100ac10c9ef66dfb4f460abdf3f981835ffec) | `success` |

État final, relu sur la chaîne :

```
exceptionOf(1) — montant 0.3 ETH · consommée true · approbateurs 2
approversOf(1) — [0x3D7261F2…9fB4, 0x9A280D95…5DC7]
budgetOf(1)    — spent 0.95 ETH · exceptionAllowance 0.3 ETH
effectiveCeiling(1) — 1.3 ETH
```

Les deux refus sont des **transactions réelles, incluses dans des blocs et revertées** — pas des
simulations. Le seuil n'est donc pas une propriété affirmée par nos tests locaux : il est
constatable par n'importe qui sur l'explorateur.

## Non déployés — locaux uniquement

Ces contrats existent dans le dépôt et sont testés sous Foundry, mais ne tournent sur aucune chaîne :

- [`MandateAwareCursor`](contracts/MandateAwareCursor.sol) — voir [`TEST-SEAM-DEMO.md`](TEST-SEAM-DEMO.md)
- [`MandateAwareAggregateCursor`](contracts/MandateAwareAggregateCursor.sol) — voir [`TEST-SECTION5.md`](TEST-SECTION5.md)

## Vérification du source sur l'explorateur

**Aucun des contrats n'est vérifié sur Basescan.** Il n'y a pas de clé API Basescan sur cette
machine — ni dans l'environnement, ni dans un fichier de clés. La vérification n'a donc pas été
tentée, plutôt que d'être annoncée sans être faite.

En attendant, ce qui est vérifiable par un tiers sans nous faire confiance : le bytecode déployé est
lisible sur l'explorateur, les sources sont dans `contracts/`, et chaque contrat se recompile avec
`npx tsx scripts/compile.ts <Nom>` sous solc 0.8.36, optimiseur activé, 200 runs. Les lectures de
contrôle ci-dessus sont reproductibles avec `cast call`.

## Reproduire un déploiement

```bash
npx tsx scripts/compile.ts StructuredBudget
npx tsx scripts/compile.ts MandateWithException
npx tsx scripts/deploy-demos.ts
```

Le script lit la clé de déploiement dans `.env` (gitignoré) et ne l'imprime jamais — seule l'adresse
apparaît dans sa sortie.
