// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title InheritableAgentMandate — référence on-chain de la "3ᵉ patte"
 * @notice Ce que la recherche a montré comme NON construit à la mi-2026 :
 *         des clauses de contrôle liées à l'identité on-chain d'un agent, qui se
 *         propagent AUTOMATIQUEMENT à tout enfant au spawn et ne peuvent être ni
 *         élargies ni arrachées.
 *
 *         - Identité façon ERC-8004 (un agentId par agent), mais DÉLIBÉRÉMENT NON
 *           TRANSFÉRABLE (pas de fonction transfer) : l'identité est liée à la lignée,
 *           quasi soulbound. C'est la réponse au problème de transférabilité d'ERC-8004
 *           (agentId transférable + wallet effacé au transfert = rien ne persiste).
 *         - Clauses de style ERC-8226 (plafond, télomère, bail, gel/kill) portées PAR
 *           l'identité, et vérifiées enfant ⊆ parent AU MOMENT DU SPAWN, on-chain.
 *         - Gel (kill switch) qui cascade à toute la descendance via isActive().
 *
 *         Contrat de référence : minimal et lisible, non audité, à composer avec un
 *         mandat ERC-8226 réel pour la logique de dépense fine.
 */
contract InheritableAgentMandate {
    struct Mandate {
        uint256 maxSpendWei;  // plafond de dépense
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
        require(cm.maxSpendWei <= pm.maxSpendWei, "spend cap cannot exceed parent");
        require(!pm.requireLease || cm.requireLease, "cannot disable inherited lease");
        for (uint256 i; i < childPayees.length; i++) {
            require(payeeAllowed[parentId][childPayees[i]], "payee not in parent allowlist");
        }

        childId = nextId++;
        ownerOf[childId] = childOwner;
        parentOf[childId] = parentId;
        mandateOf[childId] = cm;
        for (uint256 i; i < childPayees.length; i++) payeeAllowed[childId][childPayees[i]] = true;
        emit Spawned(childId, parentId);
    }

    /// @notice Kill switch. Geler un parent gèle tout son sous-arbre (voir isActive).
    function freeze(uint256 id) external onlyGuardian {
        mandateOf[id].frozen = true;
        emit Frozen(id);
    }

    /// @notice Un agent n'est actif que si lui ET tous ses ancêtres sont non gelés.
    function isActive(uint256 id) public view returns (bool) {
        uint256 cur = id;
        while (cur != 0) {
            if (mandateOf[cur].frozen) return false;
            cur = parentOf[cur];
        }
        return true;
    }

    // Volontairement : PAS de fonction transfer/approve. L'identité est liée à la lignée
    // (soulbound). C'est ce qui empêche de contourner les clauses par un transfert.
}
