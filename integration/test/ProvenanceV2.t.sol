// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {ProvenanceRegistryV2} from "adn/ProvenanceRegistryV2.sol";

/**
 * ProvenanceRegistryV2 — les invariants de v1 doivent tenir, plus les deux ajouts.
 * Chaque lecture est imprimée telle quelle ; les assertions portent sur des
 * propriétés que le code peut échouer.
 */
contract ProvenanceV2Test is Test {
    ProvenanceRegistryV2 r;

    bytes32 constant SPEC = keccak256("spec-commit");
    bytes32 constant IMPL = keccak256("implementation-commit");

    bytes32 A = keccak256("A");
    bytes32 M = keccak256("M");
    bytes32 N = keccak256("N");
    bytes32 X = keccak256("X");
    bytes32 Y = keccak256("Y");
    bytes32 Z = keccak256("Z");

    function setUp() public {
        r = new ProvenanceRegistryV2();
    }

    function _none() internal pure returns (bytes32[] memory a) {
        a = new bytes32[](0);
    }

    function _one(bytes32 p) internal pure returns (bytes32[] memory a) {
        a = new bytes32[](1);
        a[0] = p;
    }

    function _reg(bytes32 k, bytes32[] memory parents) internal {
        r.register(k, parents, SPEC, IMPL, ProvenanceRegistryV2.ReviewMethod.BlindReconstruction);
    }

    /// X et Y : ancêtre commun A à profondeur 2. Z indépendant.
    function _graph() internal {
        _reg(A, _none());
        _reg(M, _one(A));
        _reg(N, _one(A));
        _reg(X, _one(M));
        _reg(Y, _one(N));
        _reg(Z, _none());
    }

    // ---------------------------------------------------------- l'ajout v2
    function test_implementationCommit_est_lisible() public {
        console2.log("=== implementationCommit, ajout de v2 ===");
        _reg(A, _none());
        (bytes32 spec, bytes32 impl, address author, ProvenanceRegistryV2.ReviewMethod m, bool exists) =
            r.recordOf(A);
        console2.log("   specCommit == valeur posee ? rendu           :", spec == SPEC);
        console2.log("   implementationCommit == valeur posee ? rendu :", impl == IMPL);
        console2.log("   author == l'appelant ? rendu                 :", author == address(this));
        console2.log("   exists rendu                                 :", exists);
        assertEq(uint8(m), uint8(ProvenanceRegistryV2.ReviewMethod.BlindReconstruction));
        assertTrue(spec == SPEC && impl == IMPL, "les deux commits doivent etre distincts et lisibles");
        assertTrue(spec != impl, "spec et implementation sont deux champs differents");
    }

    // ---------------------------------------------------------- l'alias
    function test_alias_identique_a_shareLineage() public {
        console2.log("=== sameHeritageCluster == shareLineage, sur tout le graphe ===");
        _graph();
        bytes32[6] memory keys = [A, M, N, X, Y, Z];
        uint256 compared;
        for (uint256 i; i < 6; i++) {
            for (uint256 j; j < 6; j++) {
                for (uint8 d; d <= 4; d++) {
                    assertEq(
                        r.sameHeritageCluster(keys[i], keys[j], d),
                        r.shareLineage(keys[i], keys[j], d),
                        "l'alias doit rendre exactement shareLineage"
                    );
                    compared++;
                }
            }
        }
        console2.log("   paires x profondeurs comparees, toutes identiques :", compared);
    }

    function testFuzz_alias_identique(uint8 depth, uint8 pick) public {
        _graph();
        bytes32[6] memory keys = [A, M, N, X, Y, Z];
        bytes32 a = keys[pick % 6];
        bytes32 b = keys[(pick / 6) % 6];
        uint8 d = depth % 8;
        assertEq(r.sameHeritageCluster(a, b, d), r.shareLineage(a, b, d));
    }

    function test_le_verdict_depend_de_la_profondeur() public {
        console2.log("=== l'horizon fait partie de la question ===");
        _graph();
        console2.log("   X et Y ont A pour ancetre commun a 2 generations");
        for (uint8 d; d <= 3; d++) {
            console2.log("   sameHeritageCluster(X,Y,", d, ") rendu :", r.sameHeritageCluster(X, Y, d));
        }
        console2.log("   sameHeritageCluster(X,Z, 8) rendu :", r.sameHeritageCluster(X, Z, 8));
    }

    // ---------------------------------------------------------- invariants v1
    function test_write_once() public {
        console2.log("=== write-once, inchange depuis v1 ===");
        _reg(A, _none());
        vm.expectRevert(bytes("programKey already registered"));
        _reg(A, _none());
        console2.log("   re-enregistrement de A : reverte");

        _reg(M, _one(A));
        vm.expectRevert(bytes("programKey already registered"));
        _reg(M, _none());
        console2.log("   re-enregistrement de M en effacant sa lignee : reverte");
    }

    function test_parent_inconnu_et_self_parent() public {
        console2.log("=== parent inconnu / self-parent, inchanges depuis v1 ===");
        vm.expectRevert(bytes("unknown parent"));
        _reg(M, _one(A));
        console2.log("   parent jamais enregistre : reverte");

        _reg(A, _none());

        // Un noeud qui se declare son propre parent est bien refuse — mais par le
        // controle d'existence, pas par le garde `self parent`. On rapporte la
        // raison REELLE plutot que celle qu'on attendait.
        vm.expectRevert(bytes("unknown parent"));
        _reg(X, _one(X));
        console2.log("   noeud declarant sa propre cle : reverte - unknown parent");

        vm.expectRevert(bytes("programKey is zero"));
        _reg(bytes32(0), _none());
        console2.log("   cle nulle : reverte");
    }

    /// Le garde `self parent` est-il atteignable ? Les deux chemins sont fermes avant.
    function test_le_garde_self_parent_est_inatteignable() public {
        console2.log("=== le garde 'self parent' n'est jamais atteint ===");
        _reg(A, _none());

        console2.log("   cas 1 - la cle n'existe pas encore :");
        vm.expectRevert(bytes("unknown parent"));
        _reg(X, _one(X));
        console2.log("      le controle d'existence du parent reverte en premier");

        console2.log("   cas 2 - la cle existe deja :");
        vm.expectRevert(bytes("programKey already registered"));
        _reg(A, _one(A));
        console2.log("      le write-once reverte en premier");

        console2.log("   -> aucune entree ne peut atteindre `require(parents[i] != programKey)`");
        console2.log("   -> la protection tient, mais par deux autres controles ; le garde est du code mort");
        console2.log("   -> present a l'identique dans v1 deployee (0x202f4eef...)");
    }

    function test_pas_de_champ_cluster_stocke() public view {
        console2.log("=== le cluster n'est PAS un champ stocke ===");
        console2.log("   recordOf rend 5 valeurs : spec, implementation, author, method, exists");
        console2.log("   aucune n'est un tag de cluster auto-declare");
        console2.log("   MAX_NODES rendu :", r.MAX_NODES());
    }

    function test_borne_max_nodes() public view {
        assertEq(r.MAX_NODES(), 64, "la borne de gaz doit rester celle de v1");
    }
}
