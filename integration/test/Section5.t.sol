// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";

// Sa source, importée telle quelle depuis le clone gitignoré. Aucune modification.
import {AggregateBudgetCursor} from "bounded/AggregateBudgetCursor.sol";

// Les nôtres.
import {InheritableAgentMandate} from "adn/InheritableAgentMandate.sol";
import {MandateAwareAggregateCursor, IAggregateBudget} from "adn/MandateAwareAggregateCursor.sol";

/**
 * Section 5 — notre compteur de lignée à côté du sien, non modifié.
 * Chaque appel est encadré et son issue imprimée telle quelle.
 */
contract Section5Test is Test {
    MandateAwareAggregateCursor ours;
    AggregateBudgetCursor his;
    InheritableAgentMandate mandate;

    address issuer = makeAddr("issuer");
    address rootAgent = makeAddr("rootAgent");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint256 constant CAP = 100 ether;
    address constant PAYEE = address(0xdEaD);

    function setUp() public {
        mandate = new InheritableAgentMandate(address(this));
        ours = new MandateAwareAggregateCursor(address(mandate));
        his = new AggregateBudgetCursor();
    }

    function _payees() internal pure returns (address[] memory p) {
        p = new address[](1);
        p[0] = PAYEE;
    }

    function _reason(bytes memory low) internal pure returns (string memory) {
        if (low.length < 4) return "revert sans donnee";
        bytes4 sel = bytes4(low[0]) | (bytes4(low[1]) >> 8) | (bytes4(low[2]) >> 16) | (bytes4(low[3]) >> 24);
        if (sel == MandateAwareAggregateCursor.MandateFrozen.selector) return "MandateFrozen(agent, agentId)";
        if (sel == MandateAwareAggregateCursor.RootCapExceeded.selector) return "RootCapExceeded()";
        if (sel == MandateAwareAggregateCursor.NodeCapExceeded.selector) return "NodeCapExceeded()";
        if (sel == MandateAwareAggregateCursor.CappedNodeCannotDelegate.selector) return "CappedNodeCannotDelegate()";
        if (sel == MandateAwareAggregateCursor.PathRevoked.selector) return "PathRevoked()";
        return vm.toString(sel);
    }

    // ------------------------------------------------------------------ N1
    function test_N1_conservation() public {
        console2.log("=== N1 - conservation (falsifiable) ===");
        vm.prank(issuer);
        bytes32 rootId = ours.createRoot(rootAgent, CAP, 0, 0, bytes32("n1"));
        console2.log("cap de la racine (wei) :", CAP);

        vm.prank(rootAgent);
        uint64 a = ours.delegate(rootId, 0, alice, 0);
        vm.prank(rootAgent);
        uint64 b = ours.delegate(rootId, 0, bob, 0);
        console2.log("fan-out : deux enfants de la racine, nodeId", a, "et", b);

        vm.prank(alice);
        uint64 c = ours.delegate(rootId, a, alice, 30 ether);
        console2.log("petit-enfant plafonne a 30, nodeId :", c);

        vm.prank(rootAgent);
        ours.draw(rootId, 0, 40 ether);
        vm.prank(alice);
        ours.draw(rootId, a, 20 ether);
        vm.prank(bob);
        ours.draw(rootId, b, 25 ether);
        console2.log("apres 40 + 20 + 25 :");
        console2.log("   spentRoot rendu     :", ours.spentRoot(rootId, 0));
        console2.log("   remainingRoot rendu :", ours.remainingRoot(rootId));

        console2.log("tentative de tirage de 20 (total demande 105 > cap 100) :");
        vm.prank(alice);
        try ours.draw(rootId, c, 20 ether) {
            console2.log("   issue : aboutit");
        } catch (bytes memory low) {
            console2.log("   issue : reverte -", _reason(low));
        }
        console2.log("   spentRoot rendu apres :", ours.spentRoot(rootId, 0));
        console2.log("   somme des draw admis <= cap ? rendu :", ours.spentRoot(rootId, 0) <= CAP);
    }

    // ------------------------------------------------------------------ N2
    function test_N2_conformite() public view {
        console2.log("=== N2 - conformite (falsifiable) ===");
        console2.log("supportsInterface(0xc7cabe86) rendu :", ours.supportsInterface(0xc7cabe86));
        console2.log("supportsInterface(0x01ffc9a7) rendu :", ours.supportsInterface(0x01ffc9a7));
        console2.log("supportsInterface(0xffffffff) rendu :", ours.supportsInterface(0xffffffff));
        console2.log("supportsInterface(0xdeadbeef) rendu :", ours.supportsInterface(0xdeadbeef));
        console2.log("le sien, supportsInterface(0xc7cabe86) rendu :", his.supportsInterface(0xc7cabe86));
    }

    // ------------------------------------------------------------------ N3
    function test_N3_pont() public {
        console2.log("=== N3 - le pont (ILLUSTRATION : le refus est code par nous) ===");
        uint256 parentId = mandate.mint(
            alice,
            InheritableAgentMandate.Mandate({maxSpendWei: CAP, telomere: 3, requireLease: true, frozen: false}),
            _payees()
        );
        vm.prank(alice);
        ours.bindAgent(parentId);
        console2.log("adresse d'alice adossee a l'agentId :", ours.boundAgentId(alice));

        vm.prank(issuer);
        bytes32 rootId = ours.createRoot(alice, CAP, 0, 0, bytes32("n3"));
        vm.prank(alice);
        uint64 child = ours.delegate(rootId, 0, alice, 0);

        vm.prank(alice);
        ours.draw(rootId, child, 10 ether);
        console2.log("avant gel - draw(10) aboutit, spentRoot rendu :", ours.spentRoot(rootId, 0));

        mandate.freeze(parentId);
        console2.log("freeze(mandat d'alice) execute, SANS appel a revoke");
        console2.log("mandate.isActive rendu   :", mandate.isActive(parentId));
        console2.log("isPathActive rendu       :", ours.isPathActive(rootId, child));

        vm.prank(alice);
        try ours.draw(rootId, child, 10 ether) {
            console2.log("draw apres gel : aboutit");
        } catch (bytes memory low) {
            console2.log("draw apres gel : reverte -", _reason(low));
        }
        console2.log("spentRoot rendu apres :", ours.spentRoot(rootId, 0));
    }

    // ----------------------------------------------------------------- N3b
    function test_N3b_vue_additive() public {
        console2.log("=== N3b - isPathActive (spec) vs isDrawable (additive) ===");
        uint256 agentId = mandate.mint(
            alice,
            InheritableAgentMandate.Mandate({maxSpendWei: CAP, telomere: 3, requireLease: true, frozen: false}),
            _payees()
        );
        vm.prank(alice);
        ours.bindAgent(agentId);

        vm.prank(issuer);
        bytes32 rootId = ours.createRoot(alice, CAP, 0, 0, bytes32("n3b"));
        vm.prank(alice);
        uint64 child = ours.delegate(rootId, 0, alice, 0);

        console2.log("avant gel - isPathActive rendu :", ours.isPathActive(rootId, child));
        console2.log("avant gel - isDrawable   rendu :", ours.isDrawable(rootId, child));

        mandate.freeze(agentId);
        console2.log("freeze(mandat) execute, sans revoke");
        console2.log("apres gel - isPathActive rendu :", ours.isPathActive(rootId, child));
        console2.log("apres gel - isDrawable   rendu :", ours.isDrawable(rootId, child));

        vm.prank(alice);
        try ours.draw(rootId, child, 1 ether) {
            console2.log("draw : aboutit");
        } catch (bytes memory low) {
            console2.log("draw : reverte -", _reason(low));
        }

        console2.log("--- apres un revoke explicite, en plus du gel ---");
        vm.prank(issuer);
        ours.revoke(rootId, child);
        console2.log("isPathActive rendu :", ours.isPathActive(rootId, child));
        console2.log("isDrawable   rendu :", ours.isDrawable(rootId, child));

        console2.log("--- noeud sans mandat adosse (comportement de reference) ---");
        vm.prank(issuer);
        bytes32 r2 = ours.createRoot(bob, CAP, 0, 0, bytes32("n3b-libre"));
        vm.prank(bob);
        uint64 free = ours.delegate(r2, 0, bob, 0);
        console2.log("isPathActive rendu :", ours.isPathActive(r2, free));
        console2.log("isDrawable   rendu :", ours.isDrawable(r2, free));
    }

    // ------------------------------------------------------------------ N4
    function test_N4_contraste() public {
        console2.log("=== N4 - SON cursor non modifie, meme gel (MESURE) ===");
        uint256 parentId = mandate.mint(
            alice,
            InheritableAgentMandate.Mandate({maxSpendWei: CAP, telomere: 3, requireLease: true, frozen: false}),
            _payees()
        );
        vm.prank(issuer);
        bytes32 rootId = his.createRoot(alice, CAP, 0, 0, bytes32("n4"));
        vm.prank(alice);
        uint64 child = his.delegate(rootId, 0, alice, 0);

        mandate.freeze(parentId);
        console2.log("mandate.isActive rendu       :", mandate.isActive(parentId));
        console2.log("son isPathActive rendu       :", his.isPathActive(rootId, child));

        vm.prank(alice);
        try his.draw(rootId, child, 10 ether) {
            console2.log("son draw, mandat gele : aboutit");
        } catch (bytes memory low) {
            console2.log("son draw, mandat gele : reverte -", _reason(low));
        }
        console2.log("son spentRoot rendu :", his.spentRoot(rootId, 0));

        console2.log("--- il faut un revoke manuel ---");
        vm.prank(issuer);
        his.revoke(rootId, child);
        console2.log("son isPathActive apres revoke rendu :", his.isPathActive(rootId, child));
    }

    // ------------------------------------------------------- identite
    function test_identite_soulbound() public {
        console2.log("=== identite : adresse adossee vs adresse libre (ILLUSTRATION) ===");
        uint256 agentId = mandate.mint(
            alice,
            InheritableAgentMandate.Mandate({maxSpendWei: CAP, telomere: 3, requireLease: true, frozen: false}),
            _payees()
        );
        console2.log("proprietaire de l'agentId rendu :", mandate.ownerOf(agentId));

        console2.log("bob tente d'adosser son adresse a l'agentId d'alice :");
        vm.prank(bob);
        try ours.bindAgent(agentId) {
            console2.log("   issue : aboutit");
        } catch (bytes memory low) {
            console2.log("   issue : reverte -", _reason(low));
        }

        vm.prank(alice);
        ours.bindAgent(agentId);
        console2.log("alice adosse la sienne, boundAgentId(alice) rendu :", ours.boundAgentId(alice));
        console2.log("boundAgentId(bob) rendu :", ours.boundAgentId(bob));
        console2.log("le mandat expose-t-il un transfert ? (chercher 'transfer' dans son ABI)");
    }
}
