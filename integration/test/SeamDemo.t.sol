// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";

// Sa source, importée telle quelle depuis le clone gitignoré. Aucune modification.
import {EnvelopeRegistry} from "bounded/EnvelopeRegistry.sol";

// Les nôtres.
import {InheritableAgentMandate} from "adn/InheritableAgentMandate.sol";
import {MandateAwareCursor} from "adn/MandateAwareCursor.sol";

/**
 * Démonstrateur — un compteur conscient du mandat, à côté du sien non modifié.
 *
 * N3 est une ILLUSTRATION : le refus sur gel est écrit par nous dans le contrat.
 * N1 et N2 sont les points falsifiables : aucune valeur attendue n'est écrite ici,
 * le rendu est imprimé tel quel.
 */
contract SeamDemoTest is Test {
    EnvelopeRegistry his;
    InheritableAgentMandate mandate;
    MandateAwareCursor ours;

    uint256 constant PK = 0xA11CE; // clé de test Foundry, jamais un compte réel
    address principal;

    uint256 constant CAP_PARENT = 1 ether;
    uint256 constant CAP_CHILD = 0.4 ether;
    address constant ASSET = address(0);
    address constant PAYEE = address(0xdEaD);

    bytes4 constant FROZEN_ID = 0x3985961d; // annoncé par son README, ligne 44

    uint256 parentId;
    uint256 childId;

    function setUp() public {
        principal = vm.addr(PK);
        his = new EnvelopeRegistry();
        mandate = new InheritableAgentMandate(address(this));
        ours = new MandateAwareCursor(address(mandate));

        parentId = mandate.mint(
            principal,
            InheritableAgentMandate.Mandate({
                maxSpendWei: CAP_PARENT, telomere: 3, requireLease: true, frozen: false
            }),
            _payees()
        );
        childId = mandate.spawn(
            parentId,
            principal,
            InheritableAgentMandate.Mandate({
                maxSpendWei: CAP_CHILD, telomere: 2, requireLease: true, frozen: false
            }),
            _payees()
        );
    }

    function _payees() internal pure returns (address[] memory p) {
        p = new address[](1);
        p[0] = PAYEE;
    }

    function _reason(bytes memory low) internal pure returns (string memory) {
        if (low.length < 4) return "revert sans donnee";
        bytes4 sel = bytes4(low[0]) | (bytes4(low[1]) >> 8) | (bytes4(low[2]) >> 16) | (bytes4(low[3]) >> 24);
        if (sel == MandateAwareCursor.MandateInactive.selector) return "MandateInactive(agentId)";
        if (sel == MandateAwareCursor.CapabilityMismatch.selector) return "CapabilityMismatch()";
        if (sel == MandateAwareCursor.NotActive.selector) return "NotActive()";
        if (sel == MandateAwareCursor.BoundExceeded.selector) return "BoundExceeded()";
        if (sel == MandateAwareCursor.Unauthorized.selector) return "Unauthorized()";
        if (sel == EnvelopeRegistry.BadWitness.selector) return "BadWitness()";
        if (sel == EnvelopeRegistry.NotActive.selector) return "EnvelopeRegistry.NotActive()";
        return vm.toString(sel);
    }

    function test_demo() public {
        console2.log("mandat parent agentId :", parentId);
        console2.log("enfant  agentId       :", childId);
        console2.log("plafond enfant (wei)  :", CAP_CHILD);

        // ------------------------------------------------------------ N1
        console2.log("");
        console2.log("=== N1 - comptage normal, avant tout gel (falsifiable) ===");
        bytes32 root = ours.capabilityRootFor(CAP_CHILD, ASSET, childId);
        console2.log("capabilityRoot (cap, actif, registre de mandats, agentId) :");
        console2.logBytes32(root);

        bytes memory initData = abi.encode(CAP_CHILD, ASSET, childId, keccak256("n1"));
        vm.prank(principal);
        bytes32 id = ours.registerEnvelope(principal, root, 0, initData);
        console2.log("registerEnvelope : aboutit");
        console2.log("   agentIdOf(enveloppe) rendu :", ours.agentIdOf(id));
        console2.log("   isActive() rendu           :", ours.isActive(id));

        vm.prank(principal);
        try ours.advanceCursor(id, abi.encode(uint256(0.05 ether))) returns (bytes32) {
            console2.log("advanceCursor(0.05) : aboutit");
        } catch (bytes memory low) {
            console2.log("advanceCursor(0.05) : reverte -", _reason(low));
        }
        console2.log("   spent rendu     :", ours.spent(id));
        console2.log("   remaining rendu :", ours.remaining(id));

        // ------------------------------------------------------------ N2
        console2.log("");
        console2.log("=== N2 - conformite a son interface gelee (falsifiable) ===");
        console2.log("supportsInterface(0x3985961d) rendu :", ours.supportsInterface(FROZEN_ID));
        console2.log("supportsInterface(0x01ffc9a7) rendu :", ours.supportsInterface(0x01ffc9a7));
        console2.log("supportsInterface(0xffffffff) rendu :", ours.supportsInterface(0xffffffff));
        console2.log("--- le sien, pour comparaison ---");
        console2.log("son registre, supportsInterface(0x3985961d) rendu :", his.supportsInterface(FROZEN_ID));

        // ------------------------------------------------------------ N3
        console2.log("");
        console2.log("=== N3 - le chaperon (ILLUSTRATION : le refus est code par nous) ===");
        mandate.freeze(parentId);
        console2.log("freeze(parent) execute");
        console2.log("mandate.isActive(enfant) rendu :", mandate.isActive(childId));
        console2.log("notre cursor, isActive(enveloppe) rendu :", ours.isActive(id));

        vm.prank(principal);
        try ours.advanceCursor(id, abi.encode(uint256(0.05 ether))) returns (bytes32) {
            console2.log("advanceCursor apres gel : aboutit");
        } catch (bytes memory low) {
            console2.log("advanceCursor apres gel : reverte -", _reason(low));
        }
        console2.log("   spent rendu :", ours.spent(id));

        // ------------------------------------------------------------ N4
        console2.log("");
        console2.log("=== N4 - contraste : SON registre non modifie, meme gel ===");
        bytes32 hisRoot = keccak256(abi.encode(CAP_CHILD, ASSET));
        vm.prank(principal);
        bytes32 hisId =
            his.registerEnvelope(principal, hisRoot, 0, abi.encode(CAP_CHILD, ASSET, keccak256("n4"), bytes("")));
        console2.log("son registerEnvelope : aboutit");
        console2.log("son isActive() rendu :", his.isActive(hisId));

        bytes32 prev = his.getCursor(hisId);
        bytes32 digest = his.advanceDigest(hisId, prev, 0.05 ether);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PK, digest);
        vm.prank(principal);
        try his.advanceCursor(hisId, abi.encode(uint256(0.05 ether), abi.encodePacked(r, s, v))) returns (bytes32) {
            console2.log("son advanceCursor, mandat gele : aboutit");
        } catch (bytes memory low) {
            console2.log("son advanceCursor, mandat gele : reverte -", _reason(low));
        }
        console2.log("   son spent rendu :", his.spent(hisId));
        console2.log("");
        console2.log("(mandate.isActive(enfant) vaut toujours :", mandate.isActive(childId), ")");
    }
}
