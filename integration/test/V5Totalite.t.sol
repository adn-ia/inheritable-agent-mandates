// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {InheritableAgentMandateV5} from "adn/InheritableAgentMandateV5.sol";

/// Les trois regles portees le 26/08, degagees avec zexoverz.
contract V5TotaliteTest is Test {
    InheritableAgentMandateV5 v5;
    address G; address A; address P;
    uint64 constant T0 = 1_000_000;
    uint32 constant PER = 30 days;

    function setUp() public {
        G = makeAddr("g"); A = makeAddr("a"); P = makeAddr("p");
        vm.warp(T0);
        vm.prank(G); v5 = new InheritableAgentMandateV5(G);
    }
    function _m(uint256 c, uint64 st, uint32 len, uint16 n, uint16 te)
        internal pure returns (InheritableAgentMandateV5.Mandate memory) {
        return InheritableAgentMandateV5.Mandate({maxSpendWei:c, periodStart:st,
            periodLength:len, periodCount:n, telomere:te, requireLease:true, frozen:false});
    }

    // 1 — l'echeance effective est le MINIMUM de la chaine
    function test_1_minimum_de_chaine() public {
        address[] memory pay = new address[](1); pay[0] = P;
        vm.prank(G);
        uint256 gp = v5.mint(A, _m(100 ether, T0, PER, 12, 3), pay);
        vm.prank(A);
        uint256 ch = v5.spawn(gp, A, _m(40 ether, T0, PER * 6, 2, 2), pay);

        console2.log("=== 1. Echeance effective = min sur la chaine ===");
        console2.log("   echeance PROPRE du grand-parent :", v5.currentExpiry(gp));
        console2.log("   echeance PROPRE de l'enfant     :", v5.currentExpiry(ch));
        console2.log("   echeance EFFECTIVE de l'enfant  :", v5.effectiveExpiry(ch));
        console2.log("   -> l'enfant est gouverne par son ancetre, pas par sa propre periode");
        console2.log("   effective == min ? :",
            v5.effectiveExpiry(ch) == v5.currentExpiry(gp));
    }

    // 2 — isActive ne revele JAMAIS
    function test_2_isactive_ne_revele_jamais() public {
        console2.log("=== 2. Totalite : isActive ne revele jamais ===");
        console2.log("   sur un id inconnu (999)   :", v5.isActive(999));
        console2.log("   sur l'id 0                :", v5.isActive(0));
        address[] memory pay = new address[](1); pay[0] = P;
        vm.prank(G);
        uint256 id = v5.mint(A, _m(100 ether, T0, PER, 12, 3), pay);
        console2.log("   sur un agent sain         :", v5.isActive(id));
        vm.warp(type(uint64).max - 1);
        console2.log("   au bout du temps (uint64 max) :", v5.isActive(id));
        console2.log("   -> aucun revert dans les quatre cas");
    }

    // 3 — la periode longue de l'enfant ne l'aide plus
    function test_3_periode_longue_n_aide_plus() public {
        address[] memory pay = new address[](1); pay[0] = P;
        vm.prank(G);
        uint256 gp = v5.mint(A, _m(100 ether, T0, PER, 12, 3), pay);
        vm.prank(A);
        uint256 ch = v5.spawn(gp, A, _m(40 ether, T0, PER * 6, 2, 2), pay);
        vm.warp(T0 + uint64(PER) * 2); // le grand-parent n'a pas renouvele
        console2.log("=== 3. Une periode plus longue achete-t-elle de la survie ? ===");
        console2.log("   grand-parent actif ? :", v5.isActive(gp));
        console2.log("   enfant actif ?       :", v5.isActive(ch));
        console2.log("   -> ce qui reste est une perte de VIVACITE pour l'enfant,");
        console2.log("      pas un gain de survie. Donc pas un MUST.");
    }
}
