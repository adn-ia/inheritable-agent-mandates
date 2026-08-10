// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {InheritableAgentMandateV3} from "adn/InheritableAgentMandateV3.sol";
import {VulnerableNoConservation} from "./_VulnerableV3.sol";
import {MandateGateV3, IInheritableAgentMandate} from "adn/MandateGateV3.sol";

/// Le gate lit mandateOf a 4 valeurs (signature v1) ; V3 en rend 5. Cet adaptateur
/// ne fait que retirer validUntil  il n'invente rien.
contract V3Adapter is IInheritableAgentMandate {
    InheritableAgentMandateV3 public m;
    constructor(InheritableAgentMandateV3 _m) { m = _m; }
    function ownerOf(uint256 id) external view returns (address) { return m.ownerOf(id); }
    function parentOf(uint256 id) external view returns (uint256) { return m.parentOf(id); }
    function mandateOf(uint256 id) external view returns (uint256, uint16, bool, bool) {
        (uint256 cap,, uint16 tel, bool lease, bool fr) = m.mandateOf(id);
        return (cap, tel, lease, fr);
    }
    function isActive(uint256 id) external view returns (bool) { return m.isActive(id); }
    function payeeAllowed(uint256 id, address p) external view returns (bool) { return m.payeeAllowed(id, p); }
}

/**
 * Deux choses que la premiere suite ne prouvait pas.
 *
 *  A. Une suite verte ne dit rien tant qu'on n'a pas montre qu'elle CASSE contre un
 *     build sans l'invariant. Paire break/hold, un seul mot de diff entre les deux.
 *  B. La limite du cas 5 etait de l'arithmetique  deux plafonds additionnes. Ici on
 *     DEPENSE reellement a travers le gate, et on constate le total.
 */
contract ConservationPairTest is Test {
    address guardian = address(this);
    address owner = makeAddr("owner");
    address kid = makeAddr("kid");
    address constant PAYEE = address(0xdEaD);
    address[] payees;

    uint256 constant ISSUER_PK = 0xA11CE;

    function setUp() public { payees.push(PAYEE); }

    function _m3(uint256 cap, uint16 tel) internal pure returns (InheritableAgentMandateV3.Mandate memory) {
        return InheritableAgentMandateV3.Mandate({
            maxSpendWei: cap, validUntil: 0, telomere: tel, requireLease: false, frozen: false });
    }
    function _mv(uint256 cap, uint16 tel) internal pure returns (VulnerableNoConservation.Mandate memory) {
        return VulnerableNoConservation.Mandate({
            maxSpendWei: cap, validUntil: 0, telomere: tel, requireLease: false, frozen: false });
    }

    //  A. paire break / hold 

    function test_A1_BREAK_fanout_passe_sans_conservation() public {
        VulnerableNoConservation v = new VulnerableNoConservation(guardian);
        uint256 root = v.mint(owner, _mv(500, 8), payees);
        vm.startPrank(owner);
        v.spawn(root, kid, _mv(500, 7), payees);
        uint256 c2 = v.spawn(root, kid, _mv(500, 7), payees);
        uint256 c3 = v.spawn(root, kid, _mv(500, 7), payees);
        vm.stopPrank();
        console2.log("  build VULNERABLE : 3 enfants a 500 sous un parent a 500");
        console2.log("    ids", c2, c3);
        console2.log("    allocatedOf(root) =", v.allocatedOf(root), "(jamais debite)");
        console2.log("    availableBudget(root) =", v.availableBudget(root));
        console2.log("    -> FAN-OUT REUSSI : 1500 distribues depuis un plafond de 500");
        assertEq(v.availableBudget(root), 500, "le build vulnerable ne debite rien");
    }

    function test_A2_HOLD_le_meme_scenario_sur_V3() public {
        InheritableAgentMandateV3 m = new InheritableAgentMandateV3(guardian);
        uint256 root = m.mint(owner, _m3(500, 8), payees);
        vm.prank(owner);
        m.spawn(root, kid, _m3(500, 7), payees);
        console2.log("  build REEL : 1er enfant a 500 -> passe, availableBudget =", m.availableBudget(root));
        vm.prank(owner);
        vm.expectRevert(bytes("conservation: exceeds parent unallocated budget"));
        m.spawn(root, kid, _m3(500, 7), payees);
        console2.log("    2e enfant -> REVERTE");
        vm.prank(owner);
        vm.expectRevert(bytes("conservation: exceeds parent unallocated budget"));
        m.spawn(root, kid, _m3(1, 7), payees);
        console2.log("    meme a 1 wei -> REVERTE");
    }

    function test_A3_BREAK_partition_illimitee_sans_conservation() public {
        VulnerableNoConservation v = new VulnerableNoConservation(guardian);
        uint256 root = v.mint(owner, _mv(500, 8), payees);
        vm.startPrank(owner);
        uint256 total;
        for (uint256 i; i < 10; i++) { v.spawn(root, kid, _mv(250, 7), payees); total += 250; }
        vm.stopPrank();
        console2.log("  build VULNERABLE : 10 enfants a 250 =", total, "sous un plafond de 500");
        assertEq(total, 2500);
        console2.log("    -> 5x le plafond du parent, aucun refus");
    }

    //  B. la limite, par la DEPENSE reelle 

    function _sign(MandateGateV3 gate, MandateGateV3.Action memory a, uint256 nonce)
        internal view returns (MandateGateV3.Verdict memory v)
    {
        v = MandateGateV3.Verdict({ artifactHash: gate.commit(a), issuer: vm.addr(ISSUER_PK),
            approve: true, nonce: nonce, expiry: uint64(block.timestamp + 1 days), signature: "" });
        (uint8 pv, bytes32 r, bytes32 s) = vm.sign(ISSUER_PK, gate.verdictDigest(v));
        v.signature = abi.encodePacked(r, s, pv);
    }

    function test_B_la_limite_par_depense_reelle() public {
        InheritableAgentMandateV3 m = new InheritableAgentMandateV3(guardian);
        V3Adapter ad = new V3Adapter(m);
        MandateGateV3 gate = new MandateGateV3(IInheritableAgentMandate(address(ad)), guardian);
        gate.setIssuer(vm.addr(ISSUER_PK), true);

        uint256 root = m.mint(owner, _m3(500, 8), payees);
        vm.prank(owner);
        uint256 child = m.spawn(root, kid, _m3(500, 7), payees);
        console2.log("  racine 500 -> enfant 500  availableBudget(racine) =", m.availableBudget(root));

        gate.credit(root, 500);
        gate.credit(child, 500);

        MandateGateV3.Action memory ar = MandateGateV3.Action({
            agentId: root, payee: PAYEE, amount: 500, salt: keccak256("root") });
        gate.execute(ar, _sign(gate, ar, 1));
        MandateGateV3.Action memory ac = MandateGateV3.Action({
            agentId: child, payee: PAYEE, amount: 500, salt: keccak256("child") });
        gate.execute(ac, _sign(gate, ac, 2));

        uint256 sr = gate.spent(root);
        uint256 sc = gate.spent(child);
        console2.log("  DEPENSE REELLE a travers le gate :");
        console2.log("    spent(racine) =", sr);
        console2.log("    spent(enfant) =", sc);
        console2.log("    total         =", sr + sc, "pour un plafond de racine de 500");

        assertEq(sr, 500, "la racine a bien depense 500");
        assertEq(sc, 500, "l'enfant a bien depense 500");
        assertEq(sr + sc, 1000, "comportement reel : l'arbre depense 2x le plafond de la racine");
        console2.log("  -> la conservation borne la DISTRIBUTION, pas la CONSOMMATION.");
        console2.log("     Ce n'est plus une addition de plafonds : c'est de la depense constatee.");
    }
}
