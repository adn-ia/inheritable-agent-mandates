// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2, Vm} from "forge-std/Test.sol";
import {MandateWithException} from "adn/MandateWithException.sol";

/**
 * La couture — C1→C7. Chaque appel est encadré, son issue imprimée telle quelle.
 * Aucune valeur attendue n'est écrite ici : le contrat décide, le test rapporte.
 */
contract CoutureExceptionTest is Test {
    MandateWithException m;

    address agent = makeAddr("agent");
    address g1 = makeAddr("gardien1");
    address g2 = makeAddr("gardien2");
    address g3 = makeAddr("gardien3");
    address outsider = makeAddr("outsider");

    bytes32 constant CAT = bytes32("ops");
    bytes32 constant OTHER = bytes32("autre");
    bytes32 constant BET = keccak256("le paiement debloque la livraison sous 48h");
    bytes32 constant READ = keccak256("lecture neutre datee avant le resultat");

    uint256 constant CAP = 1000;
    uint256 constant MAX_EXC = 500;
    uint256 constant BIG = 200;
    uint256 constant BIG_APPROVALS = 2;

    uint256 budgetId;

    function setUp() public {
        address[] memory gs = new address[](3);
        gs[0] = g1;
        gs[1] = g2;
        gs[2] = g3;
        m = new MandateWithException(gs, MAX_EXC, BIG, BIG_APPROVALS);
        budgetId = m.createBudget(agent, CAP);
    }

    function _reason(bytes memory low) internal pure returns (string memory) {
        if (low.length < 4) return "revert sans donnee";
        bytes4 s = bytes4(low[0]) | (bytes4(low[1]) >> 8) | (bytes4(low[2]) >> 16) | (bytes4(low[3]) >> 24);
        if (s == MandateWithException.CapExceeded.selector) return "CapExceeded";
        if (s == MandateWithException.NotGuardian.selector) return "NotGuardian";
        if (s == MandateWithException.AgentCannotGrant.selector) return "AgentCannotGrant";
        if (s == MandateWithException.ExceptionTooLarge.selector) return "ExceptionTooLarge";
        if (s == MandateWithException.MissingStatedBet.selector) return "MissingStatedBet";
        if (s == MandateWithException.MissingPreActionRead.selector) return "MissingPreActionRead";
        if (s == MandateWithException.NotEnoughApprovers.selector) return "NotEnoughApprovers";
        if (s == MandateWithException.ExceptionExpired.selector) return "ExceptionExpired";
        if (s == MandateWithException.ExceptionConsumed.selector) return "ExceptionConsumed";
        if (s == MandateWithException.WrongCategory.selector) return "WrongCategory";
        if (s == MandateWithException.AmountAboveException.selector) return "AmountAboveException";
        if (s == MandateWithException.ExceptionNotForThisBudget.selector) return "ExceptionNotForThisBudget";
        if (s == MandateWithException.ChildCapWider.selector) return "ChildCapWider";
        if (s == MandateWithException.AlreadyApproved.selector) return "AlreadyApproved";
        if (s == MandateWithException.NotAgent.selector) return "NotAgent";
        return vm.toString(s);
    }

    // =================================================================== C1
    function test_C1_refus_propre() public {
        console2.log("=== C1 - refus propre, puis exposition du residu ===");
        vm.prank(agent);
        m.draw(budgetId, CAT, 900);
        console2.log("   deja depense : 900 sur un cap de 1000");

        vm.prank(agent);
        try m.draw(budgetId, CAT, 300) {
            console2.log("   draw(300) : ABOUTIT");
        } catch (bytes memory low) {
            console2.log(string.concat("   draw(300) : REVERTE - ", _reason(low)));
        }

        vm.recordLogs();
        vm.prank(agent);
        m.requestException(budgetId, CAT, 300);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        console2.log("   requestException emis, nb d'events :", logs.length);
        (uint256 amount, uint256 room) = abi.decode(logs[0].data, (uint256, uint256));
        console2.log("   contexte de l'event - montant demande :", amount);
        console2.log("   contexte de l'event - place restante  :", room);
    }

    // =================================================================== C2
    function test_C2_grant_gardien() public {
        console2.log("=== C2 - un gardien accorde, le tirage passe une fois ===");
        vm.prank(agent);
        m.draw(budgetId, CAT, 900);

        vm.prank(g1);
        uint256 eid = m.proposeException(budgetId, CAT, 150, uint64(block.timestamp + 1 days), BET, READ);
        console2.log("   exception accordee, id :", eid);

        vm.prank(agent);
        try m.drawWithException(budgetId, eid, CAT, 150) {
            console2.log("   drawWithException(150) : ABOUTIT");
        } catch (bytes memory low) {
            console2.log(string.concat("   drawWithException(150) : REVERTE - ", _reason(low)));
        }
        (,,,,,, bool consumed,) = m.exceptionOf(eid);
        console2.log("   exception consommee ? rendu :", consumed);
        console2.log("   plafond effectif rendu :", m.effectiveCeiling(budgetId));

        console2.log("   -- second usage de la meme exception --");
        vm.prank(agent);
        try m.drawWithException(budgetId, eid, CAT, 150) {
            console2.log("   issue : ABOUTIT");
        } catch (bytes memory low) {
            console2.log(string.concat("   issue : REVERTE - ", _reason(low)));
        }
    }

    // =================================================================== C3
    function test_C3_auto_grant() public {
        console2.log("=== C3 - l'agent tente d'accorder sa propre exception (falsifiable) ===");

        console2.log("   -- l'agent, qui n'est pas gardien --");
        vm.prank(agent);
        try m.proposeException(budgetId, CAT, 100, uint64(block.timestamp + 1 days), BET, READ) returns (uint256) {
            console2.log("   issue : ABOUTIT");
        } catch (bytes memory low) {
            console2.log(string.concat("   issue : REVERTE - ", _reason(low)));
        }

        console2.log("   -- un budget dont l'agent EST aussi gardien --");
        uint256 b2 = m.createBudget(g1, CAP);
        vm.prank(g1);
        try m.proposeException(b2, CAT, 100, uint64(block.timestamp + 1 days), BET, READ) returns (uint256) {
            console2.log("   issue : ABOUTIT");
        } catch (bytes memory low) {
            console2.log(string.concat("   issue : REVERTE - ", _reason(low)));
        }

        console2.log("   -- un tiers non gardien --");
        vm.prank(outsider);
        try m.proposeException(budgetId, CAT, 100, uint64(block.timestamp + 1 days), BET, READ) returns (uint256) {
            console2.log("   issue : ABOUTIT");
        } catch (bytes memory low) {
            console2.log(string.concat("   issue : REVERTE - ", _reason(low)));
        }

        console2.log("   -- un gardien qui approuve une exception sur SON propre budget --");
        vm.prank(g2);
        uint256 eid = m.proposeException(b2, CAT, 300, uint64(block.timestamp + 1 days), BET, READ);
        vm.prank(g1);
        try m.approveException(eid) {
            console2.log("   issue : ABOUTIT");
        } catch (bytes memory low) {
            console2.log(string.concat("   issue : REVERTE - ", _reason(low)));
        }
    }

    // =================================================================== C4
    function test_C4_bornes() public {
        console2.log("=== C4 - bornes de l'exception (falsifiable) ===");

        console2.log("   -- accorder au-dela du plafond d'exception (600 > 500) --");
        vm.prank(g1);
        try m.proposeException(budgetId, CAT, 600, uint64(block.timestamp + 1 days), BET, READ) returns (uint256) {
            console2.log("   issue : ABOUTIT");
        } catch (bytes memory low) {
            console2.log(string.concat("   issue : REVERTE - ", _reason(low)));
        }

        console2.log("   -- accorder sans pari declare --");
        vm.prank(g1);
        try m.proposeException(budgetId, CAT, 100, uint64(block.timestamp + 1 days), bytes32(0), READ) returns (uint256)
        {
            console2.log("   issue : ABOUTIT");
        } catch (bytes memory low) {
            console2.log(string.concat("   issue : REVERTE - ", _reason(low)));
        }

        console2.log("   -- accorder sans lecture-avant --");
        vm.prank(g1);
        try m.proposeException(budgetId, CAT, 100, uint64(block.timestamp + 1 days), BET, bytes32(0)) returns (uint256) {
            console2.log("   issue : ABOUTIT");
        } catch (bytes memory low) {
            console2.log(string.concat("   issue : REVERTE - ", _reason(low)));
        }

        vm.prank(g1);
        uint256 eid = m.proposeException(budgetId, CAT, 150, uint64(block.timestamp + 1 days), BET, READ);

        console2.log("   -- tirer plus que l'exception accordee (200 > 150) --");
        vm.prank(agent);
        try m.drawWithException(budgetId, eid, CAT, 200) {
            console2.log("   issue : ABOUTIT");
        } catch (bytes memory low) {
            console2.log(string.concat("   issue : REVERTE - ", _reason(low)));
        }

        console2.log("   -- l'utiliser dans une autre categorie --");
        vm.prank(agent);
        try m.drawWithException(budgetId, eid, OTHER, 100) {
            console2.log("   issue : ABOUTIT");
        } catch (bytes memory low) {
            console2.log(string.concat("   issue : REVERTE - ", _reason(low)));
        }

        console2.log("   -- apres expiration --");
        vm.warp(block.timestamp + 2 days);
        vm.prank(agent);
        try m.drawWithException(budgetId, eid, CAT, 100) {
            console2.log("   issue : ABOUTIT");
        } catch (bytes memory low) {
            console2.log(string.concat("   issue : REVERTE - ", _reason(low)));
        }
    }

    // =================================================================== C5
    function test_C5_seuil() public {
        console2.log("=== C5 - seuil N-sur-M pour les grosses exceptions (falsifiable) ===");
        console2.log("   seuil :", BIG, "- approbations requises au-dela :", BIG_APPROVALS);

        vm.prank(agent);
        m.draw(budgetId, CAT, 900);

        vm.prank(g1);
        uint256 eid = m.proposeException(budgetId, CAT, 400, uint64(block.timestamp + 1 days), BET, READ);
        (,,,,,,, uint256 approvers) = m.exceptionOf(eid);
        console2.log("   approbateurs apres proposition :", approvers);
        console2.log("   requis pour 400 :", m.requiredApprovals(400));

        console2.log("   -- tirage avec N-1 approbateurs --");
        vm.prank(agent);
        try m.drawWithException(budgetId, eid, CAT, 50) {
            console2.log("   issue : ABOUTIT");
        } catch (bytes memory low) {
            console2.log(string.concat("   issue : REVERTE - ", _reason(low)));
        }

        vm.prank(g2);
        m.approveException(eid);
        (,,,,,,, approvers) = m.exceptionOf(eid);
        console2.log("   -- apres approbation d'un second gardien, approbateurs :", approvers);
        vm.prank(agent);
        try m.drawWithException(budgetId, eid, CAT, 50) {
            console2.log("   issue : ABOUTIT");
        } catch (bytes memory low) {
            console2.log(string.concat("   issue : REVERTE - ", _reason(low)));
        }

        console2.log("   -- le meme gardien tente d'approuver deux fois --");
        vm.prank(g1);
        uint256 eid2 = m.proposeException(budgetId, CAT, 400, uint64(block.timestamp + 1 days), BET, READ);
        vm.prank(g1);
        try m.approveException(eid2) {
            console2.log("   issue : ABOUTIT");
        } catch (bytes memory low) {
            console2.log(string.concat("   issue : REVERTE - ", _reason(low)));
        }
    }

    // =================================================================== C6
    function test_C6_heritage() public {
        console2.log("=== C6 - une exception au parent n'elargit pas l'enfant (falsifiable) ===");
        uint256 child = m.spawn(budgetId, agent, 400);
        console2.log("   parent cap 1000, enfant cap 400");

        vm.prank(g1);
        uint256 eid = m.proposeException(budgetId, CAT, 300, uint64(block.timestamp + 1 days), BET, READ);
        console2.log("   exception de 300 accordee au PARENT, id :", eid);
        console2.log("   plafond effectif du parent rendu :", m.effectiveCeiling(budgetId));
        console2.log("   plafond effectif de l'enfant rendu :", m.effectiveCeiling(child));

        console2.log("   -- l'enfant tente d'utiliser l'exception du parent --");
        vm.prank(agent);
        try m.drawWithException(child, eid, CAT, 100) {
            console2.log("   issue : ABOUTIT");
        } catch (bytes memory low) {
            console2.log(string.concat("   issue : REVERTE - ", _reason(low)));
        }

        console2.log("   -- l'enfant tire au-dela de SON cap (500 > 400) --");
        vm.prank(agent);
        try m.draw(child, CAT, 500) {
            console2.log("   issue : ABOUTIT");
        } catch (bytes memory low) {
            console2.log(string.concat("   issue : REVERTE - ", _reason(low)));
        }

        console2.log("   -- spawn d'un enfant plus large que le parent (1200 > 1000) --");
        try m.spawn(budgetId, agent, 1200) returns (uint256) {
            console2.log("   issue : ABOUTIT");
        } catch (bytes memory low) {
            console2.log(string.concat("   issue : REVERTE - ", _reason(low)));
        }
    }

    // =================================================================== C7
    function test_C7_trace() public {
        console2.log("=== C7 - integrite du registre (falsifiable) ===");
        vm.prank(g1);
        uint256 eid = m.proposeException(budgetId, CAT, 400, uint64(block.timestamp + 1 days), BET, READ);
        vm.prank(g2);
        m.approveException(eid);

        (
            uint256 bId,
            bytes32 cat,
            uint256 amount,
            uint64 expiry,
            bytes32 bet,
            bytes32 read,
            bool consumed,
            uint256 nApprovers
        ) = m.exceptionOf(eid);
        console2.log("   budgetId rendu   :", bId);
        console2.log("   montant rendu    :", amount);
        console2.log("   expiration rendue:", expiry);
        console2.log("   consomme rendu   :", consumed);
        console2.log("   approbateurs     :", nApprovers);
        console2.log("   pari declare non vide ? rendu :", bet != bytes32(0));
        console2.log("   lecture-avant non vide ? rendu :", read != bytes32(0));
        console2.log("   pari == valeur posee au grant ? rendu :", bet == BET);
        console2.log("   lecture == valeur posee au grant ? rendu :", read == READ);
        console2.logBytes32(cat);

        address[] memory apps = m.approversOf(eid);
        console2.log("   approbateur 0 :", apps[0]);
        console2.log("   approbateur 1 :", apps[1]);

        console2.log("   -- backfill : existe-t-il une fonction pour modifier la trace ? --");
        console2.log("   (verifie hors-chaine sur l'ABI, voir le rapport)");

        console2.log("   -- une seconde proposition cree-t-elle une NOUVELLE entree ? --");
        vm.prank(g1);
        uint256 eid2 = m.proposeException(budgetId, CAT, 50, uint64(block.timestamp + 1 days), BET, READ);
        console2.log("   id de la premiere :", eid);
        console2.log("   id de la seconde  :", eid2);
        (,, uint256 amount1,,,,,) = m.exceptionOf(eid);
        console2.log("   montant de la premiere, inchange ? rendu :", amount1);
    }

    // ============================================================ conservation
    /// Dépense totale ≤ cap + Σ(exceptions accordées et consommées), quel que soit
    /// le nombre de demandes.
    function testFuzz_conservation(uint16[6] calldata amounts, uint8[6] calldata who) public {
        uint256 id = m.createBudget(agent, CAP);

        for (uint256 i; i < 6; i++) {
            uint256 amt = uint256(amounts[i]) % 400;
            if (amt == 0) continue;

            vm.prank(agent);
            try m.draw(id, CAT, amt) {} catch {}

            address g = who[i] % 3 == 0 ? g1 : (who[i] % 3 == 1 ? g2 : g3);
            vm.prank(g);
            try m.proposeException(id, CAT, amt, uint64(block.timestamp + 1 days), BET, READ) returns (uint256 eid) {
                vm.prank(g == g1 ? g2 : g1);
                try m.approveException(eid) {} catch {}
                vm.prank(agent);
                try m.drawWithException(id, eid, CAT, amt) {} catch {}
            } catch {}
        }

        (,, uint256 cap, uint256 spent, uint256 allowance,) = m.budgetOf(id);
        assertLe(spent, cap + allowance, "spent <= cap + exceptions accordees");
    }
}

