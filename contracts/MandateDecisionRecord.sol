// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title MandateDecisionRecord — le compte rendu que `execute` ne peut pas rendre
 * @notice Lecture seule. Ne modifie rien, ne détient rien, n'est appelé par personne
 *         d'autre qu'un intégrateur qui veut savoir POURQUOI.
 *
 *         LE TROU QU'IL COMBLE.
 *
 *         `MandateGateV3.execute` enchaîne onze `require`. Le premier qui échoue arrête
 *         tout et renvoie une phrase en anglais. Trois conséquences, toutes constatées :
 *
 *         1. On n'apprend qu'UN motif par appel. Un mandat à la fois inactif et au-dessus
 *            de son plafond se signale « agent not active » ; on répare, on relance, et on
 *            découvre le plafond. Deux allers-retours pour deux motifs indépendants.
 *
 *         2. « périmé » et « refusé » sortent par le même tuyau. `"verdict expired"` veut
 *            dire *rafraîchis la preuve* ; `"verdict does not approve"` veut dire *arrête*.
 *            Deux remèdes opposés, une seule forme de réponse, et une chaîne de caractères
 *            qu'aucune machine ne peut interpréter.
 *
 *         3. Rien ne distingue « ce contrôle a refusé » de « ce contrôle n'a pas été
 *            atteint » de « cette question n'a pas de sens ici ». S'il n'existe aucun
 *            agent, « dépasse-t-il son plafond ? » n'a pas de réponse : il n'y a pas de
 *            plafond. Ce n'est ni un refus, ni une question non posée.
 *
 *         CE QU'IL FAIT.
 *
 *         Il évalue les ONZE contrôles, dans l'ordre exact de `execute`, SANS JAMAIS
 *         S'ARRÊTER AU PREMIER, et rend un constat par contrôle. Chaque constat porte
 *         quatre choses : lequel, son état, l'instant où la réponse est établie, et
 *         jusqu'à quand elle vaut.
 *
 *         POURQUOI CE N'EST PAS DE LA DÉPENSE PERDUE.
 *
 *         Cette fonction est `view` : hors chaîne elle ne coûte rien. Arrêter au premier
 *         échec n'économise que sur le chemin d'exécution réel — où `execute` continue de
 *         le faire, inchangé. Deux métiers, deux fonctions. Aujourd'hui ils partagent la
 *         même, et c'est le seul défaut.
 *
 *         POURQUOI UN CONTRAT SÉPARÉ.
 *
 *         `MandateGateV3` est déployé (Base Sepolia, `0x34a9ab58756b9a0579d9d156292412bbed87cbe8`).
 *         Modifier son source romprait la correspondance entre le code publié et le
 *         bytecode en chaîne. Ce lecteur se pose À CÔTÉ d'une porte qui existe déjà et la
 *         lit par ses accesseurs publics. C'est aussi la situation réelle d'un intégrateur :
 *         il hérite d'une porte, il ne la redéploie pas.
 *
 *         Démonstrateur non audité, testnet uniquement.
 */

interface IMandateGateV3Reader {
    struct Action {
        uint256 agentId;
        address payee;
        uint256 amount;
        bytes32 salt;
    }

    struct Verdict {
        bytes32 artifactHash;
        address issuer;
        bool approve;
        uint256 nonce;
        uint64 expiry;
        bytes signature;
    }

    function mandate() external view returns (address);
    function commit(Action calldata a) external pure returns (bytes32);
    function recoverIssuer(Verdict memory v) external view returns (address);
    function effectiveCap(uint256 agentId) external view returns (uint256);
    function room(uint256 agentId) external view returns (uint256);
    function spent(uint256 agentId) external view returns (uint256);
    function usedCommitment(bytes32 c) external view returns (bool);
    function authorizedIssuers(address issuer) external view returns (bool);
    function usedNonce(address issuer, uint256 nonce) external view returns (bool);
}

interface IMandateReader {
    function ownerOf(uint256 agentId) external view returns (address);
    function isActive(uint256 agentId) external view returns (bool);
    function payeeAllowed(uint256 agentId, address payee) external view returns (bool);
}

contract MandateDecisionRecord {
    /// Les onze contrôles de `MandateGateV3.execute`, dans son ordre, sans exception.
    enum Check {
        BINDING,           // le verdict porte-t-il sur CETTE action ?
        FRESHNESS,         // la preuve est-elle encore fraîche ?
        SIGNATURE,         // l'émetteur déclaré a-t-il réellement signé ?
        ISSUER_AUTHORITY,  // le gardien reconnaît-il cet émetteur ?
        NONCE_REPLAY,      // ce nonce a-t-il déjà servi ?
        VERDICT_DECISION,  // le verdict approuve-t-il ?
        COMMITMENT_REPLAY, // cette action a-t-elle déjà été exécutée ?
        AGENT_ACTIVE,      // l'agent est-il actif ?
        PAYEE_ALLOWED,     // le bénéficiaire est-il permis ?
        EFFECTIVE_CAP,     // reste-t-on sous le plafond de lignée ?
        ROOM               // reste-t-il de quoi payer ?
    }

    /**
     * Quatre états, et pas trois.
     *
     * `DENY` et `STALE` sont séparés parce que leurs remèdes s'opposent : rafraîchir
     * contre arrêter. Les confondre, c'est demander à l'intégrateur de deviner.
     *
     * `NOT_APPLICABLE` n'est pas « on n'a pas demandé » : c'est « la question n'existe pas
     * à ce niveau tant qu'un autre n'a pas répondu ». Sans agent, il n'y a pas de plafond
     * à dépasser. Un contrôle qui PEUT répondre seul répond toujours, même si un autre a
     * déjà refusé.
     */
    enum Status {
        ALLOW,
        DENY,
        STALE,
        NOT_APPLICABLE
    }

    /**
     * Ce que l'intégrateur doit faire, déduit de l'ensemble des constats.
     *
     * `NOT_APPLICABLE` n'apparaît pas ici, et c'est délibéré : une question sans objet
     * n'empêche pas l'exécution. Elle informe, elle ne bloque pas. Le confondre avec un
     * blocage était un défaut de la première version, relevé par revue adverse.
     */
    enum Remedy {
        NONE,    // rien ne s'oppose
        REFRESH, // rien n'est refusé, une preuve a seulement vieilli
        STOP     // au moins un refus réel : rafraîchir n'y changera rien
    }

    struct Finding {
        Check check;
        Status status;
        uint64 asOf;       // l'instant où CETTE réponse est établie
        uint64 validUntil; // jusqu'à quand elle vaut ; 0 = pas de péremption connue
    }

    IMandateGateV3Reader public immutable gate;
    IMandateReader public immutable mandate;

    constructor(IMandateGateV3Reader _gate) {
        gate = _gate;
        mandate = IMandateReader(_gate.mandate());
    }

    /**
     * Le compte rendu complet. Onze constats, toujours onze, quel que soit le résultat.
     *
     * Un `ALLOW` ici ne dit pas « ce sera permis ». Il dit « ce niveau permet, à cet
     * instant, dans son périmètre ». La permission composée ne tient que tant que TOUS
     * les constats datés sont simultanément valables — voir `composedValidUntil`.
     */
    function record(IMandateGateV3Reader.Action calldata a, IMandateGateV3Reader.Verdict calldata v)
        public
        view
        returns (Finding[] memory f)
    {
        f = new Finding[](11);
        uint64 nowTs = uint64(block.timestamp);
        bytes32 c = gate.commit(a);

        // --- ce que le verdict dit de lui-même : tout est répondable seul ---

        f[0] = Finding(Check.BINDING, v.artifactHash == c ? Status.ALLOW : Status.DENY, nowTs, 0);

        // Le SEUL contrôle qui porte une date de péremption dans la V3. Dépassé, il n'est
        // pas un refus : la preuve a vieilli, elle se rafraîchit.
        f[1] = Finding(
            Check.FRESHNESS,
            block.timestamp <= v.expiry ? Status.ALLOW : Status.STALE,
            nowTs,
            v.expiry
        );

        address signer = gate.recoverIssuer(v);
        f[2] = Finding(
            Check.SIGNATURE,
            (signer == v.issuer && v.issuer != address(0)) ? Status.ALLOW : Status.DENY,
            nowTs,
            0
        );

        // Répondable même si la signature est fausse : on interroge le registre sur
        // l'émetteur DÉCLARÉ. C'est précisément la distinction que la V3 protège en
        // plaçant signature avant autorité.
        f[3] = Finding(
            Check.ISSUER_AUTHORITY,
            gate.authorizedIssuers(v.issuer) ? Status.ALLOW : Status.DENY,
            nowTs,
            0
        );

        f[4] = Finding(
            Check.NONCE_REPLAY,
            gate.usedNonce(v.issuer, v.nonce) ? Status.DENY : Status.ALLOW,
            nowTs,
            0
        );

        f[5] = Finding(Check.VERDICT_DECISION, v.approve ? Status.ALLOW : Status.DENY, nowTs, 0);

        f[6] = Finding(
            Check.COMMITMENT_REPLAY,
            gate.usedCommitment(c) ? Status.DENY : Status.ALLOW,
            nowTs,
            0
        );

        // --- ce que le mandat dit ---
        //
        // CORRECTION APRÈS REVUE ADVERSE. La première version décidait `NOT_APPLICABLE`
        // sur ces quatre lignes dès que `ownerOf(agentId) == 0`. C'était FAUX : `execute`
        // n'interroge jamais `ownerOf`, et `isActive` du mandat de référence remonte la
        // lignée sans rien trouver de gelé — elle répond donc VRAI sur un agent qui
        // n'existe pas. Le banc différentiel l'a montré en une ligne : la porte
        // aboutissait, le lecteur refusait. Un lecteur qui invente un contrôle absent de
        // la porte ne rend pas compte, il légifère.

        f[7] = Finding(
            Check.AGENT_ACTIVE,
            mandate.isActive(a.agentId) ? Status.ALLOW : Status.DENY,
            nowTs,
            0
        );

        f[8] = Finding(
            Check.PAYEE_ALLOWED,
            mandate.payeeAllowed(a.agentId, a.payee) ? Status.ALLOW : Status.DENY,
            nowTs,
            0
        );

        // Le SEUL « sans objet » qui existe réellement dans cette porte : si aucun
        // ancêtre n'a déclaré de plafond, `effectiveCap` vaut le maximum d'un uint256.
        // « Dépasse-t-on le plafond ? » n'a alors pas de réponse — il n'y a pas de
        // plafond. Ce n'est pas un refus, et ça n'empêche rien.
        //
        // La comparaison est écrite sans addition : `spent + amount` déborde et fait
        // PANIQUER le contrat au lieu de rendre un constat. `execute` panique aussi, mais
        // lui ne promet pas onze constats — nous si.
        uint256 sp = gate.spent(a.agentId);
        uint256 cap = gate.effectiveCap(a.agentId);
        if (cap == type(uint256).max) {
            f[9] = Finding(Check.EFFECTIVE_CAP, Status.NOT_APPLICABLE, nowTs, 0);
        } else {
            bool overCap = sp > cap || a.amount > cap - sp;
            f[9] = Finding(Check.EFFECTIVE_CAP, overCap ? Status.DENY : Status.ALLOW, nowTs, 0);
        }

        f[10] = Finding(
            Check.ROOM,
            a.amount <= gate.room(a.agentId) ? Status.ALLOW : Status.DENY,
            nowTs,
            0
        );
    }

    /**
     * Le remède, déduit du compte rendu entier.
     *
     * `STOP` prime sur `REFRESH` : rafraîchir une preuve périmée ne lèvera pas un refus
     * réel. C'est tout l'intérêt de les avoir séparés — l'ordre des remèdes n'est pas
     * l'ordre des contrôles.
     */
    function verdictOf(IMandateGateV3Reader.Action calldata a, IMandateGateV3Reader.Verdict calldata v)
        external
        view
        returns (bool allowed, Remedy remedy, uint8 denials, uint8 stales, uint8 notApplicable)
    {
        Finding[] memory f = record(a, v);
        for (uint256 i = 0; i < f.length; i++) {
            if (f[i].status == Status.DENY) denials++;
            else if (f[i].status == Status.STALE) stales++;
            else if (f[i].status == Status.NOT_APPLICABLE) notApplicable++;
        }
        // `notApplicable` est compté et rendu, mais ne pèse PAS sur l'issue : une question
        // sans objet n'a jamais empêché la porte de laisser passer.
        allowed = (denials == 0 && stales == 0);
        if (denials > 0) remedy = Remedy.STOP;
        else if (stales > 0) remedy = Remedy.REFRESH;
        else remedy = Remedy.NONE;
    }

    /**
     * Jusqu'à quand la permission COMPOSÉE tient.
     *
     * Un accord n'est pas permanent, il est daté. La composition ne vaut que tant que
     * toutes ses parties sont simultanément fraîches : le minimum des péremptions connues.
     * `0` signifie qu'aucun constat ne porte de date — ce qui ne veut pas dire « pour
     * toujours », mais « aucune péremption n'est déclarée à ce niveau ».
     */
    function composedValidUntil(IMandateGateV3Reader.Action calldata a, IMandateGateV3Reader.Verdict calldata v)
        external
        view
        returns (uint64 validUntil)
    {
        Finding[] memory f = record(a, v);
        for (uint256 i = 0; i < f.length; i++) {
            uint64 u = f[i].validUntil;
            if (u == 0) continue;
            if (validUntil == 0 || u < validUntil) validUntil = u;
        }
    }
}
