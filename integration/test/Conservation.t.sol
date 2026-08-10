// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {InheritableAgentMandateV3} from "adn/InheritableAgentMandateV3.sol";

/**
 * L'invariant de conservation, sur InheritableAgentMandateV3.
 *
 * `enfant <= parent` seul laissait passer une evasion par FAN-OUT : dix enfants a
 * 100 % du plafond parent chacun font 1000 %. Le contrat comptabilise desormais ce
 * qu'un parent a distribue (`allocatedOf`) et refuse au-dela du reste.
 *
 * Le dernier test encode une LIMITE de ce dispositif, telle qu'observee  pas telle
 * qu'on l'aurait voulue.
 */
contract ConservationTest is Test {
    InheritableAgentMandateV3 m;

    address guardian = address(this);
    address owner = makeAddr("owner");
    address kid = makeAddr("kid");
    address[] noPayees;

    function setUp() public { m = new InheritableAgentMandateV3(guardian); }

    function _m(uint256 cap, uint16 tel) internal pure returns (InheritableAgentMandateV3.Mandate memory) {
        return InheritableAgentMandateV3.Mandate({
            maxSpendWei: cap, validUntil: 0, telomere: tel, requireLease: false, frozen: false });
    }

    // 1) le budget d'une racine fraiche est entierement disponible
    function test_racine_fraiche() public {
        uint256 root = m.mint(owner, _m(500, 8), noPayees);
        assertEq(m.allocatedOf(root), 0);
        assertEq(m.availableBudget(root), 500);
    }

    // 2) un spawn debite le parent
    function test_spawn_debite() public {
        uint256 root = m.mint(owner, _m(500, 8), noPayees);
        vm.prank(owner);
        m.spawn(root, kid, _m(200, 7), noPayees);
        assertEq(m.allocatedOf(root), 200);
        assertEq(m.availableBudget(root), 300);
    }

    // 3) LE test qui compte : 2e enfant alors que le parent est a sec -> REVERT
    function test_fanout_refuse() public {
        uint256 root = m.mint(owner, _m(500, 8), noPayees);
        vm.prank(owner);
        m.spawn(root, kid, _m(500, 7), noPayees);            // consomme tout
        assertEq(m.availableBudget(root), 0);
        vm.prank(owner);
        vm.expectRevert(bytes("conservation: exceeds parent unallocated budget"));
        m.spawn(root, kid, _m(1, 7), noPayees);              // le moindre wei de trop
    }

    // 4) partition legitime : 250 + 250 sous un parent 500 -> les deux passent ; le 3e revert
    function test_partition_ok_puis_refus() public {
        uint256 root = m.mint(owner, _m(500, 8), noPayees);
        vm.startPrank(owner);
        m.spawn(root, kid, _m(250, 7), noPayees);
        m.spawn(root, kid, _m(250, 7), noPayees);
        assertEq(m.availableBudget(root), 0);
        vm.expectRevert(bytes("conservation: exceeds parent unallocated budget"));
        m.spawn(root, kid, _m(1, 7), noPayees);
        vm.stopPrank();
    }

    // 5) LA LIMITE, telle qu'observee : la conservation borne ce qu'un parent
    //    DISTRIBUE, pas ce que l'arbre peut CONSOMMER. Un parent qui a tout alloue
    //    garde son propre plafond intact : `allocatedOf` n'entame pas `maxSpendWei`.
    //    Capacite cumulee parent + enfant = 2 x le plafond de la racine.
    function test_LIMITE_la_conservation_borne_la_distribution_pas_la_consommation() public {
        uint256 root = m.mint(owner, _m(500, 8), noPayees);
        vm.prank(owner);
        uint256 child = m.spawn(root, kid, _m(500, 7), noPayees);

        (uint256 rootCap,,,,) = m.mandateOf(root);
        (uint256 childCap,,,,) = m.mandateOf(child);

        console2.log("   racine  : maxSpendWei =", rootCap, " allocatedOf =", m.allocatedOf(root));
        console2.log("   enfant  : maxSpendWei =", childCap);
        console2.log("   availableBudget(racine) =", m.availableBudget(root));

        // le plafond de la racine n'est PAS reduit par ce qu'elle a distribue
        assertEq(rootCap, 500, "le plafond de la racine a ete entame");
        assertEq(m.availableBudget(root), 0, "il ne reste rien a distribuer");
        assertEq(childCap, 500, "l'enfant porte bien 500");

        // capacite de depense cumulee : 2 x le plafond de la racine
        console2.log("   capacite cumulee racine + enfant =", rootCap + childCap);
        assertEq(rootCap + childCap, 1000, "comportement reel : 2 x 500");
        console2.log("   -> la conservation borne la DISTRIBUTION, pas la CONSOMMATION.");
        console2.log("      La depense reelle est comptee ailleurs (spent[] du gate), et");
        console2.log("      `allocatedOf` n'y entre pas. Limite nommee, pas corrigee ici.");
    }

    // 5bis) seconde face de la meme limite : le gardien peut minter une racine de plus,
    //       sans plafond global. La conservation est PAR LIGNEE, pas pour l'emission.
    function test_LIMITE_le_gardien_peut_minter_des_racines_sans_plafond() public {
        uint256 a = m.mint(owner, _m(500, 8), noPayees);
        uint256 b = m.mint(owner, _m(1_000_000, 8), noPayees);
        console2.log("   racine a :", m.availableBudget(a));
        console2.log("   racine b :", m.availableBudget(b));
        assertEq(m.availableBudget(b), 1_000_000, "aucune borne a l'emission de racines");
        console2.log("   -> l'invariant ne contraint que la descendance d'une racine donnee.");
    }
}
