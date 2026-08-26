// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * InheritableAgentMandateV5 — implémentation de référence conforme.
 *
 * NON DÉPLOYÉE. V1, V2 et V3 restent en chaîne et leurs sources ne bougent pas.
 *
 * Trois écarts avec V3, chacun motivé sur le fil ERC-8370 :
 *
 *   1. `isActive` refuse un identifiant inconnu. Le texte de l'ERC l'exigeait déjà
 *      (« MUST reject unknown ids »), V3 répondait `true` faute de vérifier l'existence.
 *
 *   2. `frozen` sort de `mandateRoot`. Le gel est une réponse de confinement,
 *      POSTÉRIEURE à l'écriture — pas une clause. L'y inclure faisait qu'un gel
 *      changeait l'identité et détachait toute enveloppe ERC-8312 épinglée sur la
 *      racine. La non-arrachabilité reste portée par le plafond, le bail, le télomère
 *      et les périodes, qu'aucun agent ne peut réécrire.
 *
 *   3. Le bail devient un BAIL SCELLÉ, forme proposée par zexoverz (#42). Au lieu
 *      d'une échéance courante gravée dans l'identité, on grave `periodStart`,
 *      `periodLength` et `periodCount` — donc le PLAFOND ABSOLU. Le compteur de
 *      périodes payées vit hors de la racine. Renouveler consomme du mou déjà
 *      accordé et ne touche jamais l'identité.
 *
 *      « Payer un loyer mensuel sur un bail de trois ans signé au départ » devient
 *      vrai au niveau du hash, plus seulement dans la prose.
 *
 * Contrat de référence : minimal et lisible, NON AUDITÉ.
 */
contract InheritableAgentMandateV5 {
    struct Mandate {
        uint256 maxSpendWei;   // plafond de dépense
        uint64  periodStart;   // début du bail ; 0 = pas de bail, donc pas d'expiration
        uint32  periodLength;  // durée d'une période, en secondes
        uint16  periodCount;   // nombre de périodes accordées AU DÉPART — le plafond absolu
        uint16  telomere;      // générations restantes (ne fait que descendre)
        bool    requireLease;  // dead-man's switch obligatoire
        bool    frozen;        // kill switch (cascade aux descendants) — HORS de la racine
    }

    address public immutable guardian;
    uint256 public nextId = 1;

    mapping(uint256 => address) public ownerOf;
    mapping(uint256 => uint256) public parentOf;
    mapping(uint256 => Mandate) public mandateOf;
    mapping(uint256 => mapping(address => bool)) public payeeAllowed;
    mapping(uint256 => uint256) public allocatedOf;

    /// Périodes déjà payées. Vit HORS de `mandateRoot` : renouveler ne change pas l'identité.
    mapping(uint256 => uint16) public periodsUsed;

    event Minted(uint256 indexed id, address owner);
    event Spawned(uint256 indexed childId, uint256 indexed parentId);
    event Frozen(uint256 indexed id);
    event Renewed(uint256 indexed id, uint16 periodsUsed, uint64 newExpiry);

    modifier onlyGuardian() {
        require(msg.sender == guardian, "not guardian");
        _;
    }

    constructor(address _guardian) {
        guardian = _guardian;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  EXISTENCE — la garde que V3 n'avait pas
    // ─────────────────────────────────────────────────────────────────────────

    function exists(uint256 id) public view returns (bool) {
        return ownerOf[id] != address(0);
    }

    /// @notice Valide un bail à la création. Refuse les baux dégénérés et ceux qui
    ///         déborderaient `uint64` — un débordement ferait révéler `isActive` en
    ///         permanence, donc bloquerait l'agent et toute sa descendance.
    function _checkLease(Mandate calldata m) internal pure returns (uint64 end) {
        if (m.periodStart == 0) return 0;
        require(m.periodLength != 0 && m.periodCount != 0, "degenerate lease");
        uint256 e = uint256(m.periodStart) + uint256(m.periodLength) * uint256(m.periodCount);
        require(e <= type(uint64).max, "lease overflows uint64");
        return uint64(e);
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  BAIL SCELLÉ — le plafond est dans l'identité, la position n'y est pas
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Fin absolue, gravée à la naissance. Ne bouge JAMAIS.
    function absoluteEnd(uint256 id) public view returns (uint64) {
        Mandate storage m = mandateOf[id];
        if (m.periodStart == 0) return 0; // pas de bail = pas d'expiration
        return m.periodStart + uint64(m.periodLength) * uint64(m.periodCount);
    }

    /// @dev    Calcul TOTAL de l'échéance courante. Ne révèle jamais : rend `ok = false`
    ///         si l'arithmétique déborderait. Voir la note de totalité sur `isActive`.
    function _expiry(uint256 id) internal view returns (uint64 exp, bool ok) {
        Mandate storage m = mandateOf[id];
        if (m.periodStart == 0) return (0, true);          // pas de bail
        unchecked {
            uint256 e = uint256(m.periodStart)
                      + uint256(m.periodLength) * uint256(periodsUsed[id]);
            if (e > type(uint64).max) return (0, false);
            return (uint64(e), true);
        }
    }

    /// @notice Échéance courante, DÉRIVÉE du compteur. Toujours <= `absoluteEnd`.
    function currentExpiry(uint256 id) public view returns (uint64) {
        (uint64 e, ) = _expiry(id);
        return e;
    }

    /// @notice Échéance EFFECTIVE : le minimum sur l'agent et TOUS ses ancêtres.
    /// @dev    C'est la quantité qui gouverne la vivacité, pas l'échéance propre. Une fois
    ///         que la lecture remonte la chaîne, l'échéance d'un nœud ne décide plus s'il est
    ///         vivant — ses ancêtres le décident, à chaque lecture. Maintenir vivant un agent
    ///         de profondeur d est une opération à d parties, et celui qui paie la période
    ///         d'un nœud n'est pas celui qui peut le garder utilisable.
    ///         Rend 0 si aucun bail n'existe sur la chaîne. Total : ne révèle jamais.
    function effectiveExpiry(uint256 id) public view returns (uint64) {
        uint64 best = 0; // 0 = aucun bail rencontré
        uint256 cur = id;
        while (cur != 0) {
            (uint64 e, bool ok) = _expiry(cur);
            if (!ok) return 1; // valeur impossible : traitée comme expirée depuis toujours
            if (e != 0 && (best == 0 || e < best)) best = e;
            cur = parentOf[cur];
        }
        return best;
    }

    /// @notice Renouveler = consommer une période déjà accordée. Ne repousse rien.
    /// @dev    Exige que le PARENT soit actif à l'instant du renouvellement. C'est ce qui
    ///         borne la fenêtre de survie d'un descendant à une période, et c'est la
    ///         condition sous laquelle la lecture locale de l'expiration reste valide.
    function renew(uint256 id) external onlyGuardian {
        require(exists(id), "unknown id");
        Mandate storage m = mandateOf[id];
        require(m.periodStart != 0, "no lease to renew");
        require(periodsUsed[id] < m.periodCount, "lease ceiling reached");

        // Couvre le gel, l'expiration et TOUTE la chaîne d'ancêtres. Un bail se paie
        // AVANT qu'il ne lapse : un agent expiré ne se ressuscite pas.
        require(isActive(id), "agent not active");

        periodsUsed[id] += 1;
        emit Renewed(id, periodsUsed[id], currentExpiry(id));
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  NAISSANCE ET REPRODUCTION
    // ─────────────────────────────────────────────────────────────────────────

    function mint(address owner, Mandate calldata m, address[] calldata payees)
        external
        onlyGuardian
        returns (uint256 id)
    {
        require(owner != address(0), "owner is zero");
        _checkLease(m);
        id = nextId++;
        ownerOf[id] = owner;
        mandateOf[id] = m;
        periodsUsed[id] = 1; // la première période est acquise à la naissance
        for (uint256 i; i < payees.length; i++) payeeAllowed[id][payees[i]] = true;
        emit Minted(id, owner);
    }

    function spawn(
        uint256 parentId,
        address childOwner,
        Mandate calldata cm,
        address[] calldata childPayees
    ) external returns (uint256 childId) {
        require(exists(parentId), "no such parent");
        require(childOwner != address(0), "child owner is zero");
        require(msg.sender == ownerOf[parentId] || msg.sender == guardian, "not authorized");
        // Un parent expiré ou gelé n'engendre plus. Sans cette garde, V3 laissait un
        // parent mort consommer son budget au profit d'un enfant mort-né.
        require(isActive(parentId), "parent not active");

        Mandate memory pm = mandateOf[parentId];
        require(!pm.frozen, "parent frozen");
        require(pm.telomere >= 1, "telomere exhausted");

        require(cm.telomere == pm.telomere - 1, "telomere must be parent-1");
        uint256 available = pm.maxSpendWei - allocatedOf[parentId];
        require(cm.maxSpendWei <= available, "conservation: exceeds parent unallocated budget");
        require(!pm.requireLease || cm.requireLease, "cannot disable inherited lease");

        // --- bail ---
        // Le bail de l'enfant est validé INCONDITIONNELLEMENT. Le faire dépendre du bail
        // du parent laissait naître, sous un parent sans bail, un enfant dont l'échéance
        // courante dépassait sa propre fin absolue dès la naissance.
        uint64 childEnd = _checkLease(cm);

        if (pm.periodStart != 0) {
            require(cm.periodStart != 0, "cannot disable inherited lease window");
            uint64 parentEnd = pm.periodStart + uint64(pm.periodLength) * uint64(pm.periodCount);
            require(childEnd <= parentEnd, "child lease outlives parent ceiling");
            require(cm.periodStart >= pm.periodStart, "child lease starts before parent");
        }
        // NOTE : aucune contrainte de direction sur `periodLength` seul. Une période plus
        // courte resserre le défaut ET affine le levier du gardien — les deux sens ne
        // coïncident pas, donc `enfant ⊆ parent` ne dit pas lequel s'applique. Question
        // ouverte, signalée par zexoverz (#42), volontairement non tranchée ici.

        for (uint256 i; i < childPayees.length; i++) {
            require(payeeAllowed[parentId][childPayees[i]], "payee not in parent allowlist");
        }

        allocatedOf[parentId] += cm.maxSpendWei;

        childId = nextId++;
        ownerOf[childId] = childOwner;
        parentOf[childId] = parentId;
        mandateOf[childId] = cm;
        periodsUsed[childId] = 1;
        for (uint256 i; i < childPayees.length; i++) payeeAllowed[childId][childPayees[i]] = true;
        emit Spawned(childId, parentId);
    }

    function availableBudget(uint256 id) public view returns (uint256) {
        return mandateOf[id].maxSpendWei - allocatedOf[id];
    }

    function freeze(uint256 id) external onlyGuardian {
        require(exists(id), "unknown id");
        mandateOf[id].frozen = true;
        emit Frozen(id);
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  ÉTAT
    // ─────────────────────────────────────────────────────────────────────────

    /// @notice Actif ssi l'agent EXISTE, qu'aucun ancêtre n'est gelé, et que le bail de
    ///         CHAQUE ancêtre a commencé et n'a pas expiré.
    /// @dev    L'expiration remonte la chaîne, contrairement à V3. La lecture locale n'était
    ///         valide que parce que l'échéance était FIGÉE à la naissance et ordonnée par
    ///         `spawn`. Ici l'échéance courante est dérivée d'un compteur, donc dynamique :
    ///         `spawn` n'ordonne plus que les fins ABSOLUES, pas les échéances courantes.
    ///         Un parent qui cesse de renouveler expire tôt alors que son enfant court
    ///         jusqu'à sa propre échéance — mesuré à 150 jours de survie sur des périodes
    ///         désalignées. Le coût est O(profondeur) ; c'est le prix du renouvellement.
    /// @dev    TOTALITÉ — cette fonction NE RÉVÈLE JAMAIS. Elle rend `false` quand elle ne
    ///         peut pas établir la vivacité. Exigence d'interface, pas de chemin arithmétique :
    ///         dès que chaque lecture remonte la chaîne, une seule valeur détenue par un
    ///         ancêtre décide du sort de tous ses descendants, et celui qui l'a écrite n'est
    ///         pas celui qui perd. Un consommateur qui lit à l'instant de consommer n'a aucune
    ///         réponse correcte face à un revert. Un contrôle de bornes ferme un chemin ; la
    ///         totalité ferme la classe, y compris le prochain champ qui rejoindra la marche.
    ///         Règle dégagée avec zexoverz sur le fil.
    function isActive(uint256 id) public view returns (bool) {
        if (!exists(id)) return false;

        uint256 cur = id;
        while (cur != 0) {
            Mandate storage m = mandateOf[cur];
            if (m.frozen) return false;
            if (m.periodStart != 0) {
                if (block.timestamp < m.periodStart) return false;   // bail pas commencé
                (uint64 e, bool ok) = _expiry(cur);
                if (!ok) return false;                                // TOTALITÉ : jamais de revert
                if (block.timestamp > e) return false;                // bail expiré
            }
            cur = parentOf[cur];
        }
        return true;
    }

    /// @notice Hash d'identité des CLAUSES. `frozen` et `periodsUsed` en sont exclus :
    ///         l'un est une réponse de confinement, l'autre une position sous un plafond.
    ///         Ni l'un ni l'autre n'est une clause que l'agent pourrait arracher.
    function mandateRoot(uint256 id) public view returns (bytes32) {
        Mandate storage m = mandateOf[id];
        return keccak256(
            abi.encode(
                address(this),
                id,
                m.maxSpendWei,
                m.periodStart,
                m.periodLength,
                m.periodCount,
                m.telomere,
                m.requireLease
            )
        );
    }

    // Volontairement : PAS de transfer/approve. L'identité est soulbound.
}
