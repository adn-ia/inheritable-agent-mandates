// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {InheritableAgentMandateV5} from "adn/InheritableAgentMandateV5.sol";

/// Les six defauts trouves par DeepSeek. Chacun rejoue apres correction.
contract V5SixDefautsTest is Test {
    InheritableAgentMandateV5 v5;
    address G; address A; address P;
    uint64 constant T0 = 1_000_000;
    uint32 constant PER = 30 days;

    function setUp() public {
        G = makeAddr("g"); A = makeAddr("a"); P = makeAddr("p");
        vm.warp(T0);
        vm.prank(G);
        v5 = new InheritableAgentMandateV5(G);
    }

    function _m(uint256 cap, uint64 st, uint32 len, uint16 cnt, uint16 telo)
        internal pure returns (InheritableAgentMandateV5.Mandate memory)
    {
        return InheritableAgentMandateV5.Mandate({
            maxSpendWei: cap, periodStart: st, periodLength: len,
            periodCount: cnt, telomere: telo, requireLease: true, frozen: false
        });
    }

    function _root() internal returns (uint256) {
        address[] memory pay = new address[](1); pay[0] = P;
        vm.prank(G);
        return v5.mint(A, _m(100 ether, T0, PER, 12, 3), pay);
    }

    function test_1_bail_malforme_sous_parent_sans_bail() public {
        address[] memory pay = new address[](1); pay[0] = P;
        vm.prank(G);
        uint256 parent = v5.mint(A, _m(100 ether, 0, 0, 0, 3), pay); // parent SANS bail
        console2.log("=== 1. Enfant a bail malforme (periodCount=0) sous parent sans bail ===");
        vm.prank(A);
        try v5.spawn(parent, A, _m(40 ether, T0, 100, 0, 2), pay) returns (uint256) {
            console2.log("   ACCEPTE - le defaut subsiste");
        } catch Error(string memory r) { console2.log("   refuse :", r); }
    }

    function test_2_parent_expire_ne_peut_plus_engendrer() public {
        uint256 parent = _root();
        address[] memory pay = new address[](1); pay[0] = P;
        vm.warp(T0 + uint64(PER) * 2); // le parent a expire
        console2.log("=== 2. Un parent expire peut-il engendrer ? ===");
        console2.log("   parent actif ? :", v5.isActive(parent));
        vm.prank(A);
        try v5.spawn(parent, A, _m(40 ether, T0, PER, 2, 2), pay) returns (uint256) {
            console2.log("   ACCEPTE - le defaut subsiste");
        } catch Error(string memory r) { console2.log("   refuse :", r); }
    }

    function test_3_bail_pas_commence() public {
        address[] memory pay = new address[](1); pay[0] = P;
        vm.prank(G);
        uint256 id = v5.mint(A, _m(100 ether, T0 + 100_000, PER, 12, 3), pay);
        console2.log("=== 3. Bail qui commence dans le FUTUR ===");
        console2.log("   maintenant     :", block.timestamp);
        console2.log("   debut du bail  :", T0 + 100_000);
        console2.log("   actif ?        :", v5.isActive(id));
    }

    function test_4_proprietaire_enfant_nul() public {
        uint256 parent = _root();
        address[] memory pay = new address[](1); pay[0] = P;
        console2.log("=== 4. Enfant a proprietaire nul (brulage de budget) ===");
        console2.log("   budget avant :", v5.availableBudget(parent));
        vm.prank(A);
        try v5.spawn(parent, address(0), _m(40 ether, T0, PER, 2, 2), pay) returns (uint256) {
            console2.log("   ACCEPTE - budget brule :", v5.availableBudget(parent));
        } catch Error(string memory r) { console2.log("   refuse :", r); }
    }

    function test_5_resurrection_d_un_expire() public {
        uint256 id = _root();
        vm.warp(T0 + uint64(PER) * 2); // expire (periodsUsed = 1)
        console2.log("=== 5. Peut-on ressusciter un agent expire ? ===");
        console2.log("   actif ? :", v5.isActive(id));
        vm.prank(G);
        try v5.renew(id) { console2.log("   renew ACCEPTE - resurrection possible"); }
        catch Error(string memory r) { console2.log("   renew refuse :", r); }

        console2.log("   -- et un agent GELE ? --");
        uint256 id2 = _root();
        vm.prank(G); v5.freeze(id2);
        vm.prank(G);
        try v5.renew(id2) { console2.log("   renew ACCEPTE sur un gele"); }
        catch Error(string memory r) { console2.log("   renew refuse :", r); }
    }

    function test_6_debordement_uint64() public {
        address[] memory pay = new address[](1); pay[0] = P;
        console2.log("=== 6. Bail qui deborde uint64 ===");
        vm.prank(G);
        try v5.mint(A, _m(100 ether, type(uint64).max - 10, 1000, 1000, 3), pay) returns (uint256) {
            console2.log("   ACCEPTE - blocage permanent possible");
        } catch Error(string memory r) { console2.log("   refuse :", r); }
    }
}
