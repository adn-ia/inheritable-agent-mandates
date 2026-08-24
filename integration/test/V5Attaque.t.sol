// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {InheritableAgentMandateV5} from "adn/InheritableAgentMandateV5.sol";

/// Tentative de casser V5. Periodes DESALIGNEES entre parent et enfant.
contract V5AttaqueTest is Test {
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

    function test_ancetre_expire_descendant_toujours_actif() public {
        address[] memory pay = new address[](1); pay[0] = P;

        // Grand-parent : 12 periodes de 30 jours -> fin absolue T0 + 360j
        vm.prank(G);
        uint256 gp = v5.mint(A, InheritableAgentMandateV5.Mandate({
            maxSpendWei: 100 ether, periodStart: T0, periodLength: PER,
            periodCount: 12, telomere: 3, requireLease: true, frozen: false
        }), pay);

        // Enfant : 2 periodes de 180 jours -> MEME fin absolue, periodes DESALIGNEES
        vm.prank(A);
        uint256 child = v5.spawn(gp, A, InheritableAgentMandateV5.Mandate({
            maxSpendWei: 40 ether, periodStart: T0, periodLength: PER * 6,
            periodCount: 2, telomere: 2, requireLease: true, frozen: false
        }), pay);

        console2.log("fin absolue grand-parent :", v5.absoluteEnd(gp));
        console2.log("fin absolue enfant       :", v5.absoluteEnd(child));
        console2.log("echeance courante gp     :", v5.currentExpiry(gp));
        console2.log("echeance courante enfant :", v5.currentExpiry(child));

        // Le grand-parent ne renouvelle jamais. On avance de 2 periodes de 30j.
        vm.warp(T0 + uint64(PER) * 2);
        console2.log("");
        console2.log("--- a T0 + 60 jours ---");
        console2.log("grand-parent actif ? :", v5.isActive(gp));
        console2.log("enfant actif ?       :", v5.isActive(child));

        uint64 ecart = v5.currentExpiry(child) - v5.currentExpiry(gp);
        console2.log("");
        console2.log("l'enfant survit a son ancetre expire de (secondes) :", ecart);
        console2.log("soit en jours :", ecart / 1 days);
        console2.log("une periode de l'enfant vaut (jours) :", uint256(PER) * 6 / 1 days);
    }
}
