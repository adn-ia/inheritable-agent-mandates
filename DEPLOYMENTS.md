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
| [`ProvenanceRegistry`](contracts/ProvenanceRegistry.sol) | [`0x202f4eef39b57901061a7353595b72c61eacf5df`](https://sepolia.basescan.org/address/0x202f4eef39b57901061a7353595b72c61eacf5df) | 2 772 o | [`DEMO-PROVENANCE.md`](DEMO-PROVENANCE.md) |
| [`ContestationRegistry`](contracts/ContestationRegistry.sol) | [`0x236b71b033dc93634ce170d51dcd313bda19b233`](https://sepolia.basescan.org/address/0x236b71b033dc93634ce170d51dcd313bda19b233) | 2 800 o | [`TEST-CONTESTATION.md`](TEST-CONTESTATION.md) · [`TEST-CYCLE.md`](TEST-CYCLE.md) |
| [`StructuredBudget`](contracts/StructuredBudget.sol) | [`0x50fCE593013725BB9ebc837433c4604dCb897f46`](https://sepolia.basescan.org/address/0x50fCE593013725BB9ebc837433c4604dCb897f46) | 4 005 o | [`TEST-BUDGET-STRUCTURE.md`](TEST-BUDGET-STRUCTURE.md) |
| [`MandateWithException`](contracts/MandateWithException.sol) | [`0x8ce2a6c8c5d97c6fe71d2d07bae3a9e816a032bd`](https://sepolia.basescan.org/address/0x8ce2a6c8c5d97c6fe71d2d07bae3a9e816a032bd) | 4 445 o | [`TEST-COUTURE-EXCEPTION.md`](TEST-COUTURE-EXCEPTION.md) |

Une première instance de `MandateWithException` a été déployée à
[`0x6bfe54b2…3c51`](https://sepolia.basescan.org/address/0x6bfe54b247def01bd7c678333a04b018fb0b3c51)
avec deux adresses gardiennes sans clé connue — donc inopérable au-delà du seuil. Elle est
**remplacée** par l'instance ci-dessus et ne doit pas être citée.

## Les deux derniers déploiements

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
