// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {StructuredBudget} from "adn/StructuredBudget.sol";

/**
 * Budget structuré — S1→S5 (bascules illustrées) puis les invariants falsifiables.
 * Chaque appel est encadré, son issue imprimée telle quelle. Aucune valeur attendue
 * n'est écrite ici : le contrat décide, le test rapporte.
 */
contract StructuredBudgetTest is Test {
    StructuredBudget sb;
    address owner = makeAddr("owner");

    bytes32 constant MEAL = bytes32("meal");
    bytes32 constant OTHER = bytes32("other");

    function setUp() public {
        sb = new StructuredBudget();
    }

    function _one(bytes32 k) internal pure returns (bytes32[] memory a) {
        a = new bytes32[](1);
        a[0] = k;
    }

    function _u(uint256 v) internal pure returns (uint256[] memory a) {
        a = new uint256[](1);
        a[0] = v;
    }

    function _two(bytes32 a1, bytes32 a2) internal pure returns (bytes32[] memory a) {
        a = new bytes32[](2);
        a[0] = a1;
        a[1] = a2;
    }

    function _u2(uint256 v1, uint256 v2) internal pure returns (uint256[] memory a) {
        a = new uint256[](2);
        a[0] = v1;
        a[1] = v2;
    }

    function _empty32() internal pure returns (bytes32[] memory a) {
        a = new bytes32[](0);
    }

    function _empty() internal pure returns (uint256[] memory a) {
        a = new uint256[](0);
    }

    function _reason(bytes memory low) internal pure returns (string memory) {
        if (low.length < 4) return "revert sans donnee";
        bytes4 s = bytes4(low[0]) | (bytes4(low[1]) >> 8) | (bytes4(low[2]) >> 16) | (bytes4(low[3]) >> 24);
        if (s == StructuredBudget.PerItemExceeded.selector) return "PerItemExceeded (plafond par depense)";
        if (s == StructuredBudget.CategoryExceeded.selector) return "CategoryExceeded (poche categorie)";
        if (s == StructuredBudget.TotalExceeded.selector) return "TotalExceeded (plafond total)";
        if (s == StructuredBudget.OverAllocated.selector) return "OverAllocated (sur-allocation au setup)";
        if (s == StructuredBudget.ChildCapWider.selector) return "ChildCapWider";
        if (s == StructuredBudget.ChildCategoryWider.selector) return "ChildCategoryWider";
        if (s == StructuredBudget.ChildPerItemWider.selector) return "ChildPerItemWider";
        return vm.toString(s);
    }

    function _tryDraw(uint256 id, bytes32 cat, uint256 amount) internal returns (bool ok, string memory why) {
        vm.prank(owner);
        try sb.draw(id, cat, amount) {
            return (true, "");
        } catch (bytes memory low) {
            return (false, _reason(low));
        }
    }

    function _print(string memory label, bool ok, string memory why) internal pure {
        if (ok) console2.log(string.concat("   ", label, " : ADMIS"));
        else console2.log(string.concat("   ", label, " : REFUSE - ", why));
    }

    // ================================================================== S1→S5
    function test_S1_plafond_plat() public {
        console2.log("=== S1 - plafond plat, cap 500, aucune structure ===");
        uint256 id = sb.createBudget(owner, 500, _empty32(), _empty(), _empty());
        (bool ok, string memory why) = _tryDraw(id, MEAL, 490);
        _print("draw(meal, 490)", ok, why);
        console2.log("   totalRoom rendu :", sb.totalRoom(id));
    }

    function test_S2_avec_reserve() public {
        console2.log("=== S2 - meme cap 500, + un engage de 200 ===");
        uint256 id = sb.createBudget(owner, 500, _empty32(), _empty(), _empty());
        vm.prank(owner);
        sb.reserve(id, OTHER, 200);
        console2.log("   apres reserve(200), totalRoom rendu :", sb.totalRoom(id));
        (bool ok, string memory why) = _tryDraw(id, MEAL, 490);
        _print("draw(meal, 490)", ok, why);
    }

    function test_S3_avec_poches() public {
        console2.log("=== S3 - cap 500 reparti : meal 50, other 450, aucun engage ===");
        uint256 id = sb.createBudget(owner, 500, _two(MEAL, OTHER), _u2(50, 450), _u2(0, 0));
        console2.log("   totalRoom rendu :", sb.totalRoom(id));
        (bool ok, string memory why) = _tryDraw(id, MEAL, 490);
        _print("draw(meal, 490)", ok, why);
    }

    function test_S4_bonne_poche() public {
        console2.log("=== S4 - meal : catCap 500, maxPerItem 500 ===");
        uint256 id = sb.createBudget(owner, 500, _one(MEAL), _u(500), _u(500));
        (bool ok, string memory why) = _tryDraw(id, MEAL, 490);
        _print("draw(meal, 490)", ok, why);
    }

    function test_S5_interaction_fine() public {
        console2.log("=== S5 - maxPerItem 500, catCap 1500, deja 1100 depenses ===");
        uint256 id = sb.createBudget(owner, 2000, _one(MEAL), _u(1500), _u(500));
        vm.startPrank(owner);
        sb.draw(id, MEAL, 500);
        sb.draw(id, MEAL, 500);
        sb.draw(id, MEAL, 100);
        vm.stopPrank();
        (, uint256 catSpent,,,) = sb.categoryOf(id, MEAL);
        console2.log("   catSpent rendu :", catSpent);
        (bool ok, string memory why) = _tryDraw(id, MEAL, 490);
        _print("draw(meal, 490)", ok, why);
    }

    // ================================================================== invariants
    function test_I1_surallocation_rejetee() public {
        console2.log("=== I1 - setup avec somme des poches > cap (falsifiable) ===");
        console2.log("   cap 500, poches 300 + 300 = 600");
        try sb.createBudget(owner, 500, _two(MEAL, OTHER), _u2(300, 300), _u2(0, 0)) returns (uint256) {
            console2.log("   issue : ABOUTIT");
        } catch (bytes memory low) {
            console2.log(string.concat("   issue : REVERTE - ", _reason(low)));
        }
        console2.log("   pour comparaison, 300 + 200 = 500 :");
        try sb.createBudget(owner, 500, _two(MEAL, OTHER), _u2(300, 200), _u2(0, 0)) returns (uint256 id2) {
            console2.log("   issue : ABOUTIT, id", id2);
        } catch (bytes memory low) {
            console2.log(string.concat("   issue : REVERTE - ", _reason(low)));
        }
    }

    function test_I2_heritage_structure() public {
        console2.log("=== I2 - heritage sur chaque dimension (falsifiable) ===");
        uint256 p = sb.createBudget(owner, 1000, _two(MEAL, OTHER), _u2(400, 400), _u2(100, 200));

        console2.log("parent : cap 1000, meal(400, item 100), other(400, item 200)");

        console2.log("-- enfant qui se resserre partout --");
        try sb.spawn(p, owner, 500, _two(MEAL, OTHER), _u2(200, 200), _u2(50, 100)) returns (uint256 c) {
            console2.log("   issue : ABOUTIT, id", c);
        } catch (bytes memory low) {
            console2.log(string.concat("   issue : REVERTE - ", _reason(low)));
        }

        console2.log("-- enfant dont le cap total s'elargit (1200 > 1000) --");
        try sb.spawn(p, owner, 1200, _one(MEAL), _u(200), _u(50)) returns (uint256) {
            console2.log("   issue : ABOUTIT");
        } catch (bytes memory low) {
            console2.log(string.concat("   issue : REVERTE - ", _reason(low)));
        }

        console2.log("-- enfant dont UNE poche s'elargit (meal 600 > 400) --");
        try sb.spawn(p, owner, 900, _one(MEAL), _u(600), _u(50)) returns (uint256) {
            console2.log("   issue : ABOUTIT");
        } catch (bytes memory low) {
            console2.log(string.concat("   issue : REVERTE - ", _reason(low)));
        }

        console2.log("-- enfant dont le plafond par depense s'elargit (item 300 > 100) --");
        try sb.spawn(p, owner, 500, _one(MEAL), _u(200), _u(300)) returns (uint256) {
            console2.log("   issue : ABOUTIT");
        } catch (bytes memory low) {
            console2.log(string.concat("   issue : REVERTE - ", _reason(low)));
        }

        console2.log("-- enfant qui retire le plafond par depense (item 0 = illimite) --");
        try sb.spawn(p, owner, 500, _one(MEAL), _u(200), _u(0)) returns (uint256) {
            console2.log("   issue : ABOUTIT");
        } catch (bytes memory low) {
            console2.log(string.concat("   issue : REVERTE - ", _reason(low)));
        }
    }

    /// Conservation sous séquences aléatoires — le fuzzer choisit montants et catégories.
    function testFuzz_I3_conservation(uint96[8] calldata amounts, bool[8] calldata pickMeal) public {
        uint256 id = sb.createBudget(owner, 1000, _two(MEAL, OTHER), _u2(400, 400), _u2(100, 200));

        for (uint256 i; i < 8; i++) {
            uint256 amt = uint256(amounts[i]) % 250;
            if (amt == 0) continue;
            bytes32 cat = pickMeal[i] ? MEAL : OTHER;
            vm.prank(owner);
            try sb.draw(id, cat, amt) {} catch {}
        }

        (,, uint256 cap, uint256 spent,,) = sb.budgetOf(id);
        (uint256 mCap, uint256 mSpent,,,) = sb.categoryOf(id, MEAL);
        (uint256 oCap, uint256 oSpent,,,) = sb.categoryOf(id, OTHER);

        assertLe(spent, cap, "spent <= cap");
        assertLe(mSpent, mCap, "catSpent[meal] <= catCap[meal]");
        assertLe(oSpent, oCap, "catSpent[other] <= catCap[other]");
    }

    /// Dépendance à l'ordre — même multiset, deux ordres, on compare les verdicts.
    function test_I4_ordre() public {
        console2.log("=== I4 - meme multiset, ordres differents (falsifiable) ===");
        uint256[3] memory amts = [uint256(300), 150, 90];
        console2.log("   budget : cap 500, meal(catCap 400, item 300) ; tirages 300, 150, 90");

        // ordre A : 300, 150, 90
        uint256 a = sb.createBudget(owner, 500, _one(MEAL), _u(400), _u(300));
        bool[3] memory admittedA;
        for (uint256 i; i < 3; i++) {
            (bool ok,) = _tryDraw(a, MEAL, amts[i]);
            admittedA[i] = ok;
        }
        (, uint256 spentA,,,) = sb.categoryOf(a, MEAL);
        console2.log("   ordre A (300,150,90) - admis :", admittedA[0], admittedA[1], admittedA[2]);
        console2.log("   ordre A - catSpent rendu :", spentA);

        // ordre B : 90, 150, 300
        uint256 b = sb.createBudget(owner, 500, _one(MEAL), _u(400), _u(300));
        uint256[3] memory amtsB = [uint256(90), 150, 300];
        bool[3] memory admittedB;
        for (uint256 i; i < 3; i++) {
            (bool ok,) = _tryDraw(b, MEAL, amtsB[i]);
            admittedB[i] = ok;
        }
        (, uint256 spentB,,,) = sb.categoryOf(b, MEAL);
        console2.log("   ordre B (90,150,300) - admis :", admittedB[0], admittedB[1], admittedB[2]);
        console2.log("   ordre B - catSpent rendu :", spentB);

        console2.log("   nombre admis A vs B :", _count(admittedA), _count(admittedB));
        console2.log("   catSpent identique ? rendu :", spentA == spentB);
    }

    function _count(bool[3] memory b) internal pure returns (uint256 n) {
        for (uint256 i; i < 3; i++) if (b[i]) n++;
    }
}
