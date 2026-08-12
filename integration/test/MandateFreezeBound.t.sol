// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {InheritableAgentMandate} from "adn/InheritableAgentMandate.sol";

/**
 * Le gel en cascade de InheritableAgentMandate echappe-t-il a une borne de lecture,
 * comme la revocation du scratch InheritableRights ?
 *
 * Ce test LIT le contrat et le mesure en local. Il ne le modifie pas, ne le
 * redeploie pas. Aucune valeur attendue n'est ecrite : on lance, on imprime.
 */
contract MandateFreezeBoundTest is Test {
    InheritableAgentMandate m;

    address agent = makeAddr("agent");
    address constant PAYEE = address(0xdEaD);
    uint256 constant CAP = 100 ether;

    function setUp() public {
        m = new InheritableAgentMandate(address(this)); // le test est gardien
    }

    function _payees() internal pure returns (address[] memory p) {
        p = new address[](1);
        p[0] = PAYEE;
    }

    /// Chaine lineaire de `n` generations. index 0 = genesis.
    function _chain(uint16 startTelomere, uint256 n) internal returns (uint256[] memory ids) {
        ids = new uint256[](n);
        ids[0] = m.mint(
            agent,
            InheritableAgentMandate.Mandate({
                maxSpendWei: CAP, telomere: startTelomere, requireLease: true, frozen: false
            }),
            _payees()
        );
        for (uint256 i = 1; i < n; i++) {
            ids[i] = m.spawn(
                ids[i - 1],
                agent,
                InheritableAgentMandate.Mandate({
                    maxSpendWei: CAP,
                    telomere: uint16(startTelomere - i),
                    requireLease: true,
                    frozen: false
                }),
                _payees()
            );
        }
    }

    // ================================================================ 1
    function test_borne_de_lecture() public {
        console2.log("=== 1 - la marche d'ancetres est-elle bornee ? ===");
        console2.log("   lu dans la source : isActive fait `while (cur != 0)`");
        console2.log("   aucune constante MAX_NODES, aucun plafond de boucle");
        console2.log("   -> on le VERIFIE par le comportement, pas par la lecture seule");

        uint256[] memory ids = _chain(300, 300);
        uint256 deepest = ids[299];
        console2.log("   chaine construite, generations :", ids.length);

        console2.log("   avant gel - isActive(le plus profond) rendu :", m.isActive(deepest));
        m.freeze(ids[0]);
        console2.log("   freeze(genesis) execute");
        console2.log("   apres gel - isActive(le plus profond) rendu :", m.isActive(deepest));
        console2.log("   (si false a 300 generations : aucune troncature a cette profondeur)");
    }

    // ================================================================ 2
    function test_plafond_de_telomere() public {
        console2.log("=== 2 - quel plafond de generations le contrat autorise-t-il ? ===");
        console2.log("   telomere declare uint16 -> maximum theorique :", uint256(type(uint16).max));

        uint256 g = m.mint(
            agent,
            InheritableAgentMandate.Mandate({
                maxSpendWei: CAP, telomere: type(uint16).max, requireLease: true, frozen: false
            }),
            _payees()
        );
        (, uint16 t,,) = m.mandateOf(g);
        console2.log("   mint avec telomere = 65535 : aboutit, telomere rendu :", uint256(t));
        console2.log("   -> aucun plafond dur au genesis autre que le type");
    }

    // ================================================================ 3
    function test_relation_profondeur_vs_borne() public {
        console2.log("=== 3 - profondeur max atteignable vs borne de lecture ===");
        console2.log("   profondeur max autorisee par le type :", uint256(type(uint16).max));
        console2.log("   borne de lecture de isActive         : aucune (while)");
        console2.log("   -> il n'y a pas de fenetre a depasser ; la question devient le GAZ");

        uint16 start = 400;
        uint256[] memory ids = _chain(start, 400);
        m.freeze(ids[0]);

        uint256[5] memory probes = [uint256(1), 50, 100, 200, 399];
        console2.log("   profondeur | gaz de isActive | rendu");
        for (uint256 i; i < 5; i++) {
            uint256 d = probes[i];
            uint256 g0 = gasleft();
            bool v = m.isActive(ids[d]);
            uint256 used = g0 - gasleft();
            console2.log(
                string.concat(
                    "   ", vm.toString(d), "  |  ", vm.toString(used), "  |  ", v ? "true" : "false"
                )
            );
        }
    }

    // ================================================================ cas 1
    function test_cas1_lignee_la_plus_profonde() public {
        console2.log("=== cas 1 - geler la racine sous une lignee profonde ===");
        uint256[] memory ids = _chain(500, 500);
        console2.log("   generations construites :", ids.length);
        console2.log("   avant - isActive(dernier) rendu :", m.isActive(ids[499]));
        m.freeze(ids[0]);
        console2.log("   freeze(genesis)");
        console2.log("   apres - isActive(dernier) rendu :", m.isActive(ids[499]));

        console2.log("   -- profondeurs intermediaires, meme gel --");
        uint256[4] memory probes = [uint256(10), 100, 300, 499];
        for (uint256 i; i < 4; i++) {
            console2.log(
                string.concat("   profondeur ", vm.toString(probes[i]), " -> isActive rendu :"),
                m.isActive(ids[probes[i]])
            );
        }
    }

    // ================================================================ cas 2
    function test_cas2_controle_ancetre_intermediaire() public {
        console2.log("=== cas 2 - controle : geler un ancetre intermediaire ===");
        uint256[] memory ids = _chain(200, 200);
        console2.log("   avant - isActive(199) rendu :", m.isActive(ids[199]));
        m.freeze(ids[100]);
        console2.log("   freeze(profondeur 100)");
        console2.log("   apres - isActive(199) rendu :", m.isActive(ids[199]));
        console2.log("   apres - isActive(150) rendu :", m.isActive(ids[150]));
        console2.log("   apres - isActive( 99) rendu :", m.isActive(ids[99]));
        console2.log("   (au-dessus du gel, la branche doit rester active)");
    }

    // ================================================================ cas 3
    function test_cas3_statique_monotone_a_l_ecriture() public {
        console2.log("=== cas 3 - le statique est-il impose a l'ECRITURE ? ===");
        uint256 p = m.mint(
            agent,
            InheritableAgentMandate.Mandate({
                maxSpendWei: 10 ether, telomere: 5, requireLease: true, frozen: false
            }),
            _payees()
        );

        console2.log("--- plafond de depense : enfant plus large que le parent ---");
        vm.expectRevert(bytes("spend cap cannot exceed parent"));
        m.spawn(
            p,
            agent,
            InheritableAgentMandate.Mandate({
                maxSpendWei: 11 ether, telomere: 4, requireLease: true, frozen: false
            }),
            _payees()
        );
        console2.log("   reverte");

        console2.log("--- bail herite : enfant qui le desactive ---");
        vm.expectRevert(bytes("cannot disable inherited lease"));
        m.spawn(
            p,
            agent,
            InheritableAgentMandate.Mandate({
                maxSpendWei: 5 ether, telomere: 4, requireLease: false, frozen: false
            }),
            _payees()
        );
        console2.log("   reverte");

        console2.log("--- telomere : enfant qui ne decremente pas ---");
        vm.expectRevert(bytes("telomere must be parent-1"));
        m.spawn(
            p,
            agent,
            InheritableAgentMandate.Mandate({
                maxSpendWei: 5 ether, telomere: 5, requireLease: true, frozen: false
            }),
            _payees()
        );
        console2.log("   reverte");

        console2.log("   -> ces trois clauses sont imposees au spawn, donc deja resumees localement");
        console2.log("   -> une marche tronquee ne pourrait pas les sur-permettre");
        console2.log("   NB : ce contrat n'a pas de champ validUntil ; le bail est un booleen");
    }
}
