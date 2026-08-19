// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {MandateGateV3, IInheritableAgentMandate} from "adn/MandateGateV3.sol";
import {MandateDecisionRecord, IMandateGateV3Reader} from "adn/MandateDecisionRecord.sol";
import {PrincipalConsent} from "adn/PrincipalConsent.sol";

/// Mandat avec une vraie lignée : parent 1 -> enfant 2. Le reste est permissif.
contract LineageMandate is IInheritableAgentMandate {
    mapping(uint256 => address) public owners;
    mapping(uint256 => uint256) public parents;

    function setOwner(uint256 id, address a) external { owners[id] = a; }
    function setParent(uint256 id, uint256 p) external { parents[id] = p; }

    function ownerOf(uint256 id) external view returns (address) { return owners[id]; }
    function parentOf(uint256 id) external view returns (uint256) { return parents[id]; }
    function mandateOf(uint256) external pure returns (uint256, uint16, bool, bool) {
        return (1 ether, 5, true, false);
    }
    function isActive(uint256) external pure returns (bool) { return true; }
    function payeeAllowed(uint256, address) external pure returns (bool) { return true; }
}

/**
 * Banc du consentement du donneur d'ordre.
 *
 * Ce qui est mis à l'épreuve : le consentement est une FEUILLE DE COUVERTURE, pas une
 * ligne de plus. Retiré, on n'ouvre pas la feuille des contrôles. Et il ne se mélange
 * jamais au décompte des onze : la porte déployée ne le connaît pas, et le banc le
 * démontre au lieu de le promettre.
 */
contract PrincipalConsentTest is Test {
    LineageMandate mandate;
    MandateGateV3 gate;
    MandateDecisionRecord rec;
    PrincipalConsent consent;

    uint256 constant ISSUER_PK = 0xA11CE;
    address ISSUER;
    address PARENT_OWNER = makeAddr("parent_owner");
    address CHILD_OWNER = makeAddr("child_owner");
    uint256 constant PARENT = 1;
    uint256 constant CHILD = 2;
    address constant PAYEE = address(0xdEaD);
    uint256 constant AMOUNT = 0.1 ether;
    uint256 nonceCounter;

    string[5] STATE = ["GRANTED", "WITHDRAWN", "RECHECK_REQUIRED", "NO_PRINCIPAL", "UNCONFIRMED"];

    function setUp() public {
        mandate = new LineageMandate();
        mandate.setOwner(PARENT, PARENT_OWNER);
        mandate.setOwner(CHILD, CHILD_OWNER);
        mandate.setParent(CHILD, PARENT);

        gate = new MandateGateV3(IInheritableAgentMandate(address(mandate)), address(this));
        rec = new MandateDecisionRecord(IMandateGateV3Reader(address(gate)));
        consent = new PrincipalConsent(rec);

        ISSUER = vm.addr(ISSUER_PK);
        gate.setIssuer(ISSUER, true);
        gate.credit(CHILD, 1 ether);
        vm.warp(1_000_000);
    }

    function _action(uint256 id) internal pure returns (MandateGateV3.Action memory) {
        return MandateGateV3.Action({agentId: id, payee: PAYEE, amount: AMOUNT, salt: bytes32(uint256(7))});
    }

    function _verdict(uint256 id) internal returns (MandateGateV3.Verdict memory v) {
        v = MandateGateV3.Verdict({
            artifactHash: gate.commit(_action(id)), issuer: ISSUER, approve: true,
            nonce: ++nonceCounter, expiry: uint64(block.timestamp + 1 days), signature: ""
        });
        (uint8 vv, bytes32 r, bytes32 s) = vm.sign(ISSUER_PK, gate.verdictDigest(v));
        v.signature = abi.encodePacked(r, s, vv);
    }

    function _as(MandateGateV3.Action memory a) internal pure returns (IMandateGateV3Reader.Action memory) {
        return IMandateGateV3Reader.Action({agentId: a.agentId, payee: a.payee, amount: a.amount, salt: a.salt});
    }
    function _as(MandateGateV3.Verdict memory v) internal pure returns (IMandateGateV3Reader.Verdict memory) {
        return IMandateGateV3Reader.Verdict({
            artifactHash: v.artifactHash, issuer: v.issuer, approve: v.approve,
            nonce: v.nonce, expiry: v.expiry, signature: v.signature
        });
    }

    // ------------------------------------------------------------------

    function test_1_accord_donne_la_feuille_s_ouvre() public {
        MandateGateV3.Action memory a = _action(CHILD);
        MandateGateV3.Verdict memory v = _verdict(CHILD);

        (PrincipalConsent.Consent st,,, bool consulted, MandateDecisionRecord.Finding[] memory f) =
            consent.evaluate(_as(a), _as(v));

        console2.log("  CAS 1 - accord donne");
        console2.log(string.concat("    consentement : ", STATE[uint8(st)]));
        console2.log("    feuille ouverte :", consulted, " constats :", f.length);
        assertEq(uint8(st), uint8(PrincipalConsent.Consent.GRANTED));
        assertTrue(consulted);
        assertEq(f.length, 11);
        assertTrue(consulted);
    }

    function test_2_retrait_on_n_ouvre_pas_la_feuille() public {
        vm.prank(CHILD_OWNER);
        consent.withdraw(CHILD);

        MandateGateV3.Action memory a = _action(CHILD);
        MandateGateV3.Verdict memory v = _verdict(CHILD);

        (PrincipalConsent.Consent st,, uint256 by, bool consulted, MandateDecisionRecord.Finding[] memory f) =
            consent.evaluate(_as(a), _as(v));

        console2.log("  CAS 2 - le donneur d'ordre retire son accord");
        console2.log(string.concat("    consentement : ", STATE[uint8(st)]), " decide par l'agent", by);
        console2.log("    feuille ouverte :", consulted, " constats :", f.length);
        assertEq(uint8(st), uint8(PrincipalConsent.Consent.WITHDRAWN));
        assertFalse(consulted, "on ne doit PAS consulter");
        assertEq(f.length, 0, "zero constat, pas onze refus");
    }

    /// Le retrait du parent ferme le sous-arbre, comme le gel.
    function test_3_le_retrait_cascade_sur_la_lignee() public {
        vm.prank(PARENT_OWNER);
        consent.withdraw(PARENT);

        (PrincipalConsent.Consent st,, uint256 by) = consent.consentOf(CHILD);
        console2.log("  CAS 3 - le PARENT retire, on interroge l'ENFANT");
        console2.log(string.concat("    consentement de l'enfant : ", STATE[uint8(st)]), " decide par l'agent", by);
        assertEq(uint8(st), uint8(PrincipalConsent.Consent.WITHDRAWN));
        assertEq(by, PARENT, "la decision vient du parent, et on le dit");
    }

    function test_4_un_tiers_ne_peut_pas_retirer() public {
        vm.prank(address(0xBAD));
        vm.expectRevert(bytes("not the principal"));
        consent.withdraw(CHILD);
        console2.log("  CAS 4 - un tiers tente le retrait -> REVERTE : not the principal");
    }

    /// « Je veux un second avis » : l'accord tient, la preuve ancienne ne vaut plus.
    function test_5_second_avis_deux_horloges_differentes() public {
        MandateGateV3.Action memory a = _action(CHILD);
        MandateGateV3.Verdict memory v = _verdict(CHILD);   // valable 24 h pour la porte

        vm.warp(block.timestamp + 2 hours);
        vm.prank(CHILD_OWNER);
        consent.requireRecheck(CHILD);

        (PrincipalConsent.Consent st, uint64 since,, bool consulted, MandateDecisionRecord.Finding[] memory f) =
            consent.evaluate(_as(a), _as(v));

        console2.log("  CAS 5 - second avis exige");
        console2.log(string.concat("    consentement : ", STATE[uint8(st)]), " fraicheur exigee depuis", since);

        assertEq(uint8(st), uint8(PrincipalConsent.Consent.RECHECK_REQUIRED));
        assertFalse(consulted, "second avis = on sort de l'hosto, le dossier est clos");
        assertEq(f.length, 0, "on ne poursuit PAS sur l'ancienne preuve");

        // Il obtient son second avis et s'en satisfait : le dossier se rouvre.
        vm.prank(CHILD_OWNER);
        consent.affirm(CHILD);
        (st,,, consulted, f) = consent.evaluate(_as(a), _as(v));
        console2.log("    apres reaffirmation : feuille ouverte =", consulted, " constats =", f.length);
        assertEq(uint8(st), uint8(PrincipalConsent.Consent.GRANTED));
        assertTrue(consulted);
    }

    function test_6_second_avis_preuve_anterieure_rejetee() public {
        MandateGateV3.Action memory a = _action(CHILD);
        MandateGateV3.Verdict memory v = _verdict(CHILD);

        vm.warp(block.timestamp + 2 days);       // la preuve est morte pour tout le monde
        vm.prank(CHILD_OWNER);
        consent.requireRecheck(CHILD);

        (,,, bool consulted6, MandateDecisionRecord.Finding[] memory f) = consent.evaluate(_as(a), _as(v));
        console2.log("  CAS 6 - second avis demande : rien ne se poursuit sur l'ancien dossier");
        assertFalse(consulted6, "aucune consultation tant que le second avis n'est pas rendu");
        assertEq(f.length, 0);
    }

    /// 🔴 Le piège de ce matin, retourné en test : la porte IGNORE le consentement.
    function test_7_la_porte_deployee_ignore_le_consentement() public {
        vm.prank(CHILD_OWNER);
        consent.withdraw(CHILD);

        MandateGateV3.Action memory a = _action(CHILD);
        MandateGateV3.Verdict memory v = _verdict(CHILD);

        (PrincipalConsent.Consent st,,, bool consulted,) = consent.evaluate(_as(a), _as(v));
        assertEq(uint8(st), uint8(PrincipalConsent.Consent.WITHDRAWN));
        assertFalse(consulted);

        // ...et pourtant :
        gate.execute(a, v);
        console2.log("  CAS 7 - accord RETIRE, et la porte execute quand meme");
        console2.log("    spent =", gate.spent(CHILD));
        assertEq(gate.spent(CHILD), AMOUNT, "la porte ne connait pas le consentement");

        // L'invariant differentiel n'est pas casse : il porte sur les ONZE, pas sur l'accord.
        (bool allowed,,,,,) = rec.verdictOf(_as(a), _as(v));
        console2.log("    le compte rendu des ONZE, lui, reste d'accord avec la porte :", allowed);
        console2.log("    -> le consentement est DECRIT, pas APPLIQUE. C'est dit, pas cache.");
    }

    /// 🔴 LA QUESTION DE HELMY : les trois sont d'accord, mais le patient est mort.
    /// Il ne peut pas s'opposer — et il ne peut pas consentir non plus.
    function test_8_patient_mort_le_silence_ne_vaut_pas_accord() public {
        uint256 ORPHAN = 42;                       // aucun proprietaire enregistre
        assertEq(mandate.ownerOf(ORPHAN), address(0), "personne ne peut consentir");

        MandateGateV3.Action memory a = _action(ORPHAN);
        MandateGateV3.Verdict memory v = _verdict(ORPHAN);

        (PrincipalConsent.Consent st,, uint256 by, bool consulted, MandateDecisionRecord.Finding[] memory f) =
            consent.evaluate(_as(a), _as(v));

        console2.log("  CAS 8 - aucun donneur d'ordre : personne pour consentir NI pour refuser");
        console2.log(string.concat("    consentement : ", STATE[uint8(st)]), " sur l'agent", by);
        console2.log("    feuille ouverte :", consulted, " constats :", f.length);

        assertEq(uint8(st), uint8(PrincipalConsent.Consent.NO_PRINCIPAL));
        assertFalse(consulted, "le silence NE vaut PAS accord");
        assertEq(f.length, 0);
        assertTrue(uint8(st) != uint8(PrincipalConsent.Consent.WITHDRAWN), "ce n'est PAS un refus");
        assertTrue(uint8(st) != uint8(PrincipalConsent.Consent.GRANTED), "ce n'est PAS un accord");
    }

    /// Le patient est vivant mais on ne l'a plus entendu : l'accord n'est pas eternel.
    function test_9_accord_non_reaffirme_n_est_plus_acquis() public {
        vm.startPrank(CHILD_OWNER);
        consent.setAffirmationPeriod(CHILD, 30 days);
        consent.affirm(CHILD);
        vm.stopPrank();

        (PrincipalConsent.Consent st,,) = consent.consentOf(CHILD);
        console2.log("  CAS 9 - accord reaffirme aujourd'hui");
        console2.log(string.concat("    -> ", STATE[uint8(st)]));
        assertEq(uint8(st), uint8(PrincipalConsent.Consent.GRANTED));

        vm.warp(block.timestamp + 31 days);
        (st,,) = consent.consentOf(CHILD);
        console2.log("    31 jours plus tard, sans un mot de sa part :");
        console2.log(string.concat("    -> ", STATE[uint8(st)]));
        assertEq(uint8(st), uint8(PrincipalConsent.Consent.UNCONFIRMED), "un accord est date");

        MandateGateV3.Action memory a = _action(CHILD);
        MandateGateV3.Verdict memory v = _verdict(CHILD);
        (,,, bool consulted, MandateDecisionRecord.Finding[] memory f) = consent.evaluate(_as(a), _as(v));
        assertFalse(consulted);
        assertEq(f.length, 0);

        vm.prank(CHILD_OWNER);
        consent.affirm(CHILD);
        (st,,) = consent.consentOf(CHILD);
        console2.log("    il redonne signe de vie :");
        console2.log(string.concat("    -> ", STATE[uint8(st)]));
        assertEq(uint8(st), uint8(PrincipalConsent.Consent.GRANTED));
    }

    /// Les trois blocages ne se confondent pas : memes effets, remedes opposes.
    function test_10_trois_blocages_trois_remedes() public {
        vm.prank(CHILD_OWNER);
        consent.withdraw(CHILD);
        (PrincipalConsent.Consent w,,) = consent.consentOf(CHILD);

        (PrincipalConsent.Consent n,,) = consent.consentOf(42);

        vm.startPrank(PARENT_OWNER);
        consent.setAffirmationPeriod(PARENT, 1 days);
        vm.stopPrank();
        vm.warp(block.timestamp + 2 days);
        (PrincipalConsent.Consent u,,) = consent.consentOf(PARENT);

        console2.log("  CAS 10 - trois blocages distincts");
        console2.log(string.concat("    refus         -> ", STATE[uint8(w)], "  : s'arreter, lui parler"));
        console2.log(string.concat("    pas de titulaire -> ", STATE[uint8(n)], "  : escalader, personne a qui parler"));
        console2.log(string.concat("    plus de nouvelles -> ", STATE[uint8(u)], "  : redemander"));

        assertTrue(consent.blocksConsultation(w) && consent.blocksConsultation(n) && consent.blocksConsultation(u));
        assertTrue(uint8(w) != uint8(n) && uint8(n) != uint8(u) && uint8(w) != uint8(u), "trois etats distincts");
    }

    /// 🔴 Le refus survit au changement de propriétaire. On ne l'efface pas, on le FRANCHIT.
    function test_11_le_nouveau_proprietaire_ne_peut_pas_effacer_le_refus() public {
        address ALICE = makeAddr("alice");
        address BOB = makeAddr("bob");
        uint256 ID = 7;

        mandate.setOwner(ID, ALICE);
        vm.prank(ALICE);
        consent.withdraw(ID);

        (PrincipalConsent.Consent st,,) = consent.consentOf(ID);
        assertEq(uint8(st), uint8(PrincipalConsent.Consent.WITHDRAWN));
        console2.log("  CAS 11 - Alice refuse, puis l'identite passe a Bob");

        // L'identite change de mains (la norme autorise une identite transferable).
        mandate.setOwner(ID, BOB);

        // Bob est bien le donneur d'ordre en titre... et ca ne suffit pas.
        vm.prank(BOB);
        vm.expectRevert(bytes("not the principal who withdrew"));
        consent.restore(ID);
        console2.log("    Bob tente restore() -> REVERTE : not the principal who withdrew");

        // ...et il ne peut pas non plus lever sans motif.
        vm.prank(BOB);
        vm.expectRevert(bytes("justification required"));
        consent.overrideWithdrawal(ID, bytes32(0));
        console2.log("    Bob tente de lever sans motif -> REVERTE : justification required");

        // Le refus tient toujours.
        (st,,) = consent.consentOf(ID);
        assertEq(uint8(st), uint8(PrincipalConsent.Consent.WITHDRAWN), "le refus d'Alice tient");

        // Franchissement explicite, motive, trace.
        bytes32 motif = keccak256("succession reglee, acte notarie 2026-08-19");
        vm.prank(BOB);
        consent.overrideWithdrawal(ID, motif);

        (st,,) = consent.consentOf(ID);
        assertEq(uint8(st), uint8(PrincipalConsent.Consent.GRANTED));

        (bool happened, address prev, address by, bytes32 just,) = consent.overrideOf(ID);
        console2.log("    Bob leve AVEC motif -> accord retabli, et la trace reste :");
        console2.log("      refus prononce par :", prev);
        console2.log("      leve par           :", by);
        assertTrue(happened, "la trace ne s'efface pas");
        assertEq(prev, ALICE);
        assertEq(by, BOB);
        assertEq(just, motif);
    }

    /// Celui qui a refuse revient dessus librement : pas de motif exige.
    function test_12_son_propre_refus_se_leve_librement() public {
        vm.prank(CHILD_OWNER);
        consent.withdraw(CHILD);

        vm.prank(CHILD_OWNER);
        vm.expectRevert(bytes("your own withdrawal: use restore"));
        consent.overrideWithdrawal(CHILD, keccak256("inutile"));

        vm.prank(CHILD_OWNER);
        consent.restore(CHILD);

        (PrincipalConsent.Consent st,,) = consent.consentOf(CHILD);
        assertEq(uint8(st), uint8(PrincipalConsent.Consent.GRANTED));

        (bool happened,,,,) = consent.overrideOf(CHILD);
        assertFalse(happened, "revenir sur son propre refus n'est pas un franchissement");
        console2.log("  CAS 12 - il revient sur son propre refus : libre, et aucune trace de franchissement");
    }
}
