// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @dev ERC-165, redéclaré pour que ce fichier compile seul.
interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

/**
 * @dev Profil « lignée » d'ERC-8312 (Section 5), **redéclaré d'après sa signature
 *      publique** (dépôt `ERC8312/bounded-agent-actions`). Aucune ligne de son
 *      implémentation n'est reprise.
 *
 *      Son README gèle l'identifiant à `0xc7cabe86`. Ce contrat ne l'écrit pas en
 *      dur : il le recalcule depuis la déclaration ci-dessous.
 */
interface IAggregateBudget is IERC165 {
    event RootCreated(
        bytes32 indexed rootId, address indexed issuer, address indexed agent, uint256 cap, uint64 periodLength
    );
    event NodeDelegated(
        bytes32 indexed rootId, uint64 indexed parentId, uint64 indexed nodeId, address agent, uint256 nodeCap
    );
    event Drawn(bytes32 indexed rootId, uint64 indexed nodeId, uint64 indexed periodIndex, uint256 amount);
    event NodeRevoked(bytes32 indexed rootId, uint64 indexed nodeId);

    function createRoot(address agent, uint256 cap, uint64 periodLength, uint64 periodAnchor, bytes32 salt)
        external
        returns (bytes32 rootId);

    function delegate(bytes32 rootId, uint64 parentId, address agent, uint256 nodeCap)
        external
        returns (uint64 nodeId);

    function draw(bytes32 rootId, uint64 nodeId, uint256 amount) external;

    function revoke(bytes32 rootId, uint64 nodeId) external;

    function rootOf(bytes32 rootId)
        external
        view
        returns (address issuer, uint256 cap, uint64 periodLength, uint64 periodAnchor, uint64 nodeCount);

    function nodeOf(bytes32 rootId, uint64 nodeId)
        external
        view
        returns (uint64 parent, uint8 depth, bool revoked, address agent, uint256 nodeCap);

    function spentRoot(bytes32 rootId, uint64 periodIndex) external view returns (uint256);

    function remainingRoot(bytes32 rootId) external view returns (uint256);

    function currentPeriod(bytes32 rootId) external view returns (uint64);

    function isPathActive(bytes32 rootId, uint64 nodeId) external view returns (bool);
}

/// @dev Ce dont ce compteur a besoin du mandat. Notre contrat, notre interface.
interface IInheritableAgentMandate {
    function isActive(uint256 agentId) external view returns (bool);
    function ownerOf(uint256 agentId) external view returns (address);
}

/**
 * @title MandateAwareAggregateCursor — le profil lignée d'ERC-8312, adossé à un mandat soulbound
 *
 * @notice PROPOSITION, pas le contrat de blockbird. Le profil Section 5 porte déjà le
 *         gel (`revoke` coupe le sous-arbre) et l'atténuation (`nodeCap`). Il laisse
 *         deux choses ouvertes, que ce contrat comble :
 *
 *         1. LE PONT — rien ne relie l'état d'un mandat externe à `revoke` : « a freeze
 *            doesn't revoke a node, someone calls revoke ». Ici, `draw` et `delegate`
 *            consultent `mandate.isActive` : un mandat gelé coupe les tirages de tout
 *            le sous-arbre, sans appel manuel à `revoke`.
 *
 *         2. L'IDENTITÉ — un nœud est identifié par une `address`, qui peut changer de
 *            mains. Ici, une adresse peut être adossée à un `agentId` de notre mandat,
 *            qui n'expose aucune fonction de transfert : le lien devient soulbound.
 *
 *         La signature `address agent` est CONSERVÉE : c'est la condition pour rester
 *         conforme au profil.
 *
 *         COMPATIBILITÉ ASSUMÉE : une adresse NON adossée se comporte exactement comme
 *         dans l'implémentation de référence — aucune consultation de mandat. C'est ce
 *         qui permet à une suite de conformité écrite pour la référence de s'appliquer
 *         ici sans adaptation.
 *
 *         ILLUSTRÉ PAR CONSTRUCTION : « gel ⇒ tirage coupé » et « soulbound à la place
 *         de l'adresse » — nous écrivons ces vérifications nous-mêmes.
 *         CE QUE LE CODE PEUT RATER : la conformité et la conservation.
 *
 *         Non audité, testnet uniquement.
 */
contract MandateAwareAggregateCursor is IAggregateBudget {
    struct Root {
        address issuer;
        uint256 cap;
        uint64 periodLength;
        uint64 periodAnchor;
        uint64 nodeCount;
    }

    struct Node {
        uint64 parent;
        uint8 depth;
        bool revoked;
        address agent;
        uint256 nodeCap;
    }

    uint8 public constant MAX_DEPTH = 32;

    IInheritableAgentMandate public immutable mandate;

    mapping(bytes32 => Root) private _roots;
    mapping(bytes32 => mapping(uint64 => Node)) private _nodes;
    /// meter unique par (root, période) — la quantité conservée
    mapping(bytes32 => mapping(uint64 => uint256)) private _spentRoot;
    /// atténuation propre à un nœud plafonné
    mapping(bytes32 => mapping(uint64 => uint256)) private _spentNode;

    /// adresse ⇢ agentId du mandat, prouvé par le détenteur lui-même
    mapping(address => uint256) private _boundAgentId;

    error UnknownRoot();
    error UnknownNode();
    error ZeroAmount();
    error OnlyNodeAgent();
    error OnlyParentAgent();
    error PathRevoked();
    error CappedNodeCannotDelegate();
    error NodeCapExceeded();
    error RootCapExceeded();
    error DepthExceeded();
    error RootExists();
    error NotMandateOwner();
    /// @notice Le refus propre à ce compteur : le mandat adossé à cet agent est gelé.
    error MandateFrozen(address agent, uint256 agentId);

    event AgentBound(address indexed agent, uint256 indexed agentId);

    constructor(address mandateRegistry) {
        require(mandateRegistry != address(0), "mandate is zero");
        mandate = IInheritableAgentMandate(mandateRegistry);
    }

    // ------------------------------------------------------------------ //
    // Adossement soulbound                                               //
    // ------------------------------------------------------------------ //

    /// @notice Adosse `msg.sender` à un `agentId` du mandat. L'appelant doit être le
    ///         détenteur de cet agentId ; le mandat n'expose aucun transfert, donc ce
    ///         lien ne peut pas changer de mains.
    function bindAgent(uint256 agentId) external {
        if (mandate.ownerOf(agentId) != msg.sender) revert NotMandateOwner();
        _boundAgentId[msg.sender] = agentId;
        emit AgentBound(msg.sender, agentId);
    }

    function boundAgentId(address agent) external view returns (uint256) {
        return _boundAgentId[agent];
    }

    /// @dev Le pont. Une adresse non adossée n'est pas contrainte : le comportement
    ///      est alors celui de la référence.
    function _requireMandateActive(address agent) internal view {
        uint256 agentId = _boundAgentId[agent];
        if (agentId == 0) return;
        if (!mandate.isActive(agentId)) revert MandateFrozen(agent, agentId);
    }

    // ------------------------------------------------------------------ //
    // Construction de l'arbre                                            //
    // ------------------------------------------------------------------ //

    function computeRootId(address issuer, address agent, bytes32 salt) public view returns (bytes32) {
        return keccak256(abi.encode(address(this), issuer, agent, salt));
    }

    function createRoot(address agent, uint256 cap, uint64 periodLength, uint64 periodAnchor, bytes32 salt)
        external
        returns (bytes32 rootId)
    {
        rootId = computeRootId(msg.sender, agent, salt);
        if (_roots[rootId].issuer != address(0)) revert RootExists();

        _roots[rootId] = Root({
            issuer: msg.sender,
            cap: cap,
            periodLength: periodLength,
            periodAnchor: periodAnchor,
            nodeCount: 1
        });
        _nodes[rootId][0] = Node({parent: 0, depth: 0, revoked: false, agent: agent, nodeCap: 0});

        emit RootCreated(rootId, msg.sender, agent, cap, periodLength);
    }

    function delegate(bytes32 rootId, uint64 parentId, address agent, uint256 nodeCap)
        external
        returns (uint64 nodeId)
    {
        Root storage r = _get(rootId);
        if (parentId >= r.nodeCount) revert UnknownNode();

        Node storage p = _nodes[rootId][parentId];
        if (msg.sender != p.agent) revert OnlyParentAgent();
        if (!_pathActive(rootId, parentId)) revert PathRevoked();
        // un nœud plafonné est une feuille : il ne délègue pas
        if (p.nodeCap != 0) revert CappedNodeCannotDelegate();
        if (p.depth + 1 > MAX_DEPTH) revert DepthExceeded();

        _requireMandateActive(p.agent);

        nodeId = r.nodeCount;
        _nodes[rootId][nodeId] =
            Node({parent: parentId, depth: p.depth + 1, revoked: false, agent: agent, nodeCap: nodeCap});
        r.nodeCount = nodeId + 1;

        emit NodeDelegated(rootId, parentId, nodeId, agent, nodeCap);
    }

    // ------------------------------------------------------------------ //
    // Metering                                                           //
    // ------------------------------------------------------------------ //

    function draw(bytes32 rootId, uint64 nodeId, uint256 amount) external {
        Root storage r = _get(rootId);
        if (nodeId >= r.nodeCount) revert UnknownNode();
        if (amount == 0) revert ZeroAmount();

        Node storage n = _nodes[rootId][nodeId];
        if (msg.sender != n.agent) revert OnlyNodeAgent();
        if (!_pathActive(rootId, nodeId)) revert PathRevoked();

        // --- le pont : la décision vient du substrat, pas d'un revoke manuel ---
        _requireMandateActive(n.agent);

        if (n.nodeCap != 0) {
            if (_spentNode[rootId][nodeId] + amount > n.nodeCap) revert NodeCapExceeded();
        }

        uint64 period = _currentPeriod(r);
        // --- conservation : un seul meter, celui de la racine ---
        if (_spentRoot[rootId][period] + amount > r.cap) revert RootCapExceeded();

        _spentNode[rootId][nodeId] += amount;
        _spentRoot[rootId][period] += amount;

        emit Drawn(rootId, nodeId, period, amount);
    }

    /// @notice Révocation explicite. Coupe le nœud et tout son sous-arbre, sans
    ///         rembourser ce qui a déjà été tiré.
    function revoke(bytes32 rootId, uint64 nodeId) external {
        Root storage r = _get(rootId);
        if (nodeId >= r.nodeCount) revert UnknownNode();

        Node storage n = _nodes[rootId][nodeId];
        address parentAgent = nodeId == 0 ? r.issuer : _nodes[rootId][n.parent].agent;
        if (msg.sender != parentAgent && msg.sender != r.issuer) revert OnlyParentAgent();

        n.revoked = true;
        emit NodeRevoked(rootId, nodeId);
    }

    // ------------------------------------------------------------------ //
    // Lectures                                                           //
    // ------------------------------------------------------------------ //

    function rootOf(bytes32 rootId)
        external
        view
        returns (address issuer, uint256 cap, uint64 periodLength, uint64 periodAnchor, uint64 nodeCount)
    {
        Root storage r = _get(rootId);
        return (r.issuer, r.cap, r.periodLength, r.periodAnchor, r.nodeCount);
    }

    function nodeOf(bytes32 rootId, uint64 nodeId)
        external
        view
        returns (uint64 parent, uint8 depth, bool revoked, address agent, uint256 nodeCap)
    {
        Root storage r = _get(rootId);
        if (nodeId >= r.nodeCount) revert UnknownNode();
        Node storage n = _nodes[rootId][nodeId];
        return (n.parent, n.depth, n.revoked, n.agent, n.nodeCap);
    }

    function spentRoot(bytes32 rootId, uint64 periodIndex) external view returns (uint256) {
        _get(rootId);
        return _spentRoot[rootId][periodIndex];
    }

    function remainingRoot(bytes32 rootId) external view returns (uint256) {
        Root storage r = _get(rootId);
        uint256 s = _spentRoot[rootId][_currentPeriod(r)];
        return s >= r.cap ? 0 : r.cap - s;
    }

    function currentPeriod(bytes32 rootId) external view returns (uint64) {
        return _currentPeriod(_get(rootId));
    }

    function isPathActive(bytes32 rootId, uint64 nodeId) external view returns (bool) {
        Root storage r = _get(rootId);
        if (nodeId >= r.nodeCount) revert UnknownNode();
        return _pathActive(rootId, nodeId);
    }

    /// @notice L'identifiant N'EST PAS écrit en dur : il est recalculé depuis la
    ///         redéclaration de l'interface ci-dessus.
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IAggregateBudget).interfaceId;
    }

    // ------------------------------------------------------------------ //
    // Interne                                                            //
    // ------------------------------------------------------------------ //

    function _get(bytes32 rootId) private view returns (Root storage r) {
        r = _roots[rootId];
        if (r.issuer == address(0)) revert UnknownRoot();
    }

    function _currentPeriod(Root storage r) private view returns (uint64) {
        if (r.periodLength == 0) return 0;
        if (block.timestamp <= r.periodAnchor) return 0;
        return uint64((block.timestamp - r.periodAnchor) / r.periodLength);
    }

    function _pathActive(bytes32 rootId, uint64 nodeId) private view returns (bool) {
        uint64 cur = nodeId;
        for (uint256 i; i <= MAX_DEPTH; i++) {
            Node storage n = _nodes[rootId][cur];
            if (n.revoked) return false;
            if (cur == 0) return true;
            cur = n.parent;
        }
        return false;
    }
}
