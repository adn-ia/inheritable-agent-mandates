# Démo testnet — registre de provenance (« brin mitochondrial »)

`contracts/ProvenanceRegistry.sol` déployé sur **Base Sepolia** (chainId `84532`). Le hash du code
porte l'**identité** d'un interpréteur ; la **lignée** est une donnée distincte, déclarée à
l'enregistrement et héritée à part du code.

> **Testnet uniquement, contrat non audité, preuve de concept. Aucune valeur réelle en jeu.**

## Contrat

| | |
|---|---|
| Adresse | [`0x202f4eef39b57901061a7353595b72c61eacf5df`](https://sepolia.basescan.org/address/0x202f4eef39b57901061a7353595b72c61eacf5df) |
| Réseau | Base Sepolia (`84532`) |
| Tx de déploiement | [`0x85e990d5…161b5c`](https://sepolia.basescan.org/tx/0x85e990d5de593c6883f5defbd8780a1a2cd86d5a7e2ed21211b901714b161b5c) |
| Bloc | 44953453 |
| Compilateur | solc 0.8.36, optimiseur activé (200 runs) |
| Propriétaire | **aucun** — pas de constructeur à argument, personne ne peut réécrire un enregistrement |

ABI complète : `MAX_NODES`, `parentsOf`, `recordOf`, `register`, `shareLineage`. **Aucun setter,
aucun `delete`** — l'absence est vérifiable dans l'ABI on-chain, pas seulement dans le source.

## Le graphe enregistré

`runId 1785675403543` — les `programKey` sont salés par exécution, le registre étant write-once.

| | programKey | parents déclarés | méthode |
|---|---|---|---|
| **A** racine | `0xb4940079…03ae83` | — | BlindReconstruction |
| **B** | `0x3cdb9687…f352656` | A | DerivedFromExisting |
| **C** indépendant | `0xec3eed1a…b243cefe` | — | BlindReconstruction |
| **D** (code ≠ B) | `0xb098b792…5283f882` | A | SharedSpecCollab |
| **E** | `0x6f3472ff…5b9c3bcd` | B | DerivedFromExisting |

Transactions d'enregistrement, toutes `success` :
[A](https://sepolia.basescan.org/tx/0x0d7968d017d564ad2a7a0599c50b305a511781b129f9caf719b53f9fad8537d9) ·
[B](https://sepolia.basescan.org/tx/0x7b7a05ebc55a30b0e3f8201da4a1ef843e568e2d930d6d2aa04db82ba24c1f1a) ·
[C](https://sepolia.basescan.org/tx/0x12bc216df0a12c33712c0d10d227624cbbad8b80de1405027dad9ef5170a5373) ·
[D](https://sepolia.basescan.org/tx/0xdf9a32b973014d6e4123f8e7208c46dd54146198eaf2b4be084b2e823b36fee0) ·
[E](https://sepolia.basescan.org/tx/0xfd4e80b44df93e726ae0e2f340ff63df93937ed39be2f2680a88920811e53560)

---

## TEST 1 — append-only : **PASSÉ**

C'est **le résultat qui prouve quelque chose**. Cinq tentatives de réécrire un `programKey` déjà
pris, toutes refusées par la chaîne, avec le même motif `programKey already registered`.

| Tentative | Transaction | Résultat |
|---|---|---|
| Réécrire A avec un autre parent | [`0xf6450578…082899`](https://sepolia.basescan.org/tx/0xf645057855a6c1f1b936b59f2d34510ffa7639740df30d9b349a7a0078082899) | `reverted` |
| Réécrire A sans parent | [`0x69b46950…5f63a3dae`](https://sepolia.basescan.org/tx/0x69b469502d0588199e1771faf8ccac39d0d42fc5a779099cb6f97de5f63a3dae) | `reverted` |
| Réécrire B à l'identique | [`0x071831c0…5c2224c4`](https://sepolia.basescan.org/tx/0x071831c0032153fd13a03ffa6d7757a0244e8dd755c5b8e489890f095c2224c4) | `reverted` |
| Réécrire B en effaçant sa lignée | [`0xdd586009…cdc56b24`](https://sepolia.basescan.org/tx/0xdd5860098397b8b05ddd2e00fcfe33da86a2b7977627417fbc04f2d5cdc56b24) | `reverted` |
| Réécrire A depuis un **autre auteur** | — | rejet au niveau du nœud, non diffusée |

Le cinquième cas mérite sa nuance : une seconde clé a été financée pour l'occasion
(`0x49943F8Fd4156E7Af99185Ba25B9fC7b0f7c984c`), et le nœud RPC a refusé de diffuser la transaction
plutôt que de l'inclure — il n'y a donc **pas de hash on-chain** pour celui-là, contrairement aux
quatre autres. Le refus est réel, mais il est attesté par le nœud, pas par un bloc.

## TEST 2 — traversée `shareLineage` : **PASSÉ**

Huit cas, dont **cinq négatifs**. Attendu et obtenu, tels que sortis du contrat :

| Cas | Attendu | Obtenu | Ce qu'il teste |
|---|---|---|---|
| B vs D, depth 2 | `true` | `true` | ancêtre commun A |
| B vs C, depth 2 | `false` | `false` | **négatif** — ascendances disjointes |
| A vs C, depth 2 | `false` | `false` | **négatif** — aucun lien |
| D vs C, depth 3 | `false` | `false` | **négatif** — une profondeur accrue ne crée pas de lien |
| E vs A, depth 1 | `false` | `false` | **borne** — A est à 2 générations |
| E vs A, depth 2 | `true` | `true` | à portée à depth 2 |
| E vs D, depth 1 | `false` | `false` | **borne** — A est à 2 générations de E |
| E vs D, depth 2 | `true` | `true` | ancêtre commun A |

Les paires `depth 1` / `depth 2` sont la partie falsifiable : un contrat qui ignorerait `maxDepth`
rendrait `true` aux deux et le test échouerait.

---

## Illustration — **ce n'est pas un test, ce n'est pas un résultat**

`hashB ≠ hashD` (`0x3cdb9687…` vs `0xb098b792…`) alors que **B et D déclarent tous deux A comme
parent**.

Lecture correcte : **le modèle exprime la lignée séparément du code.** Deux interpréteurs au code
différent — donc au hash de contenu différent — peuvent porter une ascendance commune, et le
registre la restitue.

Lecture **interdite** : « on a détecté une lignée cachée ». D descend de A **parce qu'on l'a
déclaré**. Le contrat ne fait que relire cette déclaration. Aucune détection, aucune découverte.

## Reproduire

```bash
npm install
npx tsx scripts/compile.ts ProvenanceRegistry
npx tsx scripts/deploy-key-new.ts     # clé jetable → .env (imprime l'adresse à financer)
# financer l'adresse à un faucet Base Sepolia, puis :
npx tsx scripts/deploy-provenance.ts
npx tsx scripts/demo-provenance.ts
```

Le registre étant write-once, chaque exécution sale ses `programKey` avec un `runId`. Passer
`RUN_ID=1785675403543` rejoue exactement les clés ci-dessus (et donc reverte, puisqu'elles sont
déjà prises — ce qui est en soi une vérification de l'append-only).

## Ce que ça prouve, et ce que ça ne prouve pas

**Prouvé :** le mécanisme. On peut enregistrer un interpréteur, lui attacher une ascendance
déclarée, relire cette ascendance, et **il est impossible de réécrire un enregistrement** — ni par
son auteur, ni par un tiers, ni par le déployeur.

**Non prouvé, et il faut le dire :**

La provenance est **déclarée**, pas vérifiée. Le contrat ne peut pas savoir si une lignée déclarée
est vraie. Quelqu'un peut enregistrer un interpréteur en taisant son ascendance réelle, et la chaîne
l'acceptera. Ce que le registre garantit, c'est que la déclaration est **permanente, signée et
attribuable** : mentir reste possible, mais devient visible et imputable. Moins probable, plus
visible — pas impossible.

Ça ne prouve rien sur la **fidélité** de l'interpréteur, et ce n'est **pas** une détection de
corrélation réelle. Le hash de contenu, lui, reste objectif : c'est justement la complémentarité en
jeu.

**Enfin, une limite de méthode :** le contrat et les attentes du test ont été écrits par le même
auteur, dans la même session. C'est exactement le problème dont parle tout ce fil — le vérificateur
ne devrait pas être le vérifié. Les tests sont falsifiables et les sorties sont brutes, mais une
relecture par quelqu'un d'une autre lignée vaudrait plus que ce document.
