// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ProvenanceRegistryV2 — le « brin mitochondrial », v2
 *
 * @notice Identique à [`ProvenanceRegistry`](ProvenanceRegistry.sol) (v1, déployée et
 *         laissée en place) sur tout ce qui compte : write-once, parent inconnu
 *         rejeté, self-parent rejeté, traversée bornée par `maxDepth` et `MAX_NODES`.
 *
 *         Deux changements, et deux seulement :
 *
 *         1. `implementationCommit` (`bytes32`) rejoint `specCommit` dans le Record,
 *            le register, la lecture et l'event. Un enregistrement épingle donc à la
 *            fois la spec lue et l'artefact effectivement produit.
 *
 *         2. `sameHeritageCluster(a, b, maxDepth)` — un alias de lecture qui renvoie
 *            **exactement** `shareLineage(a, b, maxDepth)`.
 *
 *         Sur le cluster, le choix est DÉRIVÉ, pas stocké. Un champ auto-déclaré
 *         aurait permis à deux nœuds sans aucune ascendance — zéro parent des deux
 *         côtés — d'être rendus « du même cluster » pour le prix d'un mot écrit dans
 *         un champ libre. La dérivation ne peut pas inventer un lien absent du
 *         graphe ; en contrepartie, elle ne voit que ce qui a été déclaré comme
 *         parent, et son verdict dépend de la profondeur demandée. Les deux options
 *         ont été construites et mesurées avant de trancher.
 *
 *         Sur le namespace, le choix est **une instance par espace d'identité**. Un
 *         simple tag de domaine évite les collisions d'identifiants mais n'empêche
 *         pas une lignée de traverser les domaines : un interpréteur peut déclarer
 *         un attestataire comme parent, et la lecture les rend apparentés. Des
 *         instances séparées rendent ce chemin inexistant plutôt qu'interdit.
 *
 *         LIMITE INCHANGÉE : la provenance est **déclarée**, pas vérifiée. Le
 *         registre garantit qu'une déclaration est permanente, signée et
 *         attribuable — pas qu'elle est vraie.
 *
 *         Non audité, testnet uniquement.
 */
contract ProvenanceRegistryV2 {
    enum ReviewMethod {
        BlindReconstruction,
        SharedSpecCollab,
        DerivedFromExisting,
        RawArtifactDecode
    }

    struct Record {
        bytes32 specCommit;
        bytes32 implementationCommit;
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
        bytes32 implementationCommit,
        ReviewMethod reviewMethod,
        bytes32[] parents
    );

    /// @notice Enregistre un interpréteur. Write-once : reverte si déjà pris.
    function register(
        bytes32 programKey,
        bytes32[] calldata parents,
        bytes32 specCommit,
        bytes32 implementationCommit,
        ReviewMethod reviewMethod
    ) external {
        require(programKey != bytes32(0), "programKey is zero");
        require(!_records[programKey].exists, "programKey already registered");

        // Une lignée déclarée doit pointer vers des ancêtres qui existent :
        // sinon la traversée passerait sur des noeuds fantomes en silence.
        for (uint256 i; i < parents.length; i++) {
            require(_records[parents[i]].exists, "unknown parent");
            require(parents[i] != programKey, "self parent");
        }

        _records[programKey] = Record({
            specCommit: specCommit,
            implementationCommit: implementationCommit,
            author: msg.sender,
            reviewMethod: reviewMethod,
            exists: true
        });
        _parents[programKey] = parents;

        emit Registered(programKey, msg.sender, specCommit, implementationCommit, reviewMethod, parents);
    }

    function recordOf(bytes32 programKey)
        external
        view
        returns (
            bytes32 specCommit,
            bytes32 implementationCommit,
            address author,
            ReviewMethod reviewMethod,
            bool exists
        )
    {
        Record memory r = _records[programKey];
        return (r.specCommit, r.implementationCommit, r.author, r.reviewMethod, r.exists);
    }

    function parentsOf(bytes32 programKey) external view returns (bytes32[] memory) {
        return _parents[programKey];
    }

    /**
     * @notice Vrai si `a` et `b` ont un ancêtre commun dans la limite de `maxDepth`
     *         générations remontées. Un noeud est son propre ancêtre à profondeur 0.
     * @dev    Traversée bornée par `maxDepth` ET par `MAX_NODES` (gaz).
     */
    function shareLineage(bytes32 a, bytes32 b, uint8 maxDepth) public view returns (bool) {
        bytes32[] memory ancA = _ancestors(a, maxDepth);
        bytes32[] memory ancB = _ancestors(b, maxDepth);

        for (uint256 i; i < ancA.length; i++) {
            for (uint256 j; j < ancB.length; j++) {
                if (ancA[i] == ancB[j]) return true;
            }
        }
        return false;
    }

    /**
     * @notice Deux interpréteurs appartiennent-ils au même cluster d'héritage ?
     * @dev    Alias de lecture : renvoie EXACTEMENT `shareLineage`. Rien n'est
     *         stocké, rien n'est auto-déclaré. Le cluster est une **conséquence** du
     *         graphe de parenté, pas une étiquette qu'on se donne.
     *
     *         Conséquence à connaître : le verdict dépend de `maxDepth`. Deux nœuds
     *         dont l'ancêtre commun est à trois générations sont « du même cluster »
     *         à `maxDepth = 3` et pas à `maxDepth = 2`. Ce n'est pas une
     *         approximation — c'est la question qui porte l'horizon.
     */
    function sameHeritageCluster(bytes32 a, bytes32 b, uint8 maxDepth) external view returns (bool) {
        return shareLineage(a, b, maxDepth);
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

    // Volontairement : PAS de champ `heritageCluster` stocké, PAS de tag de domaine.
    // Les deux options ont été construites et mesurées ; ces absences sont un choix,
    // pas un oubli.
}
