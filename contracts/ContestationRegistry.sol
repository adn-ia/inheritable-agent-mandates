// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IProvenanceRegistry {
    function parentsOf(bytes32 programKey) external view returns (bytes32[] memory);
}

/**
 * @title ContestationRegistry — couche de contestation append-only
 * @notice Se pose PAR-DESSUS un ProvenanceRegistry existant, sans jamais l'écrire.
 *         La base est passée en `immutable` et n'est appelée qu'en lecture (`parentsOf`) :
 *         ce contrat ne peut pas modifier la lignée déclarée, par construction.
 *
 *         Un tiers peut ASSERTER une arête de parenté que l'auteur n'a pas déclarée.
 *         Chaque assertion enregistre `msg.sender` et un horodatage, et émet un event.
 *         Aucun setter, aucun delete : ré-asserter la même arête ajoute une entrée,
 *         elle n'en écrase jamais une.
 *
 *         La lecture augmentée combine les parents DÉCLARÉS (base) et les arêtes
 *         ASSERTÉES (ici). Ce qu'elle rend dépend du contenu des deux registres.
 *
 *         Contestation ouverte et non gardée : n'importe quelle adresse peut asserter
 *         n'importe quelle arête. Toute variante pondérée, cautionnée ou authentifiée
 *         serait une autre conception, absente de ce contrat.
 *
 *         Non audité, testnet uniquement.
 */
contract ContestationRegistry {
    struct Assertion {
        bytes32 child;
        bytes32 claimedParent;
        address asserter;
        uint64 assertedAt;
    }

    /// borne de gaz pour la traversée généalogique
    uint256 public constant MAX_NODES = 64;

    IProvenanceRegistry public immutable base;

    /// arêtes assertées, par enfant — append-only
    mapping(bytes32 => bytes32[]) private _asserted;
    /// journal complet, append-only
    Assertion[] private _log;

    event ParentAsserted(
        bytes32 indexed child,
        bytes32 indexed claimedParent,
        address indexed asserter,
        uint256 index
    );

    constructor(address baseRegistry) {
        require(baseRegistry != address(0), "base is zero");
        base = IProvenanceRegistry(baseRegistry);
    }

    /// @notice Asserte une arête de parenté. N'écrit jamais dans la base.
    function assertParent(bytes32 child, bytes32 claimedParent) external returns (uint256 index) {
        require(child != bytes32(0) && claimedParent != bytes32(0), "zero key");
        require(child != claimedParent, "self parent");

        _asserted[child].push(claimedParent);
        index = _log.length;
        _log.push(
            Assertion({
                child: child,
                claimedParent: claimedParent,
                asserter: msg.sender,
                assertedAt: uint64(block.timestamp)
            })
        );

        emit ParentAsserted(child, claimedParent, msg.sender, index);
    }

    function assertedParentsOf(bytes32 child) external view returns (bytes32[] memory) {
        return _asserted[child];
    }

    function assertionCount() external view returns (uint256) {
        return _log.length;
    }

    function assertionAt(uint256 index) external view returns (Assertion memory) {
        return _log[index];
    }

    /**
     * @notice Remonte la généalogie en combinant les parents déclarés dans la base
     *         et les arêtes assertées ici, jusqu'à `maxDepth` générations, et rend
     *         `true` s'il existe un ancêtre commun aux deux clés.
     * @dev    Un noeud est son propre ancêtre à profondeur 0. Traversée bornée par
     *         `maxDepth` et par `MAX_NODES`.
     */
    function shareLineageWithContest(bytes32 a, bytes32 b, uint8 maxDepth) external view returns (bool) {
        bytes32[] memory ancA = _ancestors(a, maxDepth);
        bytes32[] memory ancB = _ancestors(b, maxDepth);

        for (uint256 i; i < ancA.length; i++) {
            for (uint256 j; j < ancB.length; j++) {
                if (ancA[i] == ancB[j]) return true;
            }
        }
        return false;
    }

    /// @dev Parents déclarés (base) ∪ parents assertés (ici).
    function _combinedParents(bytes32 key) internal view returns (bytes32[] memory) {
        bytes32[] memory declared = base.parentsOf(key);
        bytes32[] memory asserted = _asserted[key];

        bytes32[] memory all = new bytes32[](declared.length + asserted.length);
        uint256 n;
        for (uint256 i; i < declared.length; i++) all[n++] = declared[i];
        for (uint256 i; i < asserted.length; i++) all[n++] = asserted[i];
        return all;
    }

    function _ancestors(bytes32 key, uint8 maxDepth) internal view returns (bytes32[] memory) {
        bytes32[] memory found = new bytes32[](MAX_NODES);
        uint256 n;

        found[n++] = key;
        uint256 levelStart;
        uint256 levelEnd = n;

        for (uint256 d; d < maxDepth; d++) {
            for (uint256 i = levelStart; i < levelEnd; i++) {
                bytes32[] memory ps = _combinedParents(found[i]);
                for (uint256 k; k < ps.length; k++) {
                    bool seen;
                    for (uint256 m; m < n; m++) {
                        if (found[m] == ps[k]) {
                            seen = true;
                            break;
                        }
                    }
                    if (!seen) {
                        if (n == MAX_NODES) break;
                        found[n++] = ps[k];
                    }
                }
            }
            if (n == levelEnd) break;
            levelStart = levelEnd;
            levelEnd = n;
        }

        bytes32[] memory out = new bytes32[](n);
        for (uint256 i; i < n; i++) out[i] = found[i];
        return out;
    }
}
