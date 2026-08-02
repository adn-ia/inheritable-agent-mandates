// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ProvenanceRegistry — le « brin mitochondrial »
 * @notice Le hash du code (`programKey`) porte l'IDENTITÉ d'un interpréteur.
 *         La LIGNÉE est une donnée distincte, déclarée à l'enregistrement et
 *         héritée à part du code : deux interpréteurs au code différent (donc
 *         `programKey` différents) peuvent partager une ascendance déclarée.
 *
 *         Le registre est write-once : un `programKey` enregistré ne peut jamais
 *         être ré-enregistré, modifié ni supprimé. Aucun setter, aucun delete.
 *
 *         LIMITE ASSUMÉE : la lignée est DÉCLARÉE, pas vérifiée. Le contrat ne
 *         peut pas savoir si une ascendance déclarée est vraie. Il garantit
 *         seulement qu'elle est permanente, signée et attribuable — mentir reste
 *         possible, mais devient visible et imputable.
 *
 *         Non audité, testnet uniquement.
 */
contract ProvenanceRegistry {
    enum ReviewMethod {
        BlindReconstruction,
        SharedSpecCollab,
        DerivedFromExisting,
        RawArtifactDecode
    }

    struct Record {
        bytes32 specCommit;
        address author;
        ReviewMethod reviewMethod;
        bool exists;
    }

    /// borne de gaz pour la traversée généalogique
    uint256 public constant MAX_NODES = 64;

    mapping(bytes32 => Record) private _records;
    mapping(bytes32 => bytes32[]) private _parents;

    event Registered(
        bytes32 indexed programKey,
        address indexed author,
        bytes32 indexed specCommit,
        ReviewMethod reviewMethod,
        bytes32[] parents
    );

    /// @notice Enregistre un interpréteur. Write-once : reverte si déjà pris.
    function register(
        bytes32 programKey,
        bytes32[] calldata parents,
        bytes32 specCommit,
        ReviewMethod reviewMethod
    ) external {
        require(programKey != bytes32(0), "programKey is zero");
        require(!_records[programKey].exists, "programKey already registered");

        // Une lignée déclarée doit pointer vers des ancêtres qui existent :
        // sinon `shareLineage` traverserait des noeuds fantomes en silence.
        for (uint256 i; i < parents.length; i++) {
            require(_records[parents[i]].exists, "unknown parent");
            require(parents[i] != programKey, "self parent");
        }

        _records[programKey] = Record({
            specCommit: specCommit,
            author: msg.sender,
            reviewMethod: reviewMethod,
            exists: true
        });
        _parents[programKey] = parents;

        emit Registered(programKey, msg.sender, specCommit, reviewMethod, parents);
    }

    function recordOf(bytes32 programKey)
        external
        view
        returns (bytes32 specCommit, address author, ReviewMethod reviewMethod, bool exists)
    {
        Record memory r = _records[programKey];
        return (r.specCommit, r.author, r.reviewMethod, r.exists);
    }

    function parentsOf(bytes32 programKey) external view returns (bytes32[] memory) {
        return _parents[programKey];
    }

    /**
     * @notice Vrai si `a` et `b` ont un ancêtre commun dans la limite de `maxDepth`
     *         générations remontées. Un noeud est son propre ancêtre de profondeur 0,
     *         donc `shareLineage(x, x)` est vrai, et un parent direct partage la lignée
     *         avec son enfant dès `maxDepth >= 1`.
     * @dev    Traversée bornée par `maxDepth` ET par `MAX_NODES` (gaz).
     */
    function shareLineage(bytes32 a, bytes32 b, uint8 maxDepth) external view returns (bool) {
        bytes32[] memory ancA = _ancestors(a, maxDepth);
        bytes32[] memory ancB = _ancestors(b, maxDepth);

        for (uint256 i; i < ancA.length; i++) {
            for (uint256 j; j < ancB.length; j++) {
                if (ancA[i] == ancB[j]) return true;
            }
        }
        return false;
    }

    /// @dev Ancêtres de `key` jusqu'à `maxDepth` générations, `key` inclus (profondeur 0).
    function _ancestors(bytes32 key, uint8 maxDepth) internal view returns (bytes32[] memory) {
        bytes32[] memory found = new bytes32[](MAX_NODES);
        uint256 n;

        if (!_records[key].exists) return new bytes32[](0);

        found[n++] = key;
        uint256 levelStart;
        uint256 levelEnd = n;

        for (uint256 d; d < maxDepth; d++) {
            for (uint256 i = levelStart; i < levelEnd; i++) {
                bytes32[] memory ps = _parents[found[i]];
                for (uint256 k; k < ps.length; k++) {
                    bool seen;
                    for (uint256 m; m < n; m++) {
                        if (found[m] == ps[k]) {
                            seen = true;
                            break;
                        }
                    }
                    if (!seen) {
                        if (n == MAX_NODES) break; // borne de gaz atteinte
                        found[n++] = ps[k];
                    }
                }
            }
            if (n == levelEnd) break; // plus rien de neuf : généalogie épuisée
            levelStart = levelEnd;
            levelEnd = n;
        }

        bytes32[] memory out = new bytes32[](n);
        for (uint256 i; i < n; i++) out[i] = found[i];
        return out;
    }
}
