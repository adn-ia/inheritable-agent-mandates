// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title MandateWithException — la couture entre le calcul et le jugement humain
 *
 * @notice Un mandat à plafond dur refuse. Le refus n'est pas la fin : il expose
 *         proprement le résidu (`ExceptionRequested`) sans appeler d'oracle et sans
 *         rien décider. Des gardiens NOMMÉS, distincts de l'agent, peuvent alors
 *         accorder une exception bornée, tracée, à usage unique.
 *
 *         Chaque exception enregistre son ou ses approbateurs, le pari déclaré
 *         (`statedBet` — le résultat visé), et une lecture neutre datée AVANT le
 *         résultat (`preActionRead`). Aucune de ces trois choses ne peut être
 *         ajoutée après coup : le contrat refuse d'accorder sans elles, et n'expose
 *         aucun moyen de les modifier ensuite.
 *
 *         Ce que ce contrat NE fait pas : juger. Il borne qui peut décider, de
 *         combien, jusqu'à quand, et il enregistre. Le jugement reste humain.
 *
 *         Proposition, pas une baseline. Non audité, testnet uniquement.
 */
contract MandateWithException {
    struct Budget {
        address agent;
        uint256 parent; // 0 = racine
        uint256 cap;
        uint256 spent;
        uint256 exceptionAllowance; // somme des exceptions accordées et consommées
        bool exists;
    }

    struct Exception {
        uint256 budgetId;
        bytes32 category;
        uint256 amount;
        uint64 expiry;
        bytes32 statedBet;
        bytes32 preActionRead;
        address[] approvers;
        bool consumed;
        bool exists;
    }

    /// plafond dur au-dessus duquel aucun gardien ne peut accorder
    uint256 public immutable maxExceptionAmount;
    /// au-delà de ce montant, il faut plusieurs gardiens
    uint256 public immutable bigThreshold;
    /// nombre d'approbateurs distincts requis pour une grosse exception
    uint256 public immutable bigApprovals;

    mapping(address => bool) public isGuardian;
    uint256 public guardianCount;

    uint256 public nextBudgetId = 1;
    uint256 public nextExceptionId = 1;

    mapping(uint256 => Budget) public budgetOf;
    mapping(uint256 => Exception) private _exceptions;

    error NoSuchBudget();
    error NoSuchException();
    error NotAgent();
    error NotGuardian();
    error AgentCannotGrant();
    error ZeroAmount();
    error CapExceeded(uint256 requested, uint256 room);
    error ExceptionTooLarge(uint256 requested, uint256 maxAllowed);
    error MissingStatedBet();
    error MissingPreActionRead();
    error AlreadyApproved();
    error NotEnoughApprovers(uint256 have, uint256 need);
    error ExceptionExpired(uint64 expiry, uint256 nowTs);
    error ExceptionConsumed();
    error WrongCategory(bytes32 expected, bytes32 got);
    error AmountAboveException(uint256 requested, uint256 granted);
    error ExceptionNotForThisBudget(uint256 exceptionBudget, uint256 got);
    error ChildCapWider(uint256 childCap, uint256 parentCap);

    event BudgetCreated(uint256 indexed id, uint256 indexed parent, address indexed agent, uint256 cap);
    /// @notice Le mandat expose le résidu : voilà ce qui a été refusé, et pourquoi.
    event ExceptionRequested(
        uint256 indexed budgetId, address indexed requester, bytes32 indexed category, uint256 amount, uint256 room
    );
    event ExceptionProposed(uint256 indexed exceptionId, uint256 indexed budgetId, address indexed proposer, uint256 amount);
    event ExceptionApproved(uint256 indexed exceptionId, address indexed approver, uint256 approverCount);
    event ExceptionConsumedEvent(uint256 indexed exceptionId, uint256 indexed budgetId, uint256 amount);
    event Drawn(uint256 indexed budgetId, bytes32 indexed category, uint256 amount);

    constructor(address[] memory guardians, uint256 _maxExceptionAmount, uint256 _bigThreshold, uint256 _bigApprovals) {
        for (uint256 i; i < guardians.length; i++) {
            if (!isGuardian[guardians[i]]) {
                isGuardian[guardians[i]] = true;
                guardianCount++;
            }
        }
        maxExceptionAmount = _maxExceptionAmount;
        bigThreshold = _bigThreshold;
        bigApprovals = _bigApprovals;
    }

    // ------------------------------------------------------------------ //
    // Budgets                                                            //
    // ------------------------------------------------------------------ //

    function createBudget(address agent, uint256 cap) external returns (uint256 id) {
        id = nextBudgetId++;
        budgetOf[id] = Budget({agent: agent, parent: 0, cap: cap, spent: 0, exceptionAllowance: 0, exists: true});
        emit BudgetCreated(id, 0, agent, cap);
    }

    function spawn(uint256 parentId, address agent, uint256 cap) external returns (uint256 id) {
        Budget storage p = _budget(parentId);
        // l'enfant ne peut pas être plus large que le plafond NOMINAL du parent —
        // une exception accordée au parent n'entre pas dans ce calcul
        if (cap > p.cap) revert ChildCapWider(cap, p.cap);
        id = nextBudgetId++;
        budgetOf[id] = Budget({agent: agent, parent: parentId, cap: cap, spent: 0, exceptionAllowance: 0, exists: true});
        emit BudgetCreated(id, parentId, agent, cap);
    }

    // ------------------------------------------------------------------ //
    // Dépense ordinaire                                                  //
    // ------------------------------------------------------------------ //

    function draw(uint256 id, bytes32 category, uint256 amount) external {
        Budget storage b = _budget(id);
        if (msg.sender != b.agent) revert NotAgent();
        if (amount == 0) revert ZeroAmount();

        uint256 room = b.cap > b.spent ? b.cap - b.spent : 0;
        if (amount > room) revert CapExceeded(amount, room);

        b.spent += amount;
        emit Drawn(id, category, amount);
    }

    /// @notice Le refus, exposé proprement. N'accorde rien, n'appelle aucun oracle.
    function requestException(uint256 id, bytes32 category, uint256 amount) external {
        Budget storage b = _budget(id);
        if (msg.sender != b.agent) revert NotAgent();
        uint256 room = b.cap > b.spent ? b.cap - b.spent : 0;
        emit ExceptionRequested(id, msg.sender, category, amount, room);
    }

    // ------------------------------------------------------------------ //
    // Exceptions — réservées au rôle gardien                             //
    // ------------------------------------------------------------------ //

    /// @notice Propose une exception. Seul un gardien peut le faire, et jamais
    ///         l'agent du budget concerné, même s'il est par ailleurs gardien.
    function proposeException(
        uint256 budgetId,
        bytes32 category,
        uint256 amount,
        uint64 expiry,
        bytes32 statedBet,
        bytes32 preActionRead
    ) external returns (uint256 exceptionId) {
        Budget storage b = _budget(budgetId);
        if (!isGuardian[msg.sender]) revert NotGuardian();
        // le cœur de la non-contournabilité : l'agent ne s'auto-autorise pas
        if (msg.sender == b.agent) revert AgentCannotGrant();
        if (amount == 0) revert ZeroAmount();
        if (amount > maxExceptionAmount) revert ExceptionTooLarge(amount, maxExceptionAmount);
        // la trace n'est pas optionnelle : impossible d'accorder sans elle
        if (statedBet == bytes32(0)) revert MissingStatedBet();
        if (preActionRead == bytes32(0)) revert MissingPreActionRead();

        exceptionId = nextExceptionId++;
        Exception storage e = _exceptions[exceptionId];
        e.budgetId = budgetId;
        e.category = category;
        e.amount = amount;
        e.expiry = expiry;
        e.statedBet = statedBet;
        e.preActionRead = preActionRead;
        e.exists = true;
        e.approvers.push(msg.sender);

        emit ExceptionProposed(exceptionId, budgetId, msg.sender, amount);
        emit ExceptionApproved(exceptionId, msg.sender, 1);
    }

    /// @notice Approbation supplémentaire par un autre gardien.
    function approveException(uint256 exceptionId) external {
        Exception storage e = _exception(exceptionId);
        Budget storage b = _budget(e.budgetId);
        if (!isGuardian[msg.sender]) revert NotGuardian();
        if (msg.sender == b.agent) revert AgentCannotGrant();

        for (uint256 i; i < e.approvers.length; i++) {
            if (e.approvers[i] == msg.sender) revert AlreadyApproved();
        }
        e.approvers.push(msg.sender);
        emit ExceptionApproved(exceptionId, msg.sender, e.approvers.length);
    }

    function requiredApprovals(uint256 amount) public view returns (uint256) {
        return amount > bigThreshold ? bigApprovals : 1;
    }

    /// @notice Consomme l'exception : le tirage refusé passe UNE SEULE FOIS, à
    ///         hauteur de ce qui a été accordé, dans sa catégorie, avant expiration.
    function drawWithException(uint256 budgetId, uint256 exceptionId, bytes32 category, uint256 amount) external {
        Budget storage b = _budget(budgetId);
        if (msg.sender != b.agent) revert NotAgent();

        Exception storage e = _exception(exceptionId);
        if (e.budgetId != budgetId) revert ExceptionNotForThisBudget(e.budgetId, budgetId);
        if (e.consumed) revert ExceptionConsumed();
        if (e.expiry != 0 && block.timestamp > e.expiry) revert ExceptionExpired(e.expiry, block.timestamp);
        if (e.category != category) revert WrongCategory(e.category, category);
        if (amount > e.amount) revert AmountAboveException(amount, e.amount);

        uint256 need = requiredApprovals(e.amount);
        if (e.approvers.length < need) revert NotEnoughApprovers(e.approvers.length, need);

        e.consumed = true;
        b.spent += amount;
        b.exceptionAllowance += e.amount;

        emit ExceptionConsumedEvent(exceptionId, budgetId, amount);
        emit Drawn(budgetId, category, amount);
    }

    // ------------------------------------------------------------------ //
    // Lectures — le registre                                             //
    // ------------------------------------------------------------------ //

    function exceptionOf(uint256 exceptionId)
        external
        view
        returns (
            uint256 budgetId,
            bytes32 category,
            uint256 amount,
            uint64 expiry,
            bytes32 statedBet,
            bytes32 preActionRead,
            bool consumed,
            uint256 approverCount
        )
    {
        Exception storage e = _exception(exceptionId);
        return (
            e.budgetId, e.category, e.amount, e.expiry, e.statedBet, e.preActionRead, e.consumed, e.approvers.length
        );
    }

    function approversOf(uint256 exceptionId) external view returns (address[] memory) {
        return _exception(exceptionId).approvers;
    }

    /// @notice Plafond effectif : le nominal, plus ce que des gardiens ont
    ///         explicitement accordé et qui a été consommé. Rien d'autre.
    function effectiveCeiling(uint256 id) external view returns (uint256) {
        Budget storage b = _budget(id);
        return b.cap + b.exceptionAllowance;
    }

    function _budget(uint256 id) private view returns (Budget storage b) {
        b = budgetOf[id];
        if (!b.exists) revert NoSuchBudget();
    }

    function _exception(uint256 id) private view returns (Exception storage e) {
        e = _exceptions[id];
        if (!e.exists) revert NoSuchException();
    }

    // Volontairement : AUCUNE fonction pour modifier une exception après coup.
    // Pas de setter sur statedBet ni sur preActionRead, pas de suppression.
}
