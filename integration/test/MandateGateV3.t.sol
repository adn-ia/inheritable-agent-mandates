// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {MandateGateV3, IInheritableAgentMandate} from "adn/MandateGateV3.sol";
import {V3Vectors as V} from "./V3Vectors.sol";

contract MockMandateV3 is IInheritableAgentMandate {
    function ownerOf(uint256) external pure returns (address) { return address(0xA11CE); }
    function parentOf(uint256) external pure returns (uint256) { return 0; }
    function mandateOf(uint256) external pure returns (uint256, uint16, bool, bool) { return (1 ether, 5, true, false); }
    function isActive(uint256) external pure returns (bool) { return true; }
    function payeeAllowed(uint256, address) external pure returns (bool) { return true; }
}

/**
 * V3 : l'poque d'mission plafonne la vie d'un verdict depuis un instant que le
 * CONTRAT a crit, et le timelock empche un gardien seul d'introduire un metteur
 * dans l'instant. Les deux exigent de manipuler le temps  d'o `vm.warp`.
 */
contract MandateGateV3Test is Test {
    MandateGateV3 gate;

    function setUp() public {
        MockMandateV3 mock = new MockMandateV3();
        MandateGateV3 tmp = new MandateGateV3(IInheritableAgentMandate(address(mock)), address(this));
        vm.etch(V.GATE, address(tmp).code);
        vm.chainId(V.CHAIN_ID);
        gate = MandateGateV3(V.GATE);

        vm.warp(V.T0);
        gate.proposeIssuerKey(V.ISSUER_KEY);
        vm.warp(uint256(V.T0) + gate.TIMELOCK());
        gate.confirmIssuerKey(V.ISSUER_KEY);
        gate.credit(V.AGENT_ID, 1 ether);
    }

    function _action() internal pure returns (MandateGateV3.Action memory) {
        return MandateGateV3.Action({ agentId: V.AGENT_ID, payee: V.PAYEE, amount: V.AMOUNT, salt: V.SALT });
    }
    function _ok(uint64 epoch) internal pure returns (MandateGateV3.SchnorrVerdict memory) {
        return MandateGateV3.SchnorrVerdict({ preimage: V.OK_PRE, issuerKey: V.ISSUER_KEY,
            sigR: V.OK_R, sigS: V.OK_S, offArtifact: V.OK_A, offVerifier: V.OK_V,
            offVerdict: V.OK_D, epoch: epoch, offEpoch: V.OK_E });
    }

    function test_0_montage() public view {
        console2.log("  epoque inscrite par le contrat :", gate.issuerEpoch(V.ISSUER_KEY));
        console2.log("  epoque attendue par les fixtures:", V.EPOCH);
        console2.log("  MAX_WINDOW :", gate.MAX_WINDOW(), "TIMELOCK :", gate.TIMELOCK());
        assertEq(gate.issuerEpoch(V.ISSUER_KEY), V.EPOCH, "epoque incoherente");
    }

    function test_1_dans_la_fenetre() public {
        vm.warp(uint256(V.EPOCH) + 1 days);
        gate.executeSchnorr(_action(), _ok(V.EPOCH));
        console2.log("  a epoque+1j -> ABOUTIT, spent =", gate.spent(V.AGENT_ID));
        assertEq(gate.spent(V.AGENT_ID), V.AMOUNT);
    }

    function test_2_hors_fenetre() public {
        vm.warp(uint256(V.EPOCH) + uint256(gate.MAX_WINDOW()) + 1);
        vm.expectRevert(bytes("verdict expired"));
        gate.executeSchnorr(_action(), _ok(V.EPOCH));
        console2.log("  a epoque+MAX_WINDOW+1s -> REVERTE : verdict expired");
        console2.log("  frontiere exacte : a epoque+MAX_WINDOW pile, le verdict passe encore");
        vm.warp(uint256(V.EPOCH) + uint256(gate.MAX_WINDOW()));
        gate.executeSchnorr(_action(), _ok(V.EPOCH));
        assertEq(gate.spent(V.AGENT_ID), V.AMOUNT);
    }

    function test_3_epoque_perimee_apres_rotation() public {
        vm.warp(uint256(V.EPOCH) + 1 days);
        gate.refreshIssuerEpoch(V.ISSUER_KEY);
        console2.log("  refreshIssuerEpoch -> nouvelle epoque :", gate.issuerEpoch(V.ISSUER_KEY));
        vm.expectRevert(bytes("stale issuer epoch"));
        gate.executeSchnorr(_action(), _ok(V.EPOCH));
        console2.log("  le verdict de l'ancienne epoque -> REVERTE : stale issuer epoch");
        console2.log("  (une seule ecriture perime TOUS les verdicts de l'epoque precedente)");
    }

    function test_4_epoque_non_liee_dans_la_preimage() public {
        vm.warp(uint256(V.EPOCH) + 1 days);
        MandateGateV3.SchnorrVerdict memory v = MandateGateV3.SchnorrVerdict({
            preimage: V.BAD_PRE, issuerKey: V.ISSUER_KEY, sigR: V.BAD_R, sigS: V.BAD_S,
            offArtifact: V.BAD_A, offVerifier: V.BAD_V, offVerdict: V.BAD_D,
            epoch: V.EPOCH, offEpoch: V.BAD_E });
        vm.expectRevert(bytes("epoch not bound to verdict"));
        gate.executeSchnorr(_action(), v);
        console2.log("  preimage portant epoque+1, argument = epoque correcte");
        console2.log("  -> REVERTE : epoch not bound to verdict");
        console2.log("  (on ne peut pas declarer une epoque que le verdict signe ne porte pas)");
    }

    function test_5_timelock() public {
        uint256 K2 = 0xDEADBEEF;
        vm.warp(uint256(V.EPOCH) + 1 days);
        gate.proposeIssuerKey(K2);
        console2.log("  proposeIssuerKey  proposedAt =", gate.proposedAt(K2));
        console2.log("  autorisee tout de suite ?", gate.authorizedIssuerKeys(K2));

        vm.expectRevert(bytes("timelock not elapsed"));
        gate.confirmIssuerKey(K2);
        console2.log("  confirm avant delai -> REVERTE : timelock not elapsed");

        vm.warp(block.timestamp + gate.TIMELOCK());
        gate.confirmIssuerKey(K2);
        console2.log("  confirm apres delai -> autorisee :", gate.authorizedIssuerKeys(K2),
                     "epoque", gate.issuerEpoch(K2));

        gate.revokeIssuerKey(K2);
        console2.log("  revoke -> IMMEDIAT, autorisee :", gate.authorizedIssuerKeys(K2),
                     "epoque", gate.issuerEpoch(K2));
    }

    function test_6_revoke_annule_une_proposition_en_cours() public {
        uint256 K3 = 0xC0FFEE;
        vm.warp(uint256(V.EPOCH) + 1 days);
        gate.proposeIssuerKey(K3);
        gate.revokeIssuerKey(K3);
        console2.log("  proposition annulee par revoke  proposedAt =", gate.proposedAt(K3));
        vm.warp(block.timestamp + gate.TIMELOCK() + 1);
        vm.expectRevert(bytes("not proposed"));
        gate.confirmIssuerKey(K3);
        console2.log("  confirm apres le delai -> REVERTE : not proposed");
        console2.log("  (un gardien compromis ne peut pas proposer, se faire couper, puis confirmer)");
    }

    function test_7_refresh_exige_une_cle_deja_autorisee() public {
        vm.expectRevert(bytes("issuer key not authorized"));
        gate.refreshIssuerEpoch(0xBADBAD);
        console2.log("  refreshIssuerEpoch sur une cle non autorisee -> REVERTE");
        console2.log("  (le raccourci sans timelock ne peut PAS servir a accorder)");
    }
}
