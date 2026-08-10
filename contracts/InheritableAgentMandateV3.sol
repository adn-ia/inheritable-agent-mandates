// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title InheritableAgentMandateV3 — V2 + l'invariant de conservation du budget
 * @notice Même dispositif que `InheritableAgentMandate` (v1, déployé et inchangé), avec
 *         la clause d'expiration que le white paper liste et que v1 n'avait pas : le bail
 *         y est un booléen, sans échéance.
 *
 *         Différences avec v1, et rien d'autre :
 *         1. `Mandate.validUntil` (uint64, secondes unix ; `0` = pas d'expiration) ;
 *         2. au `spawn`, `validUntil` est monotone en treillis — si le parent est borné,
 *            l'enfant doit l'être aussi et pas plus tard. Repasser à `0` (illimité) sous un
 *            parent borné est un élargissement, donc refusé ;
 *         3. `isActive` refuse un nœud dont le `validUntil` est dépassé. Le check est
 *            LOCAL, sans marche d'ancêtres (voir le @dev de `isActive`) ;
 *         4. `mandateRoot` — le hash d'identité des clauses — inclut `validUntil`, donc
 *            modifier l'échéance change la racine.
 *
 *         AJOUT DE LA V3 — conservation. `enfant <= parent` seul laissait passer une
 *         évasion par FAN-OUT : dix enfants à 100 % du plafond parent chacun font 1000 %.
 *         Le contrat comptabilise désormais ce qu'un parent a déjà distribué
 *         (`allocatedOf`) et refuse tout enfant qui dépasserait le reste. L'ancienne
 *         garde en est subsumée : sans rien d'alloué, le reste vaut le plafond parent.
 *
 *         Le télomère, le bail booléen et la marche non bornée du gel restent tels quels.
 *
 *         Contrat de référence : minimal et lisible, non audité, testnet uniquement.
 */
contract InheritableAgentMandateV3 {
    struct Mandate {
        uint256 maxSpendWei;  // plafond de dépense
        uint64  validUntil;   // horodatage d'expiration ; 0 = pas d'expiration
        uint16  telomere;     // générations restantes (ne fait que descendre)
        bool    requireLease; // dead-man's switch obligatoire
        bool    frozen;       // kill switch (cascade aux descendants)
    }

    address public immutable guardian;
    uint256 public nextId = 1;

    mapping(uint256 => address) public ownerOf;   // agentId -> propriétaire (non transférable)
    mapping(uint256 => uint256) public parentOf;  // agentId -> parent (0 = racine)
    mapping(uint256 => Mandate) public mandateOf;
    mapping(uint256 => mapping(address => bool)) public payeeAllowed;
    /// Somme des plafonds déjà attribués aux enfants d'un agent.
    mapping(uint256 => uint256) public allocatedOf;

    event Minted(uint256 indexed id, address owner);
    event Spawned(uint256 indexed childId, uint256 indexed parentId);
    event Frozen(uint256 indexed id);

    modifier onlyGuardian() {
        require(msg.sender == guardian, "not guardian");
        _;
    }

    constructor(address _guardian) {
        guardian = _guardian;
    }

    /// @notice Fait naître un organisme-racine avec son mandat.
    function mint(address owner, Mandate calldata m, address[] calldata payees)
        external
        onlyGuardian
        returns (uint256 id)
    {
        id = nextId++;
        ownerOf[id] = owner;
        mandateOf[id] = m;
        for (uint256 i; i < payees.length; i++) payeeAllowed[id][payees[i]] = true;
        emit Minted(id, owner);
    }

    /// @notice Spawn d'un enfant. Le cœur du dispositif : enfant ⊆ parent, imposé on-chain.
    function spawn(
        uint256 parentId,
        address childOwner,
        Mandate calldata cm,
        address[] calldata childPayees
    ) external returns (uint256 childId) {
        require(ownerOf[parentId] != address(0), "no such parent");
        require(msg.sender == ownerOf[parentId] || msg.sender == guardian, "not authorized");

        Mandate memory pm = mandateOf[parentId];
        require(!pm.frozen, "parent frozen");
        require(pm.telomere >= 1, "telomere exhausted");

        // --- non-arrachabilité, vérifiée par le protocole lui-meme ---
        require(cm.telomere == pm.telomere - 1, "telomere must be parent-1");
        uint256 available = pm.maxSpendWei - allocatedOf[parentId];
        require(cm.maxSpendWei <= available, "conservation: exceeds parent unallocated budget");
        require(!pm.requireLease || cm.requireLease, "cannot disable inherited lease");
        // validUntil, en treillis : 0 = pas d'expiration, donc l'element le plus large.
        // Si le parent est borne, l'enfant ne peut ni repasser a 0 ni viser plus tard.
        if (pm.validUntil != 0) {
            require(
                cm.validUntil != 0 && cm.validUntil <= pm.validUntil,
                "validUntil cannot exceed parent"
            );
        }
        for (uint256 i; i < childPayees.length; i++) {
            require(payeeAllowed[parentId][childPayees[i]], "payee not in parent allowlist");
        }

        allocatedOf[parentId] += cm.maxSpendWei;

        childId = nextId++;
        ownerOf[childId] = childOwner;
        parentOf[childId] = parentId;
        mandateOf[childId] = cm;
        for (uint256 i; i < childPayees.length; i++) payeeAllowed[childId][childPayees[i]] = true;
        emit Spawned(childId, parentId);
    }

    /// @notice Ce qu'il reste à distribuer : plafond propre moins ce qui est déjà attribué.
    function availableBudget(uint256 id) public view returns (uint256) {
        return mandateOf[id].maxSpendWei - allocatedOf[id];
    }

    /// @notice Kill switch. Geler un parent gèle tout son sous-arbre (voir isActive).
    function freeze(uint256 id) external onlyGuardian {
        mandateOf[id].frozen = true;
        emit Frozen(id);
    }

    /// @notice Un agent n'est actif que si lui ET tous ses ancêtres sont non gelés,
    ///         et si son propre `validUntil` n'est pas dépassé.
    /// @dev    L'expiration est vérifiée LOCALEMENT, sans marche d'ancêtres : `spawn`
    ///         impose `enfant <= parent`, donc par transitivité un nœud expire toujours
    ///         avant ou en même temps que chacun de ses ancêtres. Un ancêtre expiré
    ///         implique donc que le nœud l'est déjà — le lire n'ajoute rien.
    ///         Le gel, lui, est POSTÉRIEUR à l'écriture : aucune information locale ne le
    ///         résume, il garde donc sa marche non bornée. C'est la même loi que celle
    ///         dégagée sur la révocation : une clause statique imposée à l'écriture se
    ///         résume localement, un événement dynamique non.
    function isActive(uint256 id) public view returns (bool) {
        uint64 vu = mandateOf[id].validUntil;
        if (vu != 0 && block.timestamp > vu) return false;

        uint256 cur = id;
        while (cur != 0) {
            if (mandateOf[cur].frozen) return false;
            cur = parentOf[cur];
        }
        return true;
    }

    /// @notice Hash d'identité des clauses d'un agent — `validUntil` inclus.
    /// @dev    Sert de `capabilityRoot` quand on adosse une enveloppe ERC-8312 à ce
    ///         mandat. Inclure `validUntil` est ce qui rend l'échéance non-arrachable au
    ///         niveau du hash : la retirer ou la repousser donne une AUTRE racine, donc
    ///         ne peut pas se faire passer pour le même mandat.
    function mandateRoot(uint256 id) public view returns (bytes32) {
        Mandate storage m = mandateOf[id];
        return keccak256(
            abi.encode(
                address(this), id, m.maxSpendWei, m.validUntil, m.telomere, m.requireLease, m.frozen
            )
        );
    }

    // Volontairement : PAS de fonction transfer/approve. L'identité est liée à la lignée
    // (soulbound). C'est ce qui empêche de contourner les clauses par un transfert.
}
