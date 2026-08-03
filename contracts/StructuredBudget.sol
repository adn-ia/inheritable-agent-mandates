// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title StructuredBudget — un mandat à plafond structuré
 *
 * @notice Un plafond plat est la forme la plus grossière d'un mandat. Ce contrat
 *         ajoute trois dimensions que le plafond plat n'a pas : l'engagé non débité
 *         (`reserved`), les poches par catégorie (`catCap`), et le plafond par
 *         dépense unique (`maxPerItem`).
 *
 *         Un tirage n'est admis que si les trois tiennent à la fois. Chaque refus
 *         nomme la dimension qui a bloqué.
 *
 *         Variante « budget partitionné », mise de côté au §3 du livre blanc — ce
 *         n'est pas la baseline. Non audité, testnet uniquement.
 */
contract StructuredBudget {
    struct Category {
        uint256 catCap;
        uint256 catSpent;
        uint256 catReserved;
        uint256 maxPerItem; // 0 = pas de plafond par dépense
        bool configured;
    }

    struct Budget {
        address owner;
        uint256 parent; // 0 = racine
        uint256 cap;
        uint256 spent;
        uint256 reserved;
        bool exists;
    }

    uint256 public nextId = 1;

    mapping(uint256 => Budget) public budgetOf;
    mapping(uint256 => mapping(bytes32 => Category)) private _cats;
    mapping(uint256 => bytes32[]) private _catKeys;

    error NoSuchBudget();
    error NotOwner();
    error OverAllocated(uint256 sumCatCaps, uint256 cap);
    error LengthMismatch();
    error ZeroAmount();

    /// refus nommés — chacun désigne la dimension qui a bloqué
    error PerItemExceeded(uint256 amount, uint256 maxPerItem);
    error CategoryExceeded(uint256 requested, uint256 categoryRoom);
    error TotalExceeded(uint256 requested, uint256 totalRoom);

    /// refus d'héritage — chacun nomme la dimension élargie
    error ChildCapWider(uint256 childCap, uint256 parentCap);
    error ChildCategoryWider(bytes32 category, uint256 childCatCap, uint256 parentCatCap);
    error ChildPerItemWider(bytes32 category, uint256 childMax, uint256 parentMax);
    error ChildCategoryUnknown(bytes32 category);

    event BudgetCreated(uint256 indexed id, uint256 indexed parent, address indexed owner, uint256 cap);
    event Reserved(uint256 indexed id, bytes32 indexed category, uint256 amount);
    event Settled(uint256 indexed id, bytes32 indexed category, uint256 amount);
    event Drawn(uint256 indexed id, bytes32 indexed category, uint256 amount);

    // ------------------------------------------------------------------ //
    // Construction                                                       //
    // ------------------------------------------------------------------ //

    function createBudget(
        address owner,
        uint256 cap,
        bytes32[] calldata categories,
        uint256[] calldata catCaps,
        uint256[] calldata maxPerItems
    ) external returns (uint256 id) {
        id = _create(0, owner, cap, categories, catCaps, maxPerItems);
    }

    /// @notice Enfant d'un budget existant. `enfant ⊆ parent` sur CHAQUE dimension :
    ///         plafond total, plafond de chaque poche, plafond par dépense.
    function spawn(
        uint256 parentId,
        address owner,
        uint256 cap,
        bytes32[] calldata categories,
        uint256[] calldata catCaps,
        uint256[] calldata maxPerItems
    ) external returns (uint256 id) {
        Budget storage p = _get(parentId);
        if (cap > p.cap) revert ChildCapWider(cap, p.cap);

        for (uint256 i; i < categories.length; i++) {
            Category storage pc = _cats[parentId][categories[i]];
            if (!pc.configured) revert ChildCategoryUnknown(categories[i]);
            if (catCaps[i] > pc.catCap) revert ChildCategoryWider(categories[i], catCaps[i], pc.catCap);
            // maxPerItem : 0 signifie « pas de plafond », donc plus large que tout
            uint256 pMax = pc.maxPerItem;
            uint256 cMax = maxPerItems[i];
            bool widens = (pMax != 0) && (cMax == 0 || cMax > pMax);
            if (widens) revert ChildPerItemWider(categories[i], cMax, pMax);
        }

        id = _create(parentId, owner, cap, categories, catCaps, maxPerItems);
    }

    function _create(
        uint256 parentId,
        address owner,
        uint256 cap,
        bytes32[] calldata categories,
        uint256[] calldata catCaps,
        uint256[] calldata maxPerItems
    ) internal returns (uint256 id) {
        if (categories.length != catCaps.length || categories.length != maxPerItems.length) revert LengthMismatch();

        uint256 sum;
        for (uint256 i; i < catCaps.length; i++) sum += catCaps[i];
        // invariant de setup : pas de sur-allocation
        if (sum > cap) revert OverAllocated(sum, cap);

        id = nextId++;
        budgetOf[id] = Budget({owner: owner, parent: parentId, cap: cap, spent: 0, reserved: 0, exists: true});

        for (uint256 i; i < categories.length; i++) {
            _cats[id][categories[i]] =
                Category({catCap: catCaps[i], catSpent: 0, catReserved: 0, maxPerItem: maxPerItems[i], configured: true});
            _catKeys[id].push(categories[i]);
        }

        emit BudgetCreated(id, parentId, owner, cap);
    }

    // ------------------------------------------------------------------ //
    // Engagé / débité                                                    //
    // ------------------------------------------------------------------ //

    function reserve(uint256 id, bytes32 category, uint256 amount) external {
        Budget storage b = _get(id);
        if (msg.sender != b.owner) revert NotOwner();
        if (amount == 0) revert ZeroAmount();
        _checkAll(id, b, category, amount);

        Category storage c = _cats[id][category];
        if (c.configured) c.catReserved += amount;
        b.reserved += amount;
        emit Reserved(id, category, amount);
    }

    /// @notice Convertit un engagé en dépense effective.
    function settle(uint256 id, bytes32 category, uint256 amount) external {
        Budget storage b = _get(id);
        if (msg.sender != b.owner) revert NotOwner();
        if (amount == 0) revert ZeroAmount();

        Category storage c = _cats[id][category];
        if (c.configured) {
            c.catReserved -= amount;
            c.catSpent += amount;
        }
        b.reserved -= amount;
        b.spent += amount;
        emit Settled(id, category, amount);
    }

    // ------------------------------------------------------------------ //
    // Le check                                                           //
    // ------------------------------------------------------------------ //

    function draw(uint256 id, bytes32 category, uint256 amount) external {
        Budget storage b = _get(id);
        if (msg.sender != b.owner) revert NotOwner();
        if (amount == 0) revert ZeroAmount();
        _checkAll(id, b, category, amount);

        Category storage c = _cats[id][category];
        if (c.configured) c.catSpent += amount;
        b.spent += amount;
        emit Drawn(id, category, amount);
    }

    /// @dev Les trois conditions, dans l'ordre : plafond par dépense, poche, total.
    function _checkAll(uint256 id, Budget storage b, bytes32 category, uint256 amount) internal view {
        Category storage c = _cats[id][category];

        if (c.configured) {
            if (c.maxPerItem != 0 && amount > c.maxPerItem) revert PerItemExceeded(amount, c.maxPerItem);

            uint256 catUsed = c.catSpent + c.catReserved;
            if (catUsed + amount > c.catCap) {
                revert CategoryExceeded(amount, c.catCap > catUsed ? c.catCap - catUsed : 0);
            }
        }

        uint256 used = b.spent + b.reserved;
        if (used + amount > b.cap) {
            revert TotalExceeded(amount, b.cap > used ? b.cap - used : 0);
        }
    }

    // ------------------------------------------------------------------ //
    // Lectures                                                           //
    // ------------------------------------------------------------------ //

    function categoryOf(uint256 id, bytes32 category)
        external
        view
        returns (uint256 catCap, uint256 catSpent, uint256 catReserved, uint256 maxPerItem, bool configured)
    {
        Category storage c = _cats[id][category];
        return (c.catCap, c.catSpent, c.catReserved, c.maxPerItem, c.configured);
    }

    function categoryKeys(uint256 id) external view returns (bytes32[] memory) {
        return _catKeys[id];
    }

    function totalRoom(uint256 id) external view returns (uint256) {
        Budget storage b = _get(id);
        uint256 used = b.spent + b.reserved;
        return b.cap > used ? b.cap - used : 0;
    }

    function _get(uint256 id) private view returns (Budget storage b) {
        b = budgetOf[id];
        if (!b.exists) revert NoSuchBudget();
    }
}
