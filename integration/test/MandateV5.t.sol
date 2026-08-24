// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {InheritableAgentMandateV5} from "adn/InheritableAgentMandateV5.sol";
import {InheritableAgentMandateV3} from "adn/InheritableAgentMandateV3.sol";

/**
 * V5 — les trois écarts avec V3, mesurés côte à côte.
 *
 * Ce banc n'affirme rien sur V3 : il l'instancie et imprime ce qu'elle répond,
 * puis fait la même chose sur V5. L'écart est le résultat.
 */
contract MandateV5Test is Test {
    InheritableAgentMandateV5 v5;
    InheritableAgentMandateV3 v3;

    address GUARDIAN;
    address AGENT;
    address PAYEE;

    uint64 constant START = 1_000_000;
    uint32 constant PERIOD = 30 days;
    uint16 constant COUNT = 12;

    function setUp() public {
        GUARDIAN = makeAddr("guardian");
        AGENT = makeAddr("agent");
        PAYEE = makeAddr("payee");
        vm.warp(START);
        vm.prank(GUARDIAN);
        v5 = new InheritableAgentMandateV5(GUARDIAN);
        vm.prank(GUARDIAN);
        v3 = new InheritableAgentMandateV3(GUARDIAN);
    }

    function _m(uint256 cap, uint16 telo) internal pure returns (InheritableAgentMandateV5.Mandate memory) {
        return InheritableAgentMandateV5.Mandate({
            maxSpendWei: cap, periodStart: START, periodLength: PERIOD,
            periodCount: COUNT, telomere: telo, requireLease: true, frozen: false
        });
    }

    function _mint(uint256 cap, uint16 telo) internal returns (uint256 id) {
        address[] memory p = new address[](1); p[0] = PAYEE;
        vm.prank(GUARDIAN);
        id = v5.mint(AGENT, _m(cap, telo), p);
    }

    // ═══ 1 — identifiant inconnu ═══════════════════════════════════════════
    function test_1_identifiant_inconnu() public {
        console2.log("=== 1. Que repond-on sur un agent JAMAIS CREE (id 999) ? ===");
        console2.log("   V3.isActive(999) :", v3.isActive(999));
        console2.log("   V5.isActive(999) :", v5.isActive(999));
        console2.log("   le texte de l'ERC dit : MUST reject unknown ids");
    }

    // ═══ 2 — le gel change-t-il l'identite ? ═══════════════════════════════
    function test_2_gel_et_identite() public {
        uint256 id = _mint(100 ether, 3);
        bytes32 avant = v5.mandateRoot(id);
        vm.prank(GUARDIAN);
        v5.freeze(id);
        bytes32 apres = v5.mandateRoot(id);
        console2.log("=== 2. Le gel change-t-il la racine ? ===");
        console2.logBytes32(avant);
        console2.logBytes32(apres);
        console2.log("   identique :", avant == apres);
        console2.log("   et l'agent est-il encore actif ?", v5.isActive(id));
    }

    // ═══ 3 — bail scelle : renouveler ne touche pas l'identite ═════════════
    function test_3_bail_scelle() public {
        uint256 id = _mint(100 ether, 3);
        console2.log("=== 3. Bail scelle ===");
        console2.log("   fin absolue      :", v5.absoluteEnd(id));
        console2.log("   echeance courante:", v5.currentExpiry(id));
        bytes32 avant = v5.mandateRoot(id);

        vm.prank(GUARDIAN);
        v5.renew(id);
        console2.log("   apres renew, echeance :", v5.currentExpiry(id));
        console2.log("   racine inchangee      :", avant == v5.mandateRoot(id));
        console2.log("   toujours <= fin absolue :", v5.currentExpiry(id) <= v5.absoluteEnd(id));
    }

    // ═══ 4 — le plafond du bail ne se depasse jamais ═══════════════════════
    function test_4_plafond_du_bail() public {
        uint256 id = _mint(100 ether, 3);
        uint16 n;
        while (true) {
            vm.prank(GUARDIAN);
            try v5.renew(id) { n++; } catch Error(string memory r) {
                console2.log("=== 4. Combien de renouvellements avant refus ? ===");
                console2.log("   acceptes :", n);
                console2.log("   refus    :", r);
                break;
            }
            if (n > 50) { console2.log("   PAS DE PLAFOND - anomalie"); break; }
        }
        console2.log("   echeance finale :", v5.currentExpiry(id));
        console2.log("   fin absolue     :", v5.absoluteEnd(id));
        console2.log("   depassement ?   :", v5.currentExpiry(id) > v5.absoluteEnd(id));
    }

    // ═══ 5 — un enfant peut-il survivre a son parent ? ═════════════════════
    function test_5_enfant_ne_survit_pas() public {
        uint256 parent = _mint(100 ether, 3);
        address[] memory p = new address[](1); p[0] = PAYEE;

        InheritableAgentMandateV5.Mandate memory cm = _m(40 ether, 2);
        cm.periodLength = 10 days;
        cm.periodCount = 3;

        vm.prank(AGENT);
        uint256 child = v5.spawn(parent, AGENT, cm, p);
        console2.log("=== 5. Un enfant peut-il survivre a son parent ? ===");
        console2.log("   fin absolue parent :", v5.absoluteEnd(parent));
        console2.log("   fin absolue enfant :", v5.absoluteEnd(child));

        // le parent cesse d'etre renouvele, l'enfant essaie de continuer
        vm.warp(START + uint64(PERIOD) + 1);
        console2.log("   apres 1 periode : parent actif ?", v5.isActive(parent));
        vm.prank(GUARDIAN);
        try v5.renew(child) {
            console2.log("   renouvellement de l'enfant ACCEPTE malgre le parent");
        } catch Error(string memory r) {
            console2.log("   renouvellement de l'enfant refuse :", r);
        }
    }

    // ═══ 6 — un enfant sans bail sous un parent avec bail ══════════════════
    function test_6_enfant_sans_bail() public {
        uint256 parent = _mint(100 ether, 3);
        address[] memory p = new address[](1); p[0] = PAYEE;
        InheritableAgentMandateV5.Mandate memory cm = _m(40 ether, 2);
        cm.periodStart = 0; cm.periodLength = 0; cm.periodCount = 0;
        vm.prank(AGENT);
        console2.log("=== 6. Enfant SANS bail sous un parent AVEC bail ===");
        try v5.spawn(parent, AGENT, cm, p) returns (uint256) {
            console2.log("   ACCEPTE - l'enfant echappe au bail");
        } catch Error(string memory r) {
            console2.log("   refuse :", r);
        }
    }
}
