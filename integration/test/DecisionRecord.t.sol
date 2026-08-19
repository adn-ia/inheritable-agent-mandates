// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {MandateGateV3, IInheritableAgentMandate} from "adn/MandateGateV3.sol";
import {MandateDecisionRecord, IMandateGateV3Reader} from "adn/MandateDecisionRecord.sol";

/// Mandat réglable : chaque réponse est pilotée par le banc, aucune n'est devinée.
contract ConfigurableMandate is IInheritableAgentMandate {
    address public owner_ = address(0xA11CE);
    bool public active_ = true;
    bool public payee_ = true;
    uint256 public cap_ = 1 ether;

    function setOwner(address a) external { owner_ = a; }
    function setActive(bool b) external { active_ = b; }
    function setPayee(bool b) external { payee_ = b; }
    function setCap(uint256 c) external { cap_ = c; }

    function ownerOf(uint256) external view returns (address) { return owner_; }
    function parentOf(uint256) external pure returns (uint256) { return 0; }
    function mandateOf(uint256) external view returns (uint256, uint16, bool, bool) {
        return (cap_, 5, true, false);
    }
    function isActive(uint256) external view returns (bool) { return active_; }
    function payeeAllowed(uint256, address) external view returns (bool) { return payee_; }
}

/**
 * Banc du compte rendu de décision.
 *
 * Règle du banc, inchangée : le test n'affirme pas ce que la machine DEVRAIT faire, il
 * imprime ce qu'elle FAIT. Ce qui est asserté ici ne porte que sur la distinction que
 * le contrat existe pour établir — jamais sur une interprétation.
 *
 * Ce qui est mis en évidence : `execute` enchaîne ses `require` et ne rend QU'UN motif,
 * sous forme de chaîne de caractères. Le compte rendu en rend onze, typés, datés, avec
 * « périmé » distinct de « refusé » et « sans objet » distinct des deux.
 */
contract DecisionRecordTest is Test {
    MandateGateV3 gate;
    MandateDecisionRecord rec;
    ConfigurableMandate mandate;

    uint256 constant ISSUER_PK = 0xA11CE;
    address ISSUER;
    uint256 constant AGENT_ID = 1;
    address constant PAYEE = address(0xdEaD);
    uint256 constant AMOUNT = 0.1 ether;
    uint256 nonceCounter;

    string[11] CHECKS = [
        "BINDING          ", "FRESHNESS        ", "SIGNATURE        ",
        "ISSUER_AUTHORITY ", "NONCE_REPLAY     ", "VERDICT_DECISION ",
        "COMMITMENT_REPLAY", "AGENT_ACTIVE     ", "PAYEE_ALLOWED    ",
        "EFFECTIVE_CAP    ", "ROOM             "
    ];
    string[4] STATUS = ["ALLOW", "DENY", "STALE", "NOT_APPLICABLE"];
    string[3] REMEDY = ["NONE", "REFRESH", "STOP"];

    function setUp() public {
        mandate = new ConfigurableMandate();
        gate = new MandateGateV3(IInheritableAgentMandate(address(mandate)), address(this));
        rec = new MandateDecisionRecord(IMandateGateV3Reader(address(gate)));
        ISSUER = vm.addr(ISSUER_PK);
        gate.setIssuer(ISSUER, true);
        gate.credit(AGENT_ID, 1 ether);
        vm.warp(1_000_000);
    }

    function _action() internal pure returns (MandateGateV3.Action memory) {
        return MandateGateV3.Action({agentId: AGENT_ID, payee: PAYEE, amount: AMOUNT, salt: bytes32(uint256(7))});
    }

    function _verdict(bool approve, uint64 expiry) internal returns (MandateGateV3.Verdict memory v) {
        v = MandateGateV3.Verdict({
            artifactHash: gate.commit(_action()),
            issuer: ISSUER,
            approve: approve,
            nonce: ++nonceCounter,
            expiry: expiry,
            signature: ""
        });
        (uint8 vv, bytes32 r, bytes32 s) = vm.sign(ISSUER_PK, gate.verdictDigest(v));
        v.signature = abi.encodePacked(r, s, vv);
    }

    /// Recopie mot pour mot : les deux structs ont la même disposition ABI.
    function _as(MandateGateV3.Action memory a) internal pure returns (IMandateGateV3Reader.Action memory) {
        return IMandateGateV3Reader.Action({agentId: a.agentId, payee: a.payee, amount: a.amount, salt: a.salt});
    }
    function _as(MandateGateV3.Verdict memory v) internal pure returns (IMandateGateV3Reader.Verdict memory) {
        return IMandateGateV3Reader.Verdict({
            artifactHash: v.artifactHash, issuer: v.issuer, approve: v.approve,
            nonce: v.nonce, expiry: v.expiry, signature: v.signature
        });
    }

    function _print(MandateGateV3.Action memory a, MandateGateV3.Verdict memory v) internal view {
        MandateDecisionRecord.Finding[] memory f = rec.record(_as(a), _as(v));
        for (uint256 i = 0; i < f.length; i++) {
            console2.log(
                string.concat("    ", CHECKS[uint8(f[i].check)], " : ", STATUS[uint8(f[i].status)]),
                "  asOf=", f[i].asOf
            );
        }
        (bool allowed, MandateDecisionRecord.Remedy r, uint8 d, uint8 s, uint8 n) =
            rec.verdictOf(_as(a), _as(v));
        console2.log(string.concat("    -> remede : ", REMEDY[uint8(r)]));
        console2.log("    -> refus =", d, " perimes =", s);
        console2.log("    -> sans objet =", n, " permis =", allowed);
    }

    // ------------------------------------------------------------------

    function test_1_nominal_les_onze_repondent() public {
        MandateGateV3.Action memory a = _action();
        MandateGateV3.Verdict memory v = _verdict(true, uint64(block.timestamp + 1 days));
        console2.log("  CAS 1 - tout est en ordre");
        _print(a, v);

        (bool allowed, MandateDecisionRecord.Remedy r,,,) = rec.verdictOf(_as(a), _as(v));
        assertTrue(allowed, "devrait etre permis");
        assertEq(uint8(r), uint8(MandateDecisionRecord.Remedy.NONE));

        gate.execute(a, v);
        console2.log("    execute() aboutit, spent =", gate.spent(AGENT_ID));
    }

    function test_2_perime_seul_est_STALE_pas_DENY() public {
        MandateGateV3.Action memory a = _action();
        MandateGateV3.Verdict memory v = _verdict(true, uint64(block.timestamp + 1 hours));
        vm.warp(block.timestamp + 2 hours);

        console2.log("  CAS 2 - la preuve a vieilli, rien n'est refuse");
        _print(a, v);

        MandateDecisionRecord.Finding[] memory f = rec.record(_as(a), _as(v));
        assertEq(uint8(f[1].status), uint8(MandateDecisionRecord.Status.STALE), "FRESHNESS doit etre STALE");
        (, MandateDecisionRecord.Remedy r, uint8 d,,) = rec.verdictOf(_as(a), _as(v));
        assertEq(d, 0, "aucun refus reel");
        assertEq(uint8(r), uint8(MandateDecisionRecord.Remedy.REFRESH), "remede = rafraichir");

        vm.expectRevert(bytes("verdict expired"));
        gate.execute(a, v);
        console2.log("    execute() reverte, et tout ce qu'il rend est la chaine : verdict expired");
    }

    function test_3_refuse_seul_est_DENY() public {
        MandateGateV3.Action memory a = _action();
        MandateGateV3.Verdict memory v = _verdict(false, uint64(block.timestamp + 1 days));

        console2.log("  CAS 3 - la preuve est fraiche, l'emetteur refuse");
        _print(a, v);

        MandateDecisionRecord.Finding[] memory f = rec.record(_as(a), _as(v));
        assertEq(uint8(f[1].status), uint8(MandateDecisionRecord.Status.ALLOW), "FRESHNESS reste ALLOW");
        assertEq(uint8(f[5].status), uint8(MandateDecisionRecord.Status.DENY), "VERDICT_DECISION doit etre DENY");
        (, MandateDecisionRecord.Remedy r,,,) = rec.verdictOf(_as(a), _as(v));
        assertEq(uint8(r), uint8(MandateDecisionRecord.Remedy.STOP), "remede = arreter");
    }

    /// Le cas qui porte tout : les deux a la fois.
    function test_4_perime_ET_refuse_execute_ne_dit_que_le_premier() public {
        MandateGateV3.Action memory a = _action();
        MandateGateV3.Verdict memory v = _verdict(false, uint64(block.timestamp + 1 hours));
        vm.warp(block.timestamp + 2 hours);

        console2.log("  CAS 4 - perime ET refuse, en meme temps");
        _print(a, v);

        MandateDecisionRecord.Finding[] memory f = rec.record(_as(a), _as(v));
        assertEq(uint8(f[1].status), uint8(MandateDecisionRecord.Status.STALE));
        assertEq(uint8(f[5].status), uint8(MandateDecisionRecord.Status.DENY));

        (, MandateDecisionRecord.Remedy r, uint8 d, uint8 s,) = rec.verdictOf(_as(a), _as(v));
        assertEq(d, 1); assertEq(s, 1);
        assertEq(uint8(r), uint8(MandateDecisionRecord.Remedy.STOP), "STOP prime sur REFRESH");

        vm.expectRevert(bytes("verdict expired"));
        gate.execute(a, v);
        console2.log("    execute() dit : verdict expired  -> lu seul, il fait RAFRAICHIR");
        console2.log("    la verite est : refuse  -> rafraichir ne levera jamais ce refus");
    }

    /// Le seul « sans objet » réel de cette porte : aucun ancêtre n'a déclaré de plafond.
    function test_5_sans_plafond_la_question_du_plafond_n_existe_pas() public {
        mandate.setCap(type(uint256).max);
        MandateGateV3.Action memory a = _action();
        MandateGateV3.Verdict memory v = _verdict(true, uint64(block.timestamp + 1 days));

        console2.log("  CAS 5 - aucun plafond declare dans la lignee");
        _print(a, v);

        MandateDecisionRecord.Finding[] memory f = rec.record(_as(a), _as(v));
        assertEq(uint8(f[9].status), uint8(MandateDecisionRecord.Status.NOT_APPLICABLE));

        (bool allowed, MandateDecisionRecord.Remedy r,,, uint8 n) = rec.verdictOf(_as(a), _as(v));
        assertEq(n, 1);
        assertTrue(allowed, "sans objet n'empeche PAS d'executer");
        assertEq(uint8(r), uint8(MandateDecisionRecord.Remedy.NONE));

        gate.execute(a, v);   // et la porte le confirme
        console2.log("    execute() aboutit : le sans-objet n'a rien bloque");
    }

    function test_6_deux_refus_independants_un_seul_aller_retour() public {
        mandate.setPayee(false);
        mandate.setCap(0.01 ether);
        MandateGateV3.Action memory a = _action();
        MandateGateV3.Verdict memory v = _verdict(true, uint64(block.timestamp + 1 days));

        console2.log("  CAS 6 - beneficiaire interdit ET au-dessus du plafond");
        _print(a, v);

        MandateDecisionRecord.Finding[] memory f = rec.record(_as(a), _as(v));
        assertEq(uint8(f[8].status), uint8(MandateDecisionRecord.Status.DENY), "PAYEE_ALLOWED");
        assertEq(uint8(f[9].status), uint8(MandateDecisionRecord.Status.DENY), "EFFECTIVE_CAP");

        vm.expectRevert(bytes("payee not allowed"));
        gate.execute(a, v);
        console2.log("    execute() ne dit que : payee not allowed");
        console2.log("    le second motif ne se decouvre qu'au deuxieme appel");
    }

    function test_7_la_permission_composee_est_datee() public {
        MandateGateV3.Action memory a = _action();
        uint64 exp = uint64(block.timestamp + 3 hours);
        MandateGateV3.Verdict memory v = _verdict(true, exp);

        uint64 until = rec.composedValidUntil(_as(a), _as(v));
        console2.log("  CAS 7 - un accord n'est pas permanent");
        console2.log("    maintenant           :", block.timestamp);
        console2.log("    la permission composee vaut jusqu'a :", until);
        assertEq(until, exp, "le minimum des peremptions connues");

        vm.warp(uint256(exp) + 1);
        (, MandateDecisionRecord.Remedy r,, uint8 s,) = rec.verdictOf(_as(a), _as(v));
        console2.log("    une seconde plus tard, sans que rien d'autre ne bouge :");
        console2.log(string.concat("    remede -> ", REMEDY[uint8(r)]));
        assertEq(s, 1);
        assertEq(uint8(r), uint8(MandateDecisionRecord.Remedy.REFRESH));
    }

    function test_8_les_controles_restes_muets_repondent_enfin() public {
        MandateGateV3.Action memory a = _action();
        MandateGateV3.Verdict memory v = _verdict(true, uint64(block.timestamp + 1 days));

        // lien rompu : le verdict parle d'une AUTRE action
        v.artifactHash = keccak256("une autre action");
        console2.log("  CAS 8 - le verdict ne porte pas sur cette action");
        MandateDecisionRecord.Finding[] memory f = rec.record(_as(a), _as(v));
        assertEq(uint8(f[0].status), uint8(MandateDecisionRecord.Status.DENY), "BINDING");
        // La signature reste valide POUR CE VERDICT : elle repond dans son perimetre.
        console2.log("    BINDING refuse ; SIGNATURE repond sur SON objet, pas sur l'action");

        // emetteur non autorise, signature pourtant vraie
        MandateGateV3.Action memory a2 = _action();
        MandateGateV3.Verdict memory v2 = _verdict(true, uint64(block.timestamp + 1 days));
        gate.setIssuer(ISSUER, false);
        f = rec.record(_as(a2), _as(v2));
        assertEq(uint8(f[2].status), uint8(MandateDecisionRecord.Status.ALLOW), "SIGNATURE");
        assertEq(uint8(f[3].status), uint8(MandateDecisionRecord.Status.DENY), "ISSUER_AUTHORITY");
        console2.log("    signature vraie ET emetteur revoque : les deux le disent, separement");
        gate.setIssuer(ISSUER, true);

        // agent gele
        mandate.setActive(false);
        f = rec.record(_as(a2), _as(v2));
        assertEq(uint8(f[7].status), uint8(MandateDecisionRecord.Status.DENY), "AGENT_ACTIVE");
        mandate.setActive(true);

        // nonce et commitment deja consommes
        gate.execute(a2, v2);
        f = rec.record(_as(a2), _as(v2));
        assertEq(uint8(f[4].status), uint8(MandateDecisionRecord.Status.DENY), "NONCE_REPLAY");
        assertEq(uint8(f[6].status), uint8(MandateDecisionRecord.Status.DENY), "COMMITMENT_REPLAY");
        console2.log("    apres execution : nonce ET commitment refusent, tous les deux");
    }

    /// Le débordement : `spent + amount` panique. Le compte rendu doit tenir sa promesse.
    function test_9_montant_extreme_ne_fait_pas_paniquer_le_compte_rendu() public {
        MandateGateV3.Action memory a0 = _action();
        MandateGateV3.Verdict memory v0 = _verdict(true, uint64(block.timestamp + 1 days));
        gate.execute(a0, v0);                       // spent devient non nul
        assertGt(gate.spent(AGENT_ID), 0);

        MandateGateV3.Action memory a = MandateGateV3.Action({
            agentId: AGENT_ID, payee: PAYEE, amount: type(uint256).max, salt: bytes32(uint256(9))
        });
        MandateGateV3.Verdict memory v = MandateGateV3.Verdict({
            artifactHash: gate.commit(a), issuer: ISSUER, approve: true,
            nonce: ++nonceCounter, expiry: uint64(block.timestamp + 1 days), signature: ""
        });
        (uint8 vv, bytes32 r, bytes32 sg) = vm.sign(ISSUER_PK, gate.verdictDigest(v));
        v.signature = abi.encodePacked(r, sg, vv);

        console2.log("  CAS 9 - montant = max(uint256), spent non nul");
        MandateDecisionRecord.Finding[] memory f = rec.record(_as(a), _as(v));  // ne doit PAS paniquer
        assertEq(uint8(f[9].status), uint8(MandateDecisionRecord.Status.DENY), "EFFECTIVE_CAP");
        console2.log("    onze constats rendus, aucune panique ; EFFECTIVE_CAP refuse");
    }

    /// Test différentiel : le lecteur et la porte doivent TOUJOURS être d'accord sur
    /// l'issue. C'est le seul test qui peut tuer la démonstration.
    function testFuzz_10_differentiel(bool active, bool payee, uint96 cap, bool approve, bool fresh)
        public
    {
        mandate.setOwner(address(0));   // l'agent peut ne pas exister : la porte s'en moque
        mandate.setActive(active);
        mandate.setPayee(payee);
        mandate.setCap(cap);
        MandateGateV3.Action memory a = _action();
        MandateGateV3.Verdict memory v = _verdict(approve, uint64(block.timestamp + (fresh ? 1 days : 0)));
        if (!fresh) vm.warp(block.timestamp + 1);

        (bool allowed,,,,) = rec.verdictOf(_as(a), _as(v));
        // Le lecteur permet <=> la porte aboutit. Aucune exception tolérée.

        try gate.execute(a, v) returns (bytes32) {
            console2.log("  la porte, elle, ABOUTIT");
            assertTrue(allowed, "DIVERGENCE : la porte aboutit, le lecteur refuse");
        } catch Error(string memory reason) {
            console2.log(string.concat("  la porte REVERTE : ", reason));
            assertFalse(allowed, "DIVERGENCE : la porte reverte, le lecteur permet");
        }
    }
}
