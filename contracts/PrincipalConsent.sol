// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MandateDecisionRecord, IMandateGateV3Reader} from "./MandateDecisionRecord.sol";

/**
 * @title PrincipalConsent — la feuille de couverture, pas une ligne de plus
 * @notice Le donneur d'ordre est une partie, et il n'avait aucune case.
 *
 *         LE PROBLÈME.
 *
 *         Les onze contrôles de la porte peuvent tous être verts, et l'action ne devoir
 *         quand même pas se faire — parce que celui à qui appartient l'argent a retiré son
 *         accord, ou parce qu'il exige qu'on revérifie maintenant au lieu de réutiliser un
 *         accord ancien. Ni l'un ni l'autre n'est un refus technique : aucune couche ne
 *         refuse. Et ni l'un ni l'autre n'est représentable dans un constat par couche.
 *
 *         POURQUOI UNE FEUILLE SÉPARÉE, ET PAS UN SIXIÈME ÉTAT.
 *
 *         Parce que les remèdes diffèrent, ce qui est le critère retenu partout ailleurs
 *         ici. Si un contrôle refuse, on répare quelque chose. Si le donneur d'ordre retire
 *         son accord, il n'y a RIEN à réparer : on s'arrête et on va lui parler. Ranger ces
 *         deux choses dans la même liste refait, un étage au-dessus, exactement l'écrasement
 *         qu'on reproche à l'étage du dessous.
 *
 *         Le consentement n'est donc pas un avis sur l'action. C'est ce qui donne le droit
 *         de poser la question. Sans lui, on n'ouvre pas la feuille des contrôles.
 *
 *         ⚠️ CE QUE CE CONTRAT N'EST PAS.
 *
 *         `MandateGateV3` DÉPLOYÉE N'APPLIQUE PAS LE CONSENTEMENT. Elle ne le connaît pas.
 *         Un retrait d'accord n'empêchera donc pas `execute` d'aboutir. Ce contrat décrit ce
 *         qu'une porte consciente du consentement répondrait ; il ne le fait pas respecter.
 *
 *         C'est dit franchement parce que la première version du compte rendu s'est trompée
 *         exactement là : elle bloquait ce que la porte laissait passer. L'invariant
 *         différentiel — le compte rendu permet si et seulement si la porte aboutit — porte
 *         sur les ONZE contrôles de la porte, et sur eux seuls. Le consentement est rendu à
 *         part, jamais mélangé au décompte.
 *
 *         L'HÉRITAGE.
 *
 *         Le retrait cascade sur le sous-arbre, exactement comme le gel dans
 *         `InheritableAgentMandate.isActive` : on remonte la lignée, et si un ancêtre a
 *         retiré son accord, aucun descendant n'en a. On reprend l'idiome existant plutôt
 *         que d'en inventer un.
 *
 *         Démonstrateur non audité, testnet uniquement.
 */

interface IMandateLineage {
    function ownerOf(uint256 agentId) external view returns (address);
    function parentOf(uint256 agentId) external view returns (uint256);
}

contract PrincipalConsent {
    /**
     * Trois états, et ils viennent des deux phrases du donneur d'ordre.
     *
     * `WITHDRAWN`        — « je ne veux plus ». Rien à réparer, on s'arrête.
     * `RECHECK_REQUIRED` — « je veux un second avis ». CORRIGÉ LE 19/08 après Helmy :
     *                      demander un second avis, ce n'est pas relire l'ancien dossier
     *                      plus attentivement — c'est SORTIR DE L'HÔPITAL ET APPELER UN
     *                      AUTRE CHIRURGIEN. Le dossier en cours est clos, rien ne se
     *                      poursuit sur l'ancienne preuve, et un nouveau processus démarre.
     *                      Cet état BLOQUE donc la consultation, et se lève quand le donneur
     *                      d'ordre réaffirme (`affirm`) — c'est-à-dire quand il a eu son
     *                      second avis et s'en satisfait.
     *
     *                      La première version se contentait d'un drapeau comparant la
     *                      demande à `v.expiry`. Elle ne prouvait RIEN : `expiry` est une
     *                      date de mort, pas de naissance, et le format du verdict ne porte
     *                      aucune date d'émission. Revue adverse confirmée. Le drapeau est
     *                      supprimé au lieu d'être maquillé.
     * `GRANTED`          — rien ne s'oppose du côté du donneur d'ordre.
     *
     * ⚠️ LES DEUX SUIVANTS ONT ÉTÉ AJOUTÉS LE 19/08 APRÈS UNE QUESTION DE HELMY.
     *
     * « Si l'anesthésiste, le chirurgien et la mutuelle sont d'accord, mais que le patient
     * est mort entre-temps — il ne peut pas s'opposer, mais il ne peut pas consentir non
     * plus. Il se passe quoi ? »
     *
     * La première version répondait `GRANTED`. Elle traitait l'ABSENCE DE REFUS comme un
     * ACCORD : le silence valait oui. C'est la faute même que ce dispositif existe pour
     * combattre, refaite un étage plus haut. Constaté en chaîne sur l'agent 999999, sans
     * propriétaire : la feuille s'ouvrait et les onze contrôles étaient évalués.
     *
     * `NO_PRINCIPAL` — il n'y a PERSONNE qui puisse consentir (`ownerOf == 0`). Ce n'est pas
     *                  un refus. Le remède n'est pas « s'arrêter et lui parler » — il n'y a
     *                  personne à qui parler. C'est une ESCALADE : succession, tuteur, gel.
     * `UNCONFIRMED`  — le donneur d'ordre existe, mais il n'a pas réaffirmé son accord dans
     *                  le délai exigé. Un accord donné une fois et jamais renouvelé n'est pas
     *                  un accord éternel. C'est le principe déjà retenu partout ici — une
     *                  permission est DATÉE, pas permanente — appliqué au consentement
     *                  lui-même. Le remède est de redemander, pas d'arrêter.
     *
     * Ces deux états n'ouvrent PAS la feuille des contrôles, comme `WITHDRAWN` — mais pour
     * des raisons différentes, et avec des suites différentes. Les confondre serait
     * exactement l'écrasement qu'on reproche à la porte.
     */
    enum Consent {
        GRANTED,
        WITHDRAWN,
        RECHECK_REQUIRED,
        NO_PRINCIPAL,
        UNCONFIRMED
    }

    IMandateLineage public immutable mandate;
    MandateDecisionRecord public immutable decisionRecord;

    /**
     * Le retrait porte QUI l'a prononcé, pas seulement qu'il existe.
     *
     * Sans ça, un changement de propriétaire efface le refus de l'ancien d'un simple appel :
     * le nouveau venu appelle `restore` et le refus n'a jamais existé. La norme autorise
     * explicitement une identité transférable (« if transferable… transfer MUST NOT reset or
     * clear the mandate »), donc le cas est prévu par le texte et doit l'être ici.
     *
     * Règle retenue : **celui qui a refusé peut revenir dessus librement. Un autre ne peut
     * pas** — il doit passer par `overrideWithdrawal`, un acte distinct, motivé, et tracé.
     * C'est le franchissement explicite plutôt que la continuité silencieuse.
     */
    struct Withdrawal {
        bool active;
        address by;        // le donneur d'ordre qui a prononcé le refus
        uint64 at;
    }
    mapping(uint256 => Withdrawal) public withdrawalOf;

    /// Trace d'un refus levé par quelqu'un d'autre. Jamais effacée.
    struct Override {
        bool happened;
        address previousPrincipal;
        address overriddenBy;
        bytes32 justification;
        uint64 at;
    }
    mapping(uint256 => Override) public overrideOf;
    /// Instant à partir duquel une preuve doit avoir été établie. Cascade par le maximum.
    mapping(uint256 => uint64) public freshSince;
    /// Qui a décidé, et quand — pour que le constat porte sa provenance.
    mapping(uint256 => uint64) public decidedAt;
    /// Dernière réaffirmation du donneur d'ordre : « je suis là, et je consens toujours ».
    mapping(uint256 => uint64) public lastAffirmed;
    /// Délai au-delà duquel un accord non réaffirmé n'est plus tenu pour acquis. 0 = non exigé.
    mapping(uint256 => uint64) public affirmationPeriod;

    event ConsentWithdrawn(uint256 indexed agentId, address indexed principal, uint64 at);
    event ConsentRestored(uint256 indexed agentId, address indexed principal, uint64 at);
    event WithdrawalOverridden(
        uint256 indexed agentId,
        address indexed previousPrincipal,
        address indexed overriddenBy,
        bytes32 justification,
        uint64 at
    );
    event RecheckRequired(uint256 indexed agentId, address indexed principal, uint64 freshSince);
    event ConsentAffirmed(uint256 indexed agentId, address indexed principal, uint64 at);
    event AffirmationPeriodSet(uint256 indexed agentId, uint64 period);

    constructor(MandateDecisionRecord _record) {
        decisionRecord = _record;
        mandate = IMandateLineage(address(_record.mandate()));
    }

    /// Le donneur d'ordre est LU dans le mandat, jamais fourni par l'appelant.
    modifier onlyPrincipal(uint256 agentId) {
        require(msg.sender == mandate.ownerOf(agentId), "not the principal");
        _;
    }

    /// « Je ne veux plus. » Cascade sur tout le sous-arbre.
    function withdraw(uint256 agentId) external onlyPrincipal(agentId) {
        withdrawalOf[agentId] = Withdrawal({active: true, by: msg.sender, at: uint64(block.timestamp)});
        decidedAt[agentId] = uint64(block.timestamp);
        emit ConsentWithdrawn(agentId, msg.sender, uint64(block.timestamp));
    }

    /// Revenir sur SON PROPRE refus. Celui qui a refusé, et lui seul.
    function restore(uint256 agentId) external onlyPrincipal(agentId) {
        Withdrawal memory w = withdrawalOf[agentId];
        require(w.active, "no withdrawal to restore");
        require(w.by == msg.sender, "not the principal who withdrew");
        withdrawalOf[agentId].active = false;
        decidedAt[agentId] = uint64(block.timestamp);
        emit ConsentRestored(agentId, msg.sender, uint64(block.timestamp));
    }

    /**
     * Lever le refus de QUELQU'UN D'AUTRE. Réservé au donneur d'ordre en titre, et jamais
     * silencieux : une justification non nulle est obligatoire, et l'acte est conservé.
     *
     * Un `restore` ordinaire ne peut pas faire ça : hériter d'une identité ne fait pas
     * hériter du droit d'effacer le refus de son prédécesseur.
     */
    function overrideWithdrawal(uint256 agentId, bytes32 justification) external onlyPrincipal(agentId) {
        Withdrawal memory w = withdrawalOf[agentId];
        require(w.active, "no withdrawal to override");
        require(w.by != msg.sender, "your own withdrawal: use restore");
        require(justification != bytes32(0), "justification required");

        withdrawalOf[agentId].active = false;
        overrideOf[agentId] = Override({
            happened: true,
            previousPrincipal: w.by,
            overriddenBy: msg.sender,
            justification: justification,
            at: uint64(block.timestamp)
        });
        decidedAt[agentId] = uint64(block.timestamp);
        emit WithdrawalOverridden(agentId, w.by, msg.sender, justification, uint64(block.timestamp));
    }

    /**
     * « Je veux un second avis. » L'accord n'est pas retiré : on exige que la preuve soit
     * établie APRÈS cet instant. C'est le pendant, côté donneur d'ordre, de l'axe que le fil
     * ERC-8226 débat déjà — accord gardé en mémoire contre revérification en direct — mais
     * déclenché par celui à qui appartient l'argent, pas par le système.
     */
    function requireRecheck(uint256 agentId) external onlyPrincipal(agentId) {
        freshSince[agentId] = uint64(block.timestamp);
        lastAffirmed[agentId] = 0;   // le dossier est clos : il faudra réaffirmer
        emit RecheckRequired(agentId, msg.sender, uint64(block.timestamp));
    }

    /// « Je suis toujours là, et je consens toujours. » Un accord se renouvelle.
    function affirm(uint256 agentId) external onlyPrincipal(agentId) {
        lastAffirmed[agentId] = uint64(block.timestamp);
        freshSince[agentId] = 0;     // second avis obtenu, le dossier se rouvre
        emit ConsentAffirmed(agentId, msg.sender, uint64(block.timestamp));
    }

    /// Au-delà de ce délai sans réaffirmation, l'accord n'est plus tenu pour acquis.
    function setAffirmationPeriod(uint256 agentId, uint64 period) external onlyPrincipal(agentId) {
        affirmationPeriod[agentId] = period;
        if (lastAffirmed[agentId] == 0) lastAffirmed[agentId] = uint64(block.timestamp);
        emit AffirmationPeriodSet(agentId, period);
    }

    /// Remonte la lignée, comme le gel. Un ancêtre qui retire ferme tout son sous-arbre.
    function consentOf(uint256 agentId)
        public
        view
        returns (Consent state, uint64 effectiveFreshSince, uint256 decidedBy)
    {
        // AVANT TOUT : quelqu'un peut-il seulement consentir ? Sans propriétaire, la
        // question n'a pas de titulaire. Ce n'est ni un accord, ni un refus.
        if (mandate.ownerOf(agentId) == address(0)) {
            return (Consent.NO_PRINCIPAL, 0, agentId);
        }

        uint256 cur = agentId;
        while (cur != 0) {
            if (withdrawalOf[cur].active) return (Consent.WITHDRAWN, freshSince[cur], cur);
            if (freshSince[cur] > effectiveFreshSince) {
                effectiveFreshSince = freshSince[cur];
                decidedBy = cur;
            }
            cur = mandate.parentOf(cur);
        }
        // Un accord non réaffirmé dans le délai exigé n'est plus tenu pour acquis.
        uint64 period = affirmationPeriod[agentId];
        if (period > 0 && block.timestamp > uint256(lastAffirmed[agentId]) + uint256(period)) {
            return (Consent.UNCONFIRMED, effectiveFreshSince, agentId);
        }

        state = effectiveFreshSince > 0 ? Consent.RECHECK_REQUIRED : Consent.GRANTED;
    }

    /// Les états qui interdisent d'ouvrir la feuille des contrôles.
    function blocksConsultation(Consent c) public pure returns (bool) {
        return c == Consent.WITHDRAWN
            || c == Consent.NO_PRINCIPAL
            || c == Consent.UNCONFIRMED
            || c == Consent.RECHECK_REQUIRED;
    }

    /**
     * LA FEUILLE DE COUVERTURE.
     *
     * Si l'accord est retiré, on N'OUVRE PAS la feuille des contrôles : le tableau rendu est
     * VIDE. Ce n'est pas onze refus, c'est l'absence de droit de poser la question.
     *
     * Si un second avis est exigé, la feuille ne s'ouvre pas non plus : on ne poursuit pas
     * sur l'ancienne preuve, on recommence. Elle se rouvre quand le donneur d'ordre
     * réaffirme, c'est-à-dire quand il a eu son second avis.
     */
    function evaluate(IMandateGateV3Reader.Action calldata a, IMandateGateV3Reader.Verdict calldata v)
        external
        view
        returns (
            Consent state,
            uint64 effectiveFreshSince,
            uint256 decidedBy,
            bool consulted,
            MandateDecisionRecord.Finding[] memory findings
        )
    {
        (state, effectiveFreshSince, decidedBy) = consentOf(a.agentId);

        if (blocksConsultation(state)) {
            return (state, effectiveFreshSince, decidedBy, false, new MandateDecisionRecord.Finding[](0));
        }

        consulted = true;
        findings = decisionRecord.record(a, v);
    }
}
