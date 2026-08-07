# Vérifier un verdict signé, sans faire confiance à personne

`verify_verdict.py` recalcule localement un verdict au format **Nostr NIP-01 + schnorr
BIP-340**. Python pur, **aucune dépendance**, **aucun appel réseau** vers l'émetteur du
verdict : ni `/verify-proof`, ni `independent_node`. Vous ne demandez à personne si la
signature est bonne — vous la refaites.

Deux contrôles, indépendants et tous deux nécessaires :

- **(a) l'id NIP-01** — `sha256` du tableau JSON compact
  `[0, pubkey, created_at, kind, tags, content]` encodé UTF-8, comparé à `event.id` ;
- **(b) la signature schnorr BIP-340** — 64 octets, sur cet id de 32 octets pris comme
  **message brut** (pas de hachage supplémentaire), tag `BIP0340/challenge`, contre la
  clé publique x-only.

## D'abord, vérifier le vérificateur

Un outil qui dirait « OK » à tout ne prouverait rien. Confrontez-le aux vecteurs officiels
avant de lui faire confiance :

```bash
curl -sO https://raw.githubusercontent.com/bitcoin/bips/master/bip-0340/test-vectors.csv
python3 verify_verdict.py --self-test test-vectors.csv
```

Sortie attendue :

```
vecteurs BIP-340 officiels : 19/19 conformes, 0 divergence(s)
```

Les 19 vecteurs comptent **9 signatures valides et 10 invalides** : l'outil doit accepter
les premières *et* rejeter les secondes.

## Ensuite, vérifier un verdict

```bash
curl -s https://api.babyblueviper.com/ledger/236 | python3 verify_verdict.py -
curl -s https://api.babyblueviper.com/ledger/233 | python3 verify_verdict.py -
```

L'entrée peut être l'événement Nostr lui-même, ou n'importe quel objet JSON le contenant
sous `proof_event` ou `event`. Code de sortie `0` si les deux contrôles passent, `1` sinon
— utilisable en CI.

Résultat observé le 8 août 2026 sur ces deux entrées :

```
ledger/236 — reject (conf 0.84)
  pubkey      : 6786e18a864893a900bd9858e650f67ccc3513f248fed374b591e2ff6922fbb7
  id NIP-01   : OK   (ce953822d970b5786dd3474f43e159f80cdd08a81e254354449fb01c90a0c5a3)
  schnorr     : OK

ledger/233 — approve_with_concerns (conf 0.85)
  pubkey      : 6786e18a864893a900bd9858e650f67ccc3513f248fed374b591e2ff6922fbb7
  id NIP-01   : OK   (752399647f04e8cd5877287bda2dc9e7f3def417162f8ab3ad4995dc4fa7505d)
  schnorr     : OK
```

Falsifications testées sur ces mêmes événements — chacune est bien rejetée :

| altération | (a) id | (b) schnorr |
|---|---|---|
| un champ du `content` modifié | KO | KO |
| `created_at` décalé d'une seconde | KO | KO |
| 1 bit retourné dans la signature | OK | **KO** |
| `pubkey` remplacée par une autre clé valide | KO | KO |

Le troisième cas montre pourquoi les deux contrôles sont nécessaires : la signature
n'entre pas dans le calcul de l'id, donc seul (b) le rattrape.

## Ce que cela prouve, et ce que cela ne prouve pas

**Prouvé** : l'événement a été émis par le détenteur de cette clé et n'a pas été altéré
depuis — ni contenu, ni horodatage, ni tags.

**Non prouvé** : que la clé appartienne à qui elle prétend. La rattacher à une identité
suppose une source de confiance extérieure ; aller chercher `verifier-keys.json` sur le
serveur de l'émetteur reviendrait à lui redemander de se porter garant de lui-même.

**Non prouvé non plus** : l'*antériorité*. Une signature atteste qu'un verdict a été émis,
pas qu'il l'a été **avant** l'action qu'il gouverne, ni qu'il n'a pas été contourné. Les
verdicts vérifiés ci-dessus le disent eux-mêmes, via leur champ `source_class:
agent_reported` et le `vantage_limitation` qui l'accompagne. C'est une propriété que la
cryptographie ne peut pas fournir seule : elle demande un point de médiation que l'agent
agissant ne contrôle pas.

## Pourquoi c'est ici

Ce dépôt spécifie des mandats hérités et non-arrachables. Un mandat n'a de valeur que si
les verdicts qui l'autorisent sont eux-mêmes vérifiables par un tiers — et vérifiables
**sans** demander la permission à celui qui les émet. Cet outil est la moitié « lecture »
de cette exigence.
