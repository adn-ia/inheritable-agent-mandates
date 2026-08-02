// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @dev ERC-165, redéclaré ici pour que ce fichier compile seul.
interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

/**
 * @dev Interface ERC-8312 « Bounded Agent Actions », **redéclarée d'après sa signature
 *      publique** (dépôt de référence `ERC8312/bounded-agent-actions`). Aucune ligne de
 *      son implémentation n'est reprise : seules les signatures, qui sont ce qu'un
 *      standard expose.
 *
 *      L'identifiant gelé annoncé par son README est `0x3985961d`. Ce contrat ne le
 *      code pas en dur : il le **recalcule** depuis la déclaration ci-dessous. Si notre
 *      redéclaration divergeait de la sienne, ne serait-ce que d'un paramètre,
 *      `supportsInterface(0x3985961d)` rendrait `false`.
 */
interface IBoundedAgentAction is IERC165 {
    enum Status {
        None,
        Active,
        Completed,
        Contested,
        Revoked,
        Expired
    }

    struct Envelope {
        bytes32 id;
        address principal;
        bytes32 capabilityRoot;
        bytes32 cursorRoot;
        uint64 createdAt;
        uint64 expiresAt;
        Status status;
    }

    event EnvelopeRegistered(bytes32 indexed id, address indexed principal, bytes32 indexed capabilityRoot);
    event EnvelopeAdvanced(bytes32 indexed id, bytes32 prevCursor, bytes32 newCursor);
    event EnvelopeStatusChanged(bytes32 indexed id, Status fromStatus, Status toStatus);

    function registerEnvelope(address principal, bytes32 capabilityRoot, uint64 expiresAt, bytes calldata initData)
        external
        returns (bytes32 id);

    function getEnvelope(bytes32 id) external view returns (Envelope memory);

    function getCursor(bytes32 id) external view returns (bytes32);

    function getStatus(bytes32 id) external view returns (Status);

    function isActive(bytes32 id) external view returns (bool);

    function advanceCursor(bytes32 id, bytes calldata witness) external returns (bytes32 newCursor);

    function setStatus(bytes32 id, Status newStatus) external;
}

/// @dev Ce dont ce compteur a besoin du mandat. Notre contrat, notre interface.
interface IInheritableAgentMandate {
    function isActive(uint256 agentId) external view returns (bool);
    function ownerOf(uint256 agentId) external view returns (address);
    function mandateOf(uint256 agentId)
        external
        view
        returns (uint256 maxSpendWei, uint16 telomere, bool requireLease, bool frozen);
}

/**
 * @title MandateAwareCursor — un compteur ERC-8312 qui consulte le mandat avant d'avancer
 *
 * @notice PROPOSITION, pas le contrat de blockbird. ERC-8312 « meters but does not
 *         enforce » : son enveloppe ne porte aucun champ d'identité d'agent, et sous le
 *         profil Budget Substrate le `capabilityRoot` est figé à `keccak(cap, asset)` —
 *         il n'y a donc aucun crochet où accrocher un mandat.
 *
 *         Ce compteur ajoute exactement ce crochet : le `capabilityRoot` engage en plus
 *         l'adresse du registre de mandats et l'`agentId`, et `advanceCursor` refuse
 *         d'avancer quand `mandate.isActive(agentId)` est faux.
 *
 *         CE QUI EST ILLUSTRÉ PAR CONSTRUCTION : « nœud gelé → dépense arrêtée ». Nous
 *         écrivons nous-mêmes cette vérification ; le résultat est entraîné par le
 *         montage. Ce n'est pas une découverte.
 *
 *         CE QUE LE CODE PEUT RATER : rester conforme à l'interface, et compter
 *         normalement hors gel. Ces deux points-là ne sont pas gagnés d'avance.
 *
 *         Non audité, testnet uniquement.
 */
contract MandateAwareCursor is IBoundedAgentAction {
    struct Record {
        address principal;
        bytes32 capabilityRoot;
        bytes32 cursorRoot;
        uint64 createdAt;
        uint64 expiresAt;
        Status status;
        uint256 cap;
        address asset;
        uint256 spent;
        uint256 agentId; // le crochet d'identité absent de l'enveloppe d'origine
    }

    IInheritableAgentMandate public immutable mandate;

    mapping(bytes32 => Record) private _records;

    bytes32 private constant EMPTY_CURSOR = keccak256(abi.encode(uint256(0)));

    error UnknownEnvelope();
    error IdExists();
    error BadExpiry();
    error CapabilityMismatch();
    error Unauthorized();
    error NotActive();
    error BoundExceeded();
    error BadTransition();
    /// @notice Le refus propre à ce compteur : le mandat de l'agent n'est plus actif.
    error MandateInactive(uint256 agentId);
    /// @notice Le plafond demandé pour l'enveloppe dépasse celui que le mandat porte
    ///         pour cet agent. Refus écrit par nous, pas par le standard.
    error CapExceedsMandate(uint256 requested, uint256 mandateCap);

    constructor(address mandateRegistry) {
        require(mandateRegistry != address(0), "mandate is zero");
        mandate = IInheritableAgentMandate(mandateRegistry);
    }

    /// @notice Le « costume » qu'on aurait voulu à la porte : l'identité est DANS la racine.
    function capabilityRootFor(uint256 cap, address asset, uint256 agentId) public view returns (bytes32) {
        return keccak256(abi.encode(cap, asset, address(mandate), agentId));
    }

    function computeId(address principal, bytes32 capabilityRoot, bytes32 salt) public view returns (bytes32) {
        return keccak256(abi.encode(address(this), principal, capabilityRoot, salt));
    }

    /// @inheritdoc IBoundedAgentAction
    /// @dev initData = abi.encode(uint256 cap, address asset, uint256 agentId, bytes32 salt).
    ///      `capabilityRoot` DOIT valoir `capabilityRootFor(cap, asset, agentId)`.
    function registerEnvelope(address principal, bytes32 capabilityRoot, uint64 expiresAt, bytes calldata initData)
        external
        returns (bytes32 id)
    {
        if (expiresAt != 0 && expiresAt <= block.timestamp) revert BadExpiry();

        (uint256 cap, address asset, uint256 agentId, bytes32 salt) =
            abi.decode(initData, (uint256, address, uint256, bytes32));

        if (capabilityRoot != capabilityRootFor(cap, asset, agentId)) revert CapabilityMismatch();
        if (mandate.ownerOf(agentId) == address(0)) revert Unauthorized();

        // --- second usage du crochet : le plafond de l'enveloppe ne peut pas
        //     dépasser celui que le mandat porte pour cet agent. Refus écrit par
        //     nous ; le standard ne le prévoit pas et ne peut pas le prévoir,
        //     faute de savoir de quel agent il s'agit. ---
        (uint256 mandateCap,,,) = mandate.mandateOf(agentId);
        if (cap > mandateCap) revert CapExceedsMandate(cap, mandateCap);

        id = computeId(principal, capabilityRoot, salt);
        if (_records[id].status != Status.None) revert IdExists();

        Record storage r = _records[id];
        r.principal = principal;
        r.capabilityRoot = capabilityRoot;
        r.cursorRoot = EMPTY_CURSOR;
        r.createdAt = uint64(block.timestamp);
        r.expiresAt = expiresAt;
        r.status = Status.Active;
        r.cap = cap;
        r.asset = asset;
        r.agentId = agentId;

        emit EnvelopeRegistered(id, principal, capabilityRoot);
    }

    /// @inheritdoc IBoundedAgentAction
    /// @dev witness = abi.encode(uint256 amount). Le compteur consulte le mandat AVANT
    ///      d'avancer : si la lignée est gelée, il refuse.
    function advanceCursor(bytes32 id, bytes calldata witness) external returns (bytes32 newCursor) {
        Record storage r = _get(id);
        if (_effective(r) != Status.Active) revert NotActive();
        if (msg.sender != r.principal) revert Unauthorized();

        // --- le crochet : la décision d'enforcement vient du substrat ---
        if (!mandate.isActive(r.agentId)) revert MandateInactive(r.agentId);

        uint256 amount = abi.decode(witness, (uint256));
        if (r.spent + amount > r.cap) revert BoundExceeded();

        bytes32 prevCursor = r.cursorRoot;
        r.spent += amount;
        newCursor = keccak256(abi.encode(r.spent));
        r.cursorRoot = newCursor;
        emit EnvelopeAdvanced(id, prevCursor, newCursor);
    }

    function getEnvelope(bytes32 id) external view returns (Envelope memory) {
        Record storage r = _get(id);
        return Envelope({
            id: id,
            principal: r.principal,
            capabilityRoot: r.capabilityRoot,
            cursorRoot: r.cursorRoot,
            createdAt: r.createdAt,
            expiresAt: r.expiresAt,
            status: _effective(r)
        });
    }

    function getCursor(bytes32 id) external view returns (bytes32) {
        return _get(id).cursorRoot;
    }

    function getStatus(bytes32 id) external view returns (Status) {
        return _effective(_get(id));
    }

    function isActive(bytes32 id) external view returns (bool) {
        Record storage r = _get(id);
        return _effective(r) == Status.Active && mandate.isActive(r.agentId);
    }

    function setStatus(bytes32 id, Status newStatus) external {
        Record storage r = _get(id);
        Status cur = r.status;
        if (cur != Status.Active) revert BadTransition();

        bool expired = r.expiresAt != 0 && block.timestamp >= r.expiresAt;
        if (newStatus == Status.Expired) {
            if (!expired) revert BadTransition();
        } else {
            if (expired) revert BadTransition();
            if (newStatus == Status.Revoked || newStatus == Status.Completed) {
                if (msg.sender != r.principal) revert Unauthorized();
            } else {
                revert BadTransition();
            }
        }

        r.status = newStatus;
        emit EnvelopeStatusChanged(id, cur, newStatus);
    }

    // --- lectures supplémentaires, hors interface ---

    function bound(bytes32 id) external view returns (uint256 cap, address asset) {
        Record storage r = _get(id);
        return (r.cap, r.asset);
    }

    function spent(bytes32 id) external view returns (uint256) {
        return _get(id).spent;
    }

    function remaining(bytes32 id) external view returns (uint256) {
        Record storage r = _get(id);
        if (_effective(r) != Status.Active) return 0;
        return r.cap - r.spent;
    }

    function agentIdOf(bytes32 id) external view returns (uint256) {
        return _get(id).agentId;
    }

    /// @notice L'identifiant N'EST PAS écrit en dur : il est recalculé depuis la
    ///         redéclaration de l'interface. Une divergence le ferait échouer.
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IBoundedAgentAction).interfaceId;
    }

    function _get(bytes32 id) private view returns (Record storage r) {
        r = _records[id];
        if (r.status == Status.None) revert UnknownEnvelope();
    }

    function _effective(Record storage r) private view returns (Status) {
        if (r.status == Status.Active && r.expiresAt != 0 && block.timestamp >= r.expiresAt) {
            return Status.Expired;
        }
        return r.status;
    }
}
