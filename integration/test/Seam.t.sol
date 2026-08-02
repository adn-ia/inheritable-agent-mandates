// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";

// Source de blockbird, importée TELLE QUELLE depuis le clone séparé. Aucune modification.
import {EnvelopeRegistry} from "bounded/EnvelopeRegistry.sol";
import {AggregateBudgetCursor} from "bounded/AggregateBudgetCursor.sol";
import {IBoundedAgentAction} from "bounded/IBoundedAgentAction.sol";

import {InheritableAgentMandate} from "adn/InheritableAgentMandate.sol";

/**
 * Test de couture — brancher InheritableAgentMandate comme substrat derrière le
 * capabilityRoot que le cursor d'ERC-8312 mètre.
 *
 * Ce test n'affirme rien. Chaque appel est encadré, et son issue est imprimée
 * telle quelle : aboutit, ou reverte avec sa raison exacte. Aucune valeur attendue
 * n'est écrite ici. L'interprétation se fait après, à partir de ces lignes.
 */
contract SeamTest is Test {
    EnvelopeRegistry reg;
    AggregateBudgetCursor cursor;
    InheritableAgentMandate mandate;

    uint256 constant PK = 0xA11CE; // clé de test Foundry, jamais un compte réel
    address principal;

    uint256 constant CAP_PARENT = 1 ether;
    uint256 constant CAP_CHILD = 0.4 ether;
    address constant ASSET = address(0);
    address constant PAYEE = address(0xdEaD);

    uint256 parentId;
    uint256 childId;

    function setUp() public {
        principal = vm.addr(PK);
        reg = new EnvelopeRegistry();
        cursor = new AggregateBudgetCursor();
        mandate = new InheritableAgentMandate(address(this)); // le test est gardien
    }

    function _initData(uint256 cap, bytes32 salt) internal pure returns (bytes memory) {
        return abi.encode(cap, ASSET, salt, bytes(""));
    }

    function _profileRoot(uint256 cap) internal pure returns (bytes32) {
        return keccak256(abi.encode(cap, ASSET));
    }

    /// Identité de notre mandat : le hash qui lie l'agent à ses clauses.
    function _mandateRoot(uint256 agentId) internal view returns (bytes32) {
        (uint256 maxSpend, uint16 telomere, bool requireLease, bool frozen) = mandate.mandateOf(agentId);
        return keccak256(abi.encode(address(mandate), agentId, maxSpend, telomere, requireLease, frozen));
    }

    function _register(address who, bytes32 root, uint256 cap, bytes32 salt)
        internal
        returns (bool ok, bytes32 id, string memory err)
    {
        vm.prank(who);
        try reg.registerEnvelope(who, root, 0, _initData(cap, salt)) returns (bytes32 _id) {
            return (true, _id, "");
        } catch Error(string memory reason) {
            return (false, bytes32(0), reason);
        } catch (bytes memory low) {
            return (false, bytes32(0), _selector(low));
        }
    }

    function _advance(bytes32 id, uint256 amount) internal returns (bool ok, string memory err) {
        bytes32 prev = reg.getCursor(id);
        bytes32 digest = reg.advanceDigest(id, prev, amount);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(PK, digest);
        bytes memory witness = abi.encode(amount, abi.encodePacked(r, s, v));
        vm.prank(principal);
        try reg.advanceCursor(id, witness) returns (bytes32) {
            return (true, "");
        } catch Error(string memory reason) {
            return (false, reason);
        } catch (bytes memory low) {
            return (false, _selector(low));
        }
    }

    function _selector(bytes memory low) internal pure returns (string memory) {
        if (low.length < 4) return "revert sans donnee";
        bytes4 sel = bytes4(low[0]) | (bytes4(low[1]) >> 8) | (bytes4(low[2]) >> 16) | (bytes4(low[3]) >> 24);
        if (sel == EnvelopeRegistry.CapabilityMismatch.selector) return "CapabilityMismatch()";
        if (sel == EnvelopeRegistry.NotActive.selector) return "NotActive()";
        if (sel == EnvelopeRegistry.BoundExceeded.selector) return "BoundExceeded()";
        if (sel == EnvelopeRegistry.BadWitness.selector) return "BadWitness()";
        if (sel == EnvelopeRegistry.Unauthorized.selector) return "Unauthorized()";
        if (sel == EnvelopeRegistry.IdExists.selector) return "IdExists()";
        if (sel == AggregateBudgetCursor.CappedNodeCannotDelegate.selector) return "CappedNodeCannotDelegate()";
        return vm.toString(sel);
    }

    function test_seam() public {
        console2.log("=== montage ===");
        parentId = mandate.mint(
            principal,
            InheritableAgentMandate.Mandate({
                maxSpendWei: CAP_PARENT, telomere: 3, requireLease: true, frozen: false
            }),
            _payees()
        );
        console2.log("mandat parent agentId :", parentId);
        console2.log("plafond parent (wei)  :", CAP_PARENT);

        // ---------------------------------------------------------------- a
        console2.log("");
        console2.log("=== a. capabilityRoT lie a l'identite de notre mandat ===");
        bytes32 mRoot = _mandateRoot(parentId);
        console2.log("capabilityRoot propose (hash du mandat) :");
        console2.logBytes32(mRoot);
        (bool okA, , string memory errA) = _register(principal, mRoot, CAP_PARENT, keccak256("a"));
        console2.log("issue registerEnvelope :", okA ? "aboutit" : "reverte");
        if (!okA) console2.log("   raison :", errA);

        console2.log("");
        console2.log("--- a-bis : la forme imposee par le profil, keccak(cap, asset) ---");
        (bool okB, bytes32 idB, string memory errB) = _register(principal, _profileRoot(CAP_PARENT), CAP_PARENT, keccak256("b"));
        console2.log("issue registerEnvelope :", okB ? "aboutit" : "reverte");
        if (!okB) console2.log("   raison :", errB);
        if (okB) {
            (uint256 cap, address asset) = reg.bound(idB);
            console2.log("   bound cap   :", cap);
            console2.log("   bound asset :", asset);
            console2.log("   isActive    :", reg.isActive(idB));
            (bool okAdv, string memory errAdv) = _advance(idB, 0.1 ether);
            console2.log("   issue advanceCursor(0.1 ether) :", okAdv ? "aboutit" : "reverte");
            if (!okAdv) console2.log("      raison :", errAdv);
            console2.log("   spent     :", reg.spent(idB));
            console2.log("   remaining :", reg.remaining(idB));
        }

        // ---------------------------------------------------------------- b
        console2.log("");
        console2.log("=== b. spawn enfant sous notre mandat, puis enveloppe pour l'enfant ===");
        childId = mandate.spawn(
            parentId,
            principal,
            InheritableAgentMandate.Mandate({
                maxSpendWei: CAP_CHILD, telomere: 2, requireLease: true, frozen: false
            }),
            _payees()
        );
        console2.log("enfant agentId       :", childId);
        console2.log("plafond enfant (wei) :", CAP_CHILD);

        console2.log("--- enveloppe pour l'enfant, plafond 100x celui du mandat parent ---");
        uint256 wide = CAP_PARENT * 100;
        (bool okC, , string memory errC) = _register(principal, _profileRoot(wide), wide, keccak256("c"));
        console2.log("issue registerEnvelope(cap = 100 ETH) :", okC ? "aboutit" : "reverte");
        if (!okC) console2.log("   raison :", errC);

        console2.log("--- cote lui : capped node cannot delegate (AggregateBudgetCursor) ---");
        vm.prank(principal);
        bytes32 rootId = cursor.createRoot(principal, CAP_PARENT, 0, 0, keccak256("tree"));
        vm.prank(principal);
        uint64 cappedNode = cursor.delegate(rootId, 0, principal, CAP_CHILD);
        console2.log("noeud plafonne cree, nodeId :", cappedNode);
        vm.prank(principal);
        try cursor.delegate(rootId, cappedNode, principal, 0) returns (uint64) {
            console2.log("issue delegate depuis un noeud plafonne : aboutit");
        } catch Error(string memory reason) {
            console2.log("issue delegate depuis un noeud plafonne : reverte -", reason);
        } catch (bytes memory low) {
            console2.log("issue delegate depuis un noeud plafonne : reverte -", _selector(low));
        }

        // ---------------------------------------------------------------- c
        console2.log("");
        console2.log("=== c. freeze en cascade cote mandat, puis dep enses cote 8312 ===");
        (bool okD, bytes32 idD, ) = _register(principal, _profileRoot(CAP_CHILD), CAP_CHILD, keccak256("d"));
        console2.log("enveloppe de l'enfant enregistree :", okD ? "oui" : "non");
        console2.log("avant freeze - mandate.isActive(enfant) :", mandate.isActive(childId));
        console2.log("avant freeze - envelope.isActive()      :", reg.isActive(idD));

        mandate.freeze(parentId);
        console2.log("freeze(parent) execute");
        console2.log("apres freeze - mandate.isActive(enfant) :", mandate.isActive(childId));
        console2.log("apres freeze - envelope.isActive()      :", reg.isActive(idD));
        console2.log("apres freeze - envelope.remaining()     :", reg.remaining(idD));

        (bool okAdv2, string memory errAdv2) = _advance(idD, 0.05 ether);
        console2.log("issue advanceCursor apres freeze :", okAdv2 ? "aboutit" : "reverte");
        if (!okAdv2) console2.log("   raison :", errAdv2);
        console2.log("spent apres freeze :", reg.spent(idD));
    }

    function _payees() internal pure returns (address[] memory p) {
        p = new address[](1);
        p[0] = PAYEE;
    }
}
