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
| [`MandateGate`](contracts/MandateGate.sol) | [`0x6882d039e266e5357d82cf3c7215b7639f5c24ea`](https://sepolia.basescan.org/address/0x6882d039e266e5357d82cf3c7215b7639f5c24ea) | 5 870 o | ci-dessous |
| [`MandateGateV2`](contracts/MandateGateV2.sol) | [`0xa211fd59fc964e70ffb70d27c2f2f6a982d0efa8`](https://sepolia.basescan.org/address/0xa211fd59fc964e70ffb70d27c2f2f6a982d0efa8) | 10 324 o | ci-dessous |
| [`MandateGateV3`](contracts/MandateGateV3.sol) | [`0x34a9ab58756b9a0579d9d156292412bbed87cbe8`](https://sepolia.basescan.org/address/0x34a9ab58756b9a0579d9d156292412bbed87cbe8) | 11 865 o | ci-dessous |
| [`InheritableAgentMandateV3`](contracts/InheritableAgentMandateV3.sol) | [`0xfd786e6dda41faea07c45948114d497b0f39f32b`](https://sepolia.basescan.org/address/0xfd786e6dda41faea07c45948114d497b0f39f32b) | 3 961 o | ci-dessous |

Une première instance de `MandateWithException` a été déployée à
[`0x6bfe54b2…3c51`](https://sepolia.basescan.org/address/0x6bfe54b247def01bd7c678333a04b018fb0b3c51)
avec deux adresses gardiennes sans clé connue — donc inopérable au-delà du seuil. Elle est
**remplacée** par l'instance ci-dessus et ne doit pas être citée.

## `InheritableAgentMandateV3` — invariant de conservation (Base Sepolia)

> **Contrat de référence, non audité, ne détient aucun fonds.** Testnet uniquement.

```
adresse : 0xfd786e6dda41faea07c45948114d497b0f39f32b
tx      : 0xe83d4f4bd21b5e57ab05dec19ab2b3f0b64c0c9bcb2fe1d7d152ceece50c0382
bloc    : 45313484 · gaz 932 773 · code 3 961 octets
gardien : 0x448Cc1c5689D9dFA2474265053A8FDF4bEb3B0Ae (EOA de test)
```

**Sourcify : `exact_match`**, création et exécution —
[`sourcify.dev/server/v2/contract/84532/0xfd78…f32b`](https://sourcify.dev/server/v2/contract/84532/0xfd786e6dda41faea07c45948114d497b0f39f32b)

### Ce que V3 ajoute à V2

`enfant ⊆ parent` seul laissait passer une évasion par **fan-out** : dix enfants à 100 % du
plafond parent chacun font 1000 %, sans qu'aucun ne viole la règle pris isolément. Le contrat
comptabilise désormais ce qu'un parent a distribué (`allocatedOf`) et refuse au-delà du reste.
L'ancienne garde en est subsumée — sans rien d'alloué, le reste vaut le plafond du parent.

### Exercé on-chain

| Étape | Transaction | Issue |
|---|---|---|
| `mint` racine, plafond 500 | [`0x029fd0e1…9616`](https://sepolia.basescan.org/tx/0x029fd0e19d2dfb2b4c951fbb4436679fd22c47524daf5fc36a050f31baf09616) | `success` — agent 1 |
| `spawn` enfant à 500 (consomme tout) | [`0x0c026717…d8a9`](https://sepolia.basescan.org/tx/0x0c026717ca576e30725305e39fe082cacc8e544846b5f1a6b12d0fbaa117d8a9) | `success` — agent 2 |
| `spawn` 2ᵉ enfant, **1 wei** | [`0xb49fbc3e…0871`](https://sepolia.basescan.org/tx/0xb49fbc3eb8b9adedffecdd5653d3216a65b5622019d0d1a4a4d700ec8b080871) | **`status 0`** — `conservation: exceeds parent unallocated budget` |

Le refus est une transaction **incluse dans un bloc**, pas une simulation. Et il porte sur
**1 wei** : ce n'est pas « ça refuse gros », c'est « ça refuse au wei près ».

### Lectures reproductibles

```bash
C=0xfd786e6dda41faea07c45948114d497b0f39f32b
R=https://base-sepolia-rpc.publicnode.com

cast call $C 'allocatedOf(uint256)(uint256)'     1 --rpc-url $R   # → 500
cast call $C 'availableBudget(uint256)(uint256)' 1 --rpc-url $R   # → 0
cast call $C 'parentOf(uint256)(uint256)'        2 --rpc-url $R   # → 1

# le fan-out, rejoué en lecture seule
cast call $C 'spawn(uint256,address,(uint256,uint64,uint16,bool,bool),address[])' \
  1 0x448Cc1c5689D9dFA2474265053A8FDF4bEb3B0Ae '(1,0,7,false,false)' \
  '[0x000000000000000000000000000000000000dEaD]' \
  --from 0x448Cc1c5689D9dFA2474265053A8FDF4bEb3B0Ae --rpc-url $R
# → execution reverted: conservation: exceeds parent unallocated budget
```

### La limite, mesurée et non masquée

L'invariant borne ce qu'un parent **distribue**, pas ce que l'arbre **consomme**. Un parent
qui a tout alloué garde son plafond propre intact. Démontré par la dépense réelle à travers
`MandateGateV3` — deux exécutions, verdicts ECDSA signés, `spent[]` relu : racine 500 +
enfant 500 = **1000 dépensés** pour un plafond de racine de 500. Voir
`integration/test/ConservationPair.t.sol`.

Seconde face : le gardien peut minter des racines sans plafond global. La conservation vaut
**par lignée**, pas pour l'émission.

## `MandateGateV3` — époque d'émission et timelock (Base Sepolia)

> **Contrat de référence, non audité, ne détient aucun fonds.** Testnet uniquement.

```
adresse    : 0x34a9ab58756b9a0579d9d156292412bbed87cbe8
tx         : 0xbc997e31e71ec6f350a372320fb8aed332a5ee35b9102ff35a8fc6c43b3c7fa1
bloc       : 45274351 · gaz 2 617 451 · code 11 865 octets
gardien    : 0x448Cc1c5689D9dFA2474265053A8FDF4bEb3B0Ae (EOA de test)
mandat lu  : 0x2D463dB56FadB55cd451d2C3237EC2213bA3BdA9
MAX_WINDOW : 604 800 s (7 jours)   ·   TIMELOCK : 172 800 s (2 jours)
expectedVerifierTag() = eip155:84532:0x34a9ab58756b9a0579d9d156292412bbed87cbe8
```

**Sourcify : `exact_match`**, création et exécution —
[`sourcify.dev/server/v2/contract/84532/0x34a9…cbe8`](https://sourcify.dev/server/v2/contract/84532/0x34a9ab58756b9a0579d9d156292412bbed87cbe8)

### Ce que V3 ajoute à V2

**Époque d'émission.** Le contrat écrit lui-même `issuerEpoch[k] = block.timestamp` au
moment où il reconnaît une clé. Un verdict doit s'y lier — l'époque figure dans la
préimage signée sous la forme `"issuer_epoch":<décimal>` — et sa validité est plafonnée
à `epoch + MAX_WINDOW`. La différence avec une échéance choisie par l'émetteur : celle-ci
ne plafonne rien, puisqu'il peut la fixer à dix ans.

**Timelock asymétrique.** Autoriser passe par `proposeIssuerKey` puis, après le délai,
`confirmIssuerKey`. Révoquer est **immédiat**, et annule aussi toute proposition en cours
— sinon un gardien compromis pourrait proposer, se faire couper, puis confirmer plus tard.
`refreshIssuerEpoch` ré-horodate sans délai une clé **déjà** autorisée : cette opération ne
peut qu'invalider en masse les verdicts de l'époque précédente, jamais accorder un pouvoir.

`setIssuerKey` de V2 est **supprimé** : le laisser aurait offert une porte contournant le
timelock.

### Tests (locaux, `integration/test/MandateGateV3.t.sol`)

Le temps se manipule avec `vm.warp` — ni l'expiration ni le timelock ne sont observables
autrement. Verdicts réellement signés en schnorr.

| cas | résultat |
|---|---|
| dans la fenêtre | aboutit |
| à `epoch + MAX_WINDOW` pile | aboutit encore |
| à `epoch + MAX_WINDOW + 1 s` | `verdict expired` |
| après `refreshIssuerEpoch` | `stale issuer epoch` |
| préimage portant une autre époque | `epoch not bound to verdict` |
| `confirm` avant le délai | `timelock not elapsed` |
| `revoke` puis `confirm` après le délai | `not proposed` |
| `refreshIssuerEpoch` sur clé non autorisée | `issuer key not authorized` |

### État de V2

Les trois clés d'émetteur de [`0xa211fd59…efa8`](https://sepolia.basescan.org/address/0xa211fd59fc964e70ffb70d27c2f2f6a982d0efa8)
ont été révoquées ([`0x5c2225b5…bf17`](https://sepolia.basescan.org/tx/0x5c2225b5465bd4b94b2459da1a09142e6b13bfae454f9d0bf0fcdd7e8d4cbf17)
pour la dernière). Aucun verdict schnorr n'y est donc exerçable — non parce qu'il n'en
existe pas, mais parce qu'aucun émetteur n'y est plus reconnu. V2 reste en ligne et
documenté ci-dessous ; il ne doit plus servir de cible.

## `MandateGateV2` — porte additive schnorr (Base Sepolia)

> **Démonstrateur non audité, ne détient aucun fonds.** Testnet uniquement. Le chemin
> ECDSA/EIP-191 est repris à l'identique du `MandateGate` ci-dessous ; le schnorr est une
> **seconde entrée**, pas une modification de la première.

```
adresse  : 0xa211fd59fc964e70ffb70d27c2f2f6a982d0efa8
tx       : 0x2014eea8ac9b203cb9231b09552ce5202edcef4d910133ae0a4f5e51969a42ed
bloc     : 45251181 · gaz 2 284 951 · code 10 324 octets
gardien  : 0x448Cc1c5689D9dFA2474265053A8FDF4bEb3B0Ae (EOA de test)
mandat lu: 0x2D463dB56FadB55cd451d2C3237EC2213bA3BdA9 (le même que MandateGate)
source   : commit 9d1a9ee de `main`
expectedVerifierTag() = eip155:84532:0xa211fd59fc964e70ffb70d27c2f2f6a982d0efa8
```

`expectedVerifierTag()` est **reconstruit par le contrat** à partir de `block.chainid` et
`address(this)` — jamais accepté de l'appelant. Un verdict tiers doit porter cette chaîne
exacte dans son `intended_verifier`, sans quoi il est rejeté : c'est la séparation de
domaine, portée par le contenu signé puisque le format NIP-01 ne la prévoit pas au niveau
du digest.

### Vérification du source

| Vérificateur | État | Lien |
|---|---|---|
| **Sourcify** | **`exact_match`** — création **et** exécution | [`sourcify.dev/server/v2/contract/84532/0xa211…efa8`](https://sourcify.dev/server/v2/contract/84532/0xa211fd59fc964e70ffb70d27c2f2f6a982d0efa8) |
| BaseScan Sepolia | non vérifié | — (pas de clé API Etherscan v2 dans l'environnement) |

### Émetteurs autorisés

| Transaction | Clé (x-only) |
|---|---|
| [`0x4b933ea3…10be`](https://sepolia.basescan.org/tx/0x4b933ea3fec2628957cf8032d8479753f97c4388be4d1627156fbac43fcd10be) | `6786e18a864893a900bd9858e650f67ccc3513f248fed374b591e2ff6922fbb7` — babyblueviper1 / invinoveritas |
| [`0xc2d28a30…97b0`](https://sepolia.basescan.org/tx/0xc2d28a309792bb7999fd3726594e675110e16a5840010d8cd41b93f029c497b0) | clé de test déterministe, pour la démonstration ci-dessous |

L'allowlist est réglable **par le gardien seul** : un agent ne peut pas s'y inscrire.

### Le correctif « verdict does not approve », prouvé à cette adresse

Deux verdicts réellement signés en schnorr, liés à la **même action**, adressés au **même
gate**, émis par la **même clé**. Seul le mot diffère.

| Verdict | Transaction | Issue |
|---|---|---|
| `reject` | [`0xee73ffa0…6329`](https://sepolia.basescan.org/tx/0xee73ffa099b7258b7fba6a628e9bfa7c1542675dca0906b6521deaf7f9106329) | **`reverted`** — `verdict does not approve` |
| `approve` | [`0x4c88a8cd…66ac`](https://sepolia.basescan.org/tx/0x4c88a8cdb952dccd0f6d20cce633c2e1d4d6b52f035a5229c9a405b3e1a466ac) | `success` |

```
commit(action) = 0x70c83a986274d24156e1d00675536136e1d599d2c276d050802cb87329bd96b6
spent(3) après les deux transactions = 100000000000000   ← seul l'approve a dépensé
```

Le refus est une transaction **incluse dans un bloc**, pas une simulation. La signature du
`reject` est valide, sa liaison à l'action est bonne, son destinataire est ce gate, son
émetteur est autorisé — et il est refusé quand même, parce qu'il refuse.

### Instance dépréciée

[`0xfb63fa3af614d435a7b0c0009e2c477209708604`](https://sepolia.basescan.org/address/0xfb63fa3af614d435a7b0c0009e2c477209708604)
— **DÉPRÉCIÉE, ne pas citer.** Déployée avant le correctif : son `executeSchnorr` vérifie
la liaison, le destinataire, la signature et l'autorité, puis **exécute sans lire la
décision**. Un verdict `reject` y aurait dépensé. Sa `SchnorrVerdict` a 6 champs au lieu
de 7 (`offVerdict` absent), donc son ABI diffère de celle de `main`.

## `MandateGate` — démonstrateur d'exécution

> **Démonstrateur `MandateGate`, non audité, ne détient aucun fonds.** Autorité du verdict
> en **ECDSA / EIP-191**. Gardien **unique** (une EOA, pas un multisig). Interopérabilité
> cross-auteur **non incluse** — c'est l'étape suivante.

```
adresse  : 0x6882d039e266e5357d82cf3c7215b7639f5c24ea
tx       : 0xe8a5f72b996fe6a41d604cfadaa0f92879a4d44ab3f061306592cee4745c4a08
bloc     : 45094935 · gaz 1 322 817 · code 5 870 octets
gardien  : 0x448Cc1c5689D9dFA2474265053A8FDF4bEb3B0Ae (EOA unique — voir ci-dessous)
mandat lu: 0x2d463db56fadb55cd451d2c3237ec2213ba3bda9 (InheritableAgentMandate v1)
émetteur : 0x3855B75B2E0a0ea46c134f7A37c8eB05d9aD9547 (clé jetable, autorisée par le gardien)
```

Le gate **lit** le contrat de référence v1 et ne lui écrit rien : la démonstration réutilise
des agents qui y existaient déjà (`2` = racine, `3` = son enfant). **Aucune transaction n'a
été envoyée vers v1**, dont l'empreinte source reste `773b7f55…70b66`.

### Vérification du source

| Vérificateur | État | Lien |
|---|---|---|
| **Sourcify** | **`exact_match`** — bytecode de création **et** d'exécution | [`sourcify.dev/server/v2/contract/84532/0x6882…24EA`](https://sourcify.dev/server/v2/contract/84532/0x6882D039e266e5357d82Cf3C7215b7639F5c24EA) |
| BaseScan | **non vérifié** | — |

BaseScan n'est pas vérifié faute de clé API Etherscan v2 : aucune n'est présente dans
l'environnement, et l'API refuse (`Missing/Invalid API Key`). Ce n'est pas un obstacle
technique, seulement une clé à fournir — la vérification Sourcify, elle, est publique et
suffit à confirmer que le source de ce dépôt produit bien le bytecode déployé.

Détail utile à qui reproduit : le contrat a été compilé par `scripts/compile.ts` avec
**solc 0.8.36**, optimiseur activé, 200 runs — pas avec le `solc 0.8.24` du projet Foundry.
Une première tentative de vérification via forge a échoué (`bytecode_length_mismatch`)
précisément pour cette raison.

### Preuve live — une transaction par propriété

| Propriété | Transaction | Issue |
|---|---|---|
| Verdict lié + signé + émetteur autorisé | [`0xeefc059f…`](https://sepolia.basescan.org/tx/0xeefc059f966deec04793e4fe12b9f9d61ebcf2297d056b776a5335b4e7606b06) | `success` |
| Verdict forgé, **sans signature** | [`0xf5945822…`](https://sepolia.basescan.org/tx/0xf5945822e791583df125de3f050cd17ea9475aae80bd16636dfb9cba46692589) | **`reverted`** — `verdict signature invalid` |
| **Self-report** (l'agent se signe lui-même) | [`0x5b8b0879…`](https://sepolia.basescan.org/tx/0x5b8b08796b3bad3e3f7ee4df923b0aacbebec72e21d0f7106b2d8468963973a5) | **`reverted`** — `issuer not authorized` |
| Reclamation exacte au vrai parent | [`0x8ff1dbb1…`](https://sepolia.basescan.org/tx/0x8ff1dbb1a08d202500edc7ed1a7f3af6bc385e3eafd35c7d1376c0e770a4774e) | `success` |
| **Sur-retour** (un wei de trop) | [`0x1792d1cf…`](https://sepolia.basescan.org/tx/0x1792d1cf720cdcdf4727adf70d0750b90d1daaaa9a2889102ed729bd57beeb90) | **`reverted`** — `over-return` |

Mise en place : [`setIssuer`](https://sepolia.basescan.org/tx/0xe5e73c923d64c2b3e05487208ea9337c8d64b78eb026ba196afb0b8bf6e6db78)
et [`credit`](https://sepolia.basescan.org/tx/0x010fac120243bb6901cadb9468277c61051856b93e6eefe027fa728260128614)
(0,001 unité interne à l'agent 3). Les trois refus sont des transactions **incluses dans des
blocs**, pas des simulations.

Le cas du self-report est celui qui porte : le contrat récupère bien
`0x448Cc1c5…` comme signataire, c'est-à-dire exactement l'adresse déclarée — **la signature
est valide**. Le refus tombe sur l'autorité, pas sur la signature. Un acteur ne peut pas
juger sa propre action, même en signant correctement.

### Le livre se ferme

```
received(3)   = 1000000000000000   (0,001)
spent(3)      =  400000000000000   (0,0004)
returnedTo(3) =  600000000000000   (0,0006)
room(3)       = 0
bookClosed(3) = true
received(2)   =  600000000000000   ← le parent réel a bien été crédité
```

### Lectures reproductibles

```bash
G=0x6882d039e266e5357d82cf3c7215b7639f5c24ea
R=https://sepolia.base.org
P=0x448Cc1c5689D9dFA2474265053A8FDF4bEb3B0Ae   # propriétaire de l'agent 2 (le vrai parent)

# le livre de comptes de l'agent 3
cast call $G 'received(uint256)(uint256)'   3 --rpc-url $R
cast call $G 'spent(uint256)(uint256)'      3 --rpc-url $R
cast call $G 'returnedTo(uint256)(uint256)' 3 --rpc-url $R
cast call $G 'bookClosed(uint256)(bool)'    3 --rpc-url $R   # → true

# plafond effectif = minimum sur la lignée (agent 3 sous agent 2)
cast call $G 'effectiveCap(uint256)(uint256)' 3 --rpc-url $R  # → 4000000000000000

# qui est reconnu comme émetteur ?
cast call $G 'authorizedIssuers(address)(bool)' 0x3855B75B2E0a0ea46c134f7A37c8eB05d9aD9547 --rpc-url $R  # → true
cast call $G 'authorizedIssuers(address)(bool)' $P --rpc-url $R                                          # → false

# les deux refus de reclamation, rejoués
cast call $G 'reclaim(uint256,address,uint256)' 3 $P 1 --from $P --rpc-url $R
# → execution reverted: over-return
cast call $G 'reclaim(uint256,address,uint256)' 3 0x000000000000000000000000000000000000dEaD 0 --from $P --rpc-url $R
# → execution reverted: not the real parent

# le contrat de référence n'a pas bougé : il n'a reçu aucune transaction de ce banc
cast call 0x2d463db56fadb55cd451d2c3237ec2213ba3bda9 'isActive(uint256)(bool)' 3 --rpc-url $R  # → true
```

### Ce que cette démonstration établit, et ce qu'elle n'établit pas

**Établi on-chain** : le lien action↔verdict, l'exigence de signature, l'exigence d'autorité
(un self-report correctement signé est refusé), et la conservation de la reclamation — en
transactions réelles, vérifiables par n'importe qui.

**Non établi** : l'autorité n'a été exercée que par un émetteur que **j'ai moi-même créé et
autorisé**. Le vrai test est cross-auteur — présenter à ce gate un verdict réellement signé
par le serveur d'un tiers. Il reste à faire. De plus, le digest est de l'**EIP-191**, pas de
l'**EIP-712** typé : un émetteur tiers signera probablement du 712, et les octets signés
diffèrent — l'interopérabilité demandera un alignement. Enfin, `authorizedIssuers` est une
allowlist plate, sans quorum ni seuil N-sur-M, et le gardien est une **EOA unique** détenue
par l'auteur du dépôt : en production ce devrait être un multisig.

La batterie complète (19 cas) tourne en local — voir `integration/test/MandateGate.t.sol`.

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
