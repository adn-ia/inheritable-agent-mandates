# Règles de travail — repo ADN-IA

Ce fichier est lu automatiquement par l'assistant à chaque session. Il fixe les règles
dures. **Principe fondateur : les vérifications sont la source de vérité, pas les
affirmations de l'assistant.** Le vérificateur ne doit jamais être le vérifié.

## Règle d'or

Avant d'annoncer « c'est fait » / « les règles sont suivies », l'assistant DOIT lancer
`npm run check` et **coller le résultat**. Une affirmation de conformité sans sortie de
`check` n'a aucune valeur et doit être ignorée. Ne pas dire « j'ai audité » — montrer le
diff et la sortie des tests.

## Règles dures

1. **Testnet uniquement.** Jamais de clé détenant de l'argent réel, jamais de mainnet.
2. **Ne jamais lire, écrire ni committer `.env` ou une clé privée.** (déjà gitignorés)
3. **Les invariants d'héritage sont sacrés** et vérifiés par `tests/invariants.ts` — ils
   DOIVENT rester verts :
   - `enfant ⊆ parent` (plafond ≤, payees ⊆, bail non relâché) ;
   - le télomère ne fait que **décroître** ; aucune fonction, nulle part, ne le remonte ;
   - le mandat est inscrit dans `geneId` (le modifier change l'identité).
4. **Petits diffs.** Une tâche = un changement ciblé. Ne pas refactorer du code non
   concerné. Montrer le diff, ne pas le résumer.
5. **Si une règle ne peut pas être suivie, le dire explicitement** au lieu de prétendre
   avoir réussi. Une déviation annoncée vaut mille fois mieux qu'une conformité affirmée.

## Ce que la machine refuse (barreau 1, pas barreau 4)

```bash
npm run check      # = typecheck + tests d'invariants ; doit passer
npm run reproduce  # démo de l'héritage (verrous + rejets d'évasion)
```

Le hook `.githooks/pre-commit` lance `npm run check` et **refuse le commit** s'il échoue.
Active-le une fois, après `git init` :

```bash
git config core.hooksPath .githooks
```

## Étendre les règles

Ajoute ici tes règles ; mais chaque fois que c'est possible, transforme une règle en
**test dans `tests/`** — une règle qu'une machine peut recaler ne dépend plus de la bonne
foi de personne.
