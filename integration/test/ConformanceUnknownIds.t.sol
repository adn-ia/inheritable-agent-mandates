// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {InheritableAgentMandate} from "adn/InheritableAgentMandate.sol";
import {InheritableAgentMandateV3} from "adn/InheritableAgentMandateV3.sol";

/**
 * Conformité : les identifiants inconnus.
 *
 * Le texte d'ERC-8370 pose une clause NORMATIVE, dans ses considérations de sécurité :
 *
 *   « A registry backed by mappings returns a zero-valued Mandate for an id that was never
 *     minted: frozen is false, validUntil is zero, and the ancestor walk terminates
 *     immediately. A naive isActive therefore reports an agent that does not exist as
 *     **active**, and a capability root can be computed for it. Implementations MUST reject
 *     unknown ids in isActive and in any root-deriving view, and integrators MUST NOT treat
 *     isActive as an existence check. »
 *
 * Ce banc n'affirme rien : il imprime ce que les implémentations DÉPLOYÉES répondent, et il
 * fige le constat. Les deux violent la clause. Ce n'est pas exploitable à travers
 * `MandateGateV3` — le bénéficiaire d'un agent inexistant n'est jamais autorisé, et la porte
 * s'arrête là — mais un intégrateur qui lit `isActive` seule, comme la clause l'anticipe,
 * conclura qu'un agent qui n'a jamais existé est actif.
 *
 * Découvert le 19/08/2026 en payant le même piège une couche plus haut : la première version
 * du compte rendu de décision en a tiré un « sans objet » et bloquait ce que la porte
 * laissait passer.
 *
 * Le correctif est connu et tient en une ligne — `if (!exists(id)) return false;` — mais il
 * ne peut aller ni dans la V1 ni dans la V3 : elles sont déployées sur Base Sepolia et leur
 * source doit continuer de correspondre au bytecode publié.
 */
contract ConformanceUnknownIdsTest is Test {
    InheritableAgentMandate v1;
    InheritableAgentMandateV3 v3;

    uint256 constant JAMAIS_CREE = 999_999;

    function setUp() public {
        v1 = new InheritableAgentMandate(address(this));
        v3 = new InheritableAgentMandateV3(address(this));
    }

    function test_1_un_agent_jamais_cree_n_a_pas_de_proprietaire() public view {
        console2.log("  agent", JAMAIS_CREE, "- proprietaire :");
        console2.log("   ", v1.ownerOf(JAMAIS_CREE));
        assertEq(v1.ownerOf(JAMAIS_CREE), address(0), "il n'existe pas");
        assertEq(v3.ownerOf(JAMAIS_CREE), address(0), "il n'existe pas");
    }

    /// 🔴 Le constat, figé : les deux le disent ACTIF.
    function test_2_les_deux_implementations_le_disent_actif() public view {
        bool a1 = v1.isActive(JAMAIS_CREE);
        bool a3 = v3.isActive(JAMAIS_CREE);

        console2.log("  isActive sur un agent qui n'a JAMAIS ete cree :");
        console2.log("    InheritableAgentMandate   (V1, deployee) ->", a1);
        console2.log("    InheritableAgentMandateV3 (V3, deployee) ->", a3);
        console2.log("    la clause dit : MUST reject unknown ids in isActive");

        assertTrue(a1, "constat fige : la V1 ne rejette pas");
        assertTrue(a3, "constat fige : la V3 ne rejette pas");
    }

    /// La marche d'ancetres s'arrete tout de suite : il n'y a rien a parcourir.
    function test_3_pourquoi_elle_repond_oui() public view {
        (, , , bool frozen) = v1.mandateOf(JAMAIS_CREE);
        console2.log("  gele ? ", frozen, " - parent :", v1.parentOf(JAMAIS_CREE));
        console2.log("  aucun ancetre a parcourir, aucun gel trouve -> la boucle rend true");
        assertFalse(frozen);
        assertEq(v1.parentOf(JAMAIS_CREE), 0);
    }

    /// Un agent REELLEMENT cree repond oui pour une bonne raison, lui.
    function test_4_controle_negatif_un_agent_reel() public {
        address[] memory p = new address[](1);
        p[0] = address(0xdEaD);
        InheritableAgentMandate.Mandate memory m =
            InheritableAgentMandate.Mandate({maxSpendWei: 1 ether, telomere: 5, requireLease: false, frozen: false});
        uint256 id = v1.mint(address(this), m, p);

        console2.log("  agent reellement cree :", id, "-> isActive :", v1.isActive(id));
        assertTrue(v1.isActive(id));
        assertTrue(v1.ownerOf(id) != address(0), "celui-la existe");
    }
}
