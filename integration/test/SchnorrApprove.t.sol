// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {MandateGateV2, IInheritableAgentMandate} from "adn/MandateGateV2.sol";
import {SchnorrApproveVectors as V} from "./SchnorrApproveVectors.sol";

/// Mandat minimal : le gate n'a besoin que de ces cinq lectures.
contract MockMandate is IInheritableAgentMandate {
    function ownerOf(uint256) external pure returns (address) { return address(0xA11CE); }
    function parentOf(uint256) external pure returns (uint256) { return 0; }
    function mandateOf(uint256) external pure returns (uint256, uint16, bool, bool) {
        return (1 ether, 5, true, false);
    }
    function isActive(uint256) external pure returns (bool) { return true; }
    function payeeAllowed(uint256, address) external pure returns (bool) { return true; }
}

/**
 * Le chemin schnorr doit refuser un verdict qui REFUSE — symétrique du
 * `require(v.approve)` du chemin ECDSA.
 *
 * Les deux verdicts sont réellement signés, portent la MÊME action, le MÊME gate et
 * la MÊME clé : la seule différence entre eux est le mot `approve` / `reject`. Si le
 * contrôle manquait, les deux passeraient.
 */
contract SchnorrApproveTest is Test {
    MandateGateV2 gate;
    MockMandate mock;

    function setUp() public {
        mock = new MockMandate();
        MandateGateV2 tmp = new MandateGateV2(IInheritableAgentMandate(address(mock)), address(this));
        // on place le gate à une adresse FIXE : les verdicts s'engagent dessus
        vm.etch(V.GATE, address(tmp).code);
        vm.chainId(V.CHAIN_ID);
        gate = MandateGateV2(V.GATE);
        gate.setIssuerKey(V.ISSUER_KEY, true);
        gate.credit(V.AGENT_ID, 1 ether);
    }

    function _action() internal pure returns (MandateGateV2.Action memory) {
        return MandateGateV2.Action({
            agentId: V.AGENT_ID, payee: V.PAYEE, amount: V.AMOUNT, salt: V.SALT
        });
    }

    function test_0_le_montage_est_coherent() public view {
        console2.log("  expectedVerifierTag() :", string(gate.expectedVerifierTag()));
        console2.log("  emetteur autorise     :", gate.authorizedIssuerKeys(V.ISSUER_KEY));
        assertEq(
            keccak256(gate.expectedVerifierTag()),
            keccak256("eip155:84532:0x00000000000000000000000000000000000c0de1"),
            "le gate ne se designe pas comme les verdicts l'attendent"
        );
    }

    function test_1_un_verdict_reject_est_refuse() public {
        MandateGateV2.SchnorrVerdict memory v = MandateGateV2.SchnorrVerdict({
            preimage: V.REJECT_PRE, issuerKey: V.ISSUER_KEY,
            sigR: V.REJECT_R, sigS: V.REJECT_S,
            offArtifact: V.REJECT_OFF_A, offVerifier: V.REJECT_OFF_V, offVerdict: V.REJECT_OFF_D
        });
        vm.expectRevert(bytes("verdict does not approve"));
        gate.executeSchnorr(_action(), v);
        console2.log("  verdict 'reject' -> REVERTE : verdict does not approve");
        console2.log("  spent apres      :", gate.spent(V.AGENT_ID));
        assertEq(gate.spent(V.AGENT_ID), 0, "un refus n'a pas depense");
    }

    function test_2_un_verdict_approve_passe_ce_controle() public {
        MandateGateV2.SchnorrVerdict memory v = MandateGateV2.SchnorrVerdict({
            preimage: V.APPROVE_PRE, issuerKey: V.ISSUER_KEY,
            sigR: V.APPROVE_R, sigS: V.APPROVE_S,
            offArtifact: V.APPROVE_OFF_A, offVerifier: V.APPROVE_OFF_V, offVerdict: V.APPROVE_OFF_D
        });
        bytes32 c = gate.executeSchnorr(_action(), v);
        console2.log("  verdict 'approve' -> ABOUTIT");
        console2.logBytes32(c);
        console2.log("  spent apres       :", gate.spent(V.AGENT_ID));
        assertEq(gate.spent(V.AGENT_ID), V.AMOUNT, "l'action approuvee a bien depense");
    }

    function test_3_offset_de_verdict_mensonger() public {
        MandateGateV2.SchnorrVerdict memory v = MandateGateV2.SchnorrVerdict({
            preimage: V.REJECT_PRE, issuerKey: V.ISSUER_KEY,
            sigR: V.REJECT_R, sigS: V.REJECT_S,
            offArtifact: V.REJECT_OFF_A, offVerifier: V.REJECT_OFF_V, offVerdict: 0
        });
        vm.expectRevert(bytes("verdict does not approve"));
        gate.executeSchnorr(_action(), v);
        console2.log("  offset de verdict = 0 sur un 'reject' -> REVERTE aussi");
        console2.log("  (on ne peut pas pointer ailleurs pour faire croire a un approve)");
    }
}
