// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {InheritableAgentMandateV5} from "adn/InheritableAgentMandateV5.sol";

/// La reprise : le chemin descendant qu'`allocatedOf` n'avait pas.
/// Construit pendant ETHOnline 2026. Le defaut ferme est mesure au test 1.
contract V5RepriseTest is Test {
    InheritableAgentMandateV5 v5;
    address G; address A; address B; address P;
    uint64 constant T0 = 1_000_000;
    uint32 constant PER = 30 days;

    function setUp() public {
        G = makeAddr("g"); A = makeAddr("a"); B = makeAddr("b"); P = makeAddr("p");
        vm.warp(T0);
        vm.prank(G); v5 = new InheritableAgentMandateV5(G);
    }

    function _m(uint256 c, uint64 st, uint32 len, uint16 n, uint16 te)
        internal pure returns (InheritableAgentMandateV5.Mandate memory) {
        return InheritableAgentMandateV5.Mandate({maxSpendWei:c, periodStart:st,
            periodLength:len, periodCount:n, telomere:te, requireLease:true, frozen:false});
    }
    function _pay() internal view returns (address[] memory a) {
        a = new address[](1); a[0] = P;
    }

    // ── 1 ────────────────────────────────────────────────────────────────────
    // LE DEFAUT, MESURE. Un enfant mort immobilisait sa tranche pour toujours.
    function test_1_le_budget_ne_saignait_que_dans_un_sens() public {
        vm.prank(G);
        uint256 parent = v5.mint(A, _m(100 ether, T0, PER, 12, 3), _pay());

        console2.log("=== 1. Ce que la reprise ferme ===");
        console2.log("   budget libre du parent au depart :", v5.availableBudget(parent));

        vm.prank(A);
        uint256 enfant = v5.spawn(parent, B, _m(40 ether, T0, PER, 1, 2), _pay());
        console2.log("   apres naissance d'un enfant a 40 :", v5.availableBudget(parent));

        // L'enfant meurt de sa propre horloge. Personne n'a besoin de sa cooperation.
        vm.warp(T0 + PER + 1);
        console2.log("   l'enfant est-il mort ?            :", v5.isDead(enfant));
        console2.log("   budget libre, enfant mort         :", v5.availableBudget(parent));
        console2.log("   -> avant la reprise, ces 40 etaient perdus pour toujours");

        vm.prank(A);
        uint256 rendu = v5.reclaim(enfant);
        console2.log("   rendu par la reprise              :", rendu);
        console2.log("   budget libre apres reprise        :", v5.availableBudget(parent));

        assertEq(rendu, 40 ether);
        assertEq(v5.availableBudget(parent), 100 ether);
    }

    // ── 2 ────────────────────────────────────────────────────────────────────
    // Et le parent peut reellement s'en resservir : la preuve est un nouvel enfant.
    function test_2_le_budget_rendu_est_reutilisable() public {
        vm.prank(G);
        uint256 parent = v5.mint(A, _m(100 ether, T0, PER, 12, 3), _pay());
        vm.prank(A);
        uint256 mort = v5.spawn(parent, B, _m(100 ether, T0, PER, 1, 2), _pay());

        vm.warp(T0 + PER + 1);
        vm.prank(A); v5.reclaim(mort);
        vm.warp(T0);                       // le parent, lui, est toujours dans son bail

        vm.prank(A);
        uint256 neuf = v5.spawn(parent, B, _m(100 ether, T0, PER, 1, 2), _pay());
        console2.log("=== 2. La tranche rendue reprend du service ===");
        console2.log("   nouvel enfant ne avec le budget rendu, id :", neuf);
        assertTrue(neuf != 0);
        assertEq(v5.availableBudget(parent), 0);
    }

    // ── 3 ────────────────────────────────────────────────────────────────────
    // On ne rend que le RESTE NON ALLOUE. La reprise remonte depuis le bas.
    function test_3_la_reprise_remonte_une_generation_a_la_fois() public {
        vm.prank(G);
        uint256 gp = v5.mint(A, _m(100 ether, T0, PER, 12, 3), _pay());
        vm.prank(A);
        uint256 pere = v5.spawn(gp, A, _m(60 ether, T0, PER, 1, 2), _pay());
        vm.prank(A);
        uint256 fils = v5.spawn(pere, B, _m(25 ether, T0, PER, 1, 1), _pay());

        vm.warp(T0 + PER + 1);   // les deux baux d'une periode sont echus

        console2.log("=== 3. Une generation a la fois ===");
        console2.log("   reprenable sur le pere (60 - 25) :", v5.reclaimableOf(pere));
        vm.prank(A);
        uint256 r1 = v5.reclaim(pere);
        console2.log("   rendu au grand-pere              :", r1);
        console2.log("   budget libre du grand-pere       :", v5.availableBudget(gp));
        assertEq(r1, 35 ether);

        console2.log("   puis on reprend le fils          :", v5.reclaimableOf(fils));
        vm.prank(A);
        uint256 r2 = v5.reclaim(fils);
        console2.log("   rendu au pere                    :", r2);
        console2.log("   budget libre du pere             :", v5.availableBudget(pere));
        assertEq(r2, 25 ether);
        assertEq(v5.availableBudget(pere), 60 ether);
        console2.log("   -> rien n'a ete compte deux fois");
    }

    // ── 4 ────────────────────────────────────────────────────────────────────
    // LE POINT DE CONCEPTION : mort PROPRE, pas mort heritee.
    function test_4_la_mort_d_autrui_n_est_pas_la_sienne() public {
        vm.prank(G);
        uint256 parent = v5.mint(A, _m(100 ether, T0, PER, 12, 3), _pay());
        vm.prank(A);
        uint256 enfant = v5.spawn(parent, B, _m(40 ether, T0, PER, 12, 2), _pay());

        vm.prank(G); v5.freeze(parent);

        console2.log("=== 4. Un enfant vivant sous un parent gele ===");
        console2.log("   isActive(enfant) :", v5.isActive(enfant));
        console2.log("   isDead(enfant)   :", v5.isDead(enfant));
        console2.log("   reprenable ?     :", v5.reclaimableOf(enfant));
        assertFalse(v5.isActive(enfant));   // il ne peut plus agir
        assertFalse(v5.isDead(enfant));     // mais il n'est pas mort, lui
        assertEq(v5.reclaimableOf(enfant), 0);

        vm.prank(G);
        vm.expectRevert("child not dead");
        v5.reclaim(enfant);
        console2.log("   -> geler la racine ne confisque pas le budget des descendants");
    }

    // ── 5 ────────────────────────────────────────────────────────────────────
    // Le gel de l'enfant, lui, ouvre la reprise : atteignable sans sa cooperation.
    function test_5_le_gel_de_l_enfant_ouvre_la_reprise() public {
        vm.prank(G);
        uint256 parent = v5.mint(A, _m(100 ether, T0, PER, 12, 3), _pay());
        vm.prank(A);
        uint256 enfant = v5.spawn(parent, B, _m(40 ether, T0, PER, 12, 2), _pay());

        vm.prank(G); v5.freeze(enfant);
        console2.log("=== 5. Gel de l'enfant ===");
        console2.log("   isDead(enfant) :", v5.isDead(enfant));
        vm.prank(G);
        uint256 rendu = v5.reclaim(enfant);
        console2.log("   rendu          :", rendu);
        assertEq(rendu, 40 ether);
    }

    // ── 6 ────────────────────────────────────────────────────────────────────
    // La reprise n'ecrit RIEN dans le mandat : l'identite ne bouge pas.
    function test_6_la_reprise_ne_touche_pas_a_l_identite() public {
        vm.prank(G);
        uint256 parent = v5.mint(A, _m(100 ether, T0, PER, 12, 3), _pay());
        vm.prank(A);
        uint256 enfant = v5.spawn(parent, B, _m(40 ether, T0, PER, 1, 2), _pay());

        bytes32 avant = v5.mandateRoot(enfant);
        vm.warp(T0 + PER + 1);
        vm.prank(A); v5.reclaim(enfant);
        bytes32 apres = v5.mandateRoot(enfant);

        console2.log("=== 6. L'identite survit a la reprise ===");
        console2.log("   racine identique ? :", avant == apres);
        assertEq(avant, apres);
        console2.log("   -> mettre le plafond a zero aurait ete intuitif, et aurait");
        console2.log("      detache toute enveloppe ERC-8312 epinglee sur cette racine");
    }

    // ── 7 ────────────────────────────────────────────────────────────────────
    // Les refus : rejeu, genese, appelant sans titre.
    function test_7_les_trois_refus() public {
        vm.prank(G);
        uint256 parent = v5.mint(A, _m(100 ether, T0, PER, 12, 3), _pay());
        vm.prank(A);
        uint256 enfant = v5.spawn(parent, B, _m(40 ether, T0, PER, 1, 2), _pay());
        vm.warp(T0 + PER + 1);

        console2.log("=== 7. Ce que la reprise refuse ===");

        vm.prank(B);
        vm.expectRevert("not parent owner nor guardian");
        v5.reclaim(enfant);
        console2.log("   un tiers                 : REFUSE");

        vm.prank(A); v5.reclaim(enfant);
        vm.prank(A);
        vm.expectRevert("already reclaimed");
        v5.reclaim(enfant);
        console2.log("   le rejeu                 : REFUSE");

        vm.prank(G);
        vm.expectRevert("genesis has no parent");
        v5.reclaim(parent);
        console2.log("   la genese                : REFUSE");
    }
}
