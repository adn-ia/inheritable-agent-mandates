// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {InheritableAgentMandateV3} from "adn/InheritableAgentMandateV3.sol";

/// Les deux defauts trouves sur V5 existent-ils dans V3, qui est DEPLOYEE ?
/// Instance locale jetable. Aucun deploiement, aucune transaction reelle.
contract V3HeritageTest is Test {
    InheritableAgentMandateV3 v3;
    address G; address A; address P;

    function setUp() public {
        G = makeAddr("g"); A = makeAddr("a"); P = makeAddr("p");
        vm.warp(1_000_000);
        vm.prank(G);
        v3 = new InheritableAgentMandateV3(G);
    }

    function _m(uint256 cap, uint64 vu, uint16 telo)
        internal pure returns (InheritableAgentMandateV3.Mandate memory)
    {
        return InheritableAgentMandateV3.Mandate({
            maxSpendWei: cap, validUntil: vu, telomere: telo,
            requireLease: true, frozen: false
        });
    }

    // 1 — un proprietaire nul est-il accepte ?
    function test_A_proprietaire_nul() public {
        address[] memory pay = new address[](1); pay[0] = P;
        console2.log("=== A. mint avec proprietaire = adresse nulle ===");
        vm.prank(G);
        try v3.mint(address(0), _m(100 ether, uint64(block.timestamp + 1000), 3), pay) returns (uint256) {
            console2.log("   mint ACCEPTE un proprietaire nul");
        } catch Error(string memory r) { console2.log("   refuse :", r); }
    }

    // 2 — un parent EXPIRE peut-il encore engendrer ?
    function test_B_parent_expire_engendre() public {
        address[] memory pay = new address[](1); pay[0] = P;
        uint64 vu = uint64(block.timestamp + 100);
        vm.prank(G);
        uint256 parent = v3.mint(A, _m(100 ether, vu, 3), pay);

        vm.warp(block.timestamp + 500); // le parent est expire
        console2.log("=== B. Un parent EXPIRE peut-il engendrer ? ===");
        console2.log("   parent actif ? :", v3.isActive(parent));

        vm.prank(A);
        try v3.spawn(parent, A, _m(40 ether, vu, 2), pay) returns (uint256 c) {
            console2.log("   spawn ACCEPTE. enfant cree :", c);
            console2.log("   enfant actif ? :", v3.isActive(c));
        } catch Error(string memory r) { console2.log("   spawn refuse :", r); }
    }

    // 3 — un enfant avec proprietaire nul brule-t-il le budget du parent ?
    function test_C_enfant_nul_brule_le_budget() public {
        address[] memory pay = new address[](1); pay[0] = P;
        vm.prank(G);
        uint256 parent = v3.mint(A, _m(100 ether, 0, 3), pay);
        console2.log("=== C. Enfant a proprietaire nul et budget du parent ===");
        console2.log("   budget disponible avant :", v3.availableBudget(parent));
        vm.prank(A);
        try v3.spawn(parent, address(0), _m(40 ether, 0, 2), pay) returns (uint256 c) {
            console2.log("   spawn ACCEPTE, enfant :", c);
            console2.log("   cet enfant existe-t-il ? proprietaire :", v3.ownerOf(c));
            console2.log("   budget disponible apres :", v3.availableBudget(parent));
            console2.log("   -> budget consomme par un agent sans proprietaire");
        } catch Error(string memory r) { console2.log("   spawn refuse :", r); }
    }
}
