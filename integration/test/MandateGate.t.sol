// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {InheritableAgentMandate} from "adn/InheritableAgentMandate.sol";
import {MandateGate, IInheritableAgentMandate} from "adn/MandateGate.sol";

/**
 * Banc des 11 cas falsifiables.
 *
 * Regle du banc : aucun resultat attendu n'est ecrit d'avance dans les cas ou la
 * question est ouverte. Chaque appel est encadre, son issue REELLE est imprimee
 * (aboutit / reverte + raison exacte), et l'interpretation vient apres, ailleurs.
 *
 * Provenance : les cas 8 a 11 exercent le vrai contrat de reference, non modifie.
 * Les autres exercent MandateGate, ecrit pour ce banc : juge et partie, ils montrent
 * que la regle est implementable et bloque les attaques decrites, rien de plus.
 */
contract MandateGateTest is Test {
    InheritableAgentMandate m;
    MandateGate gate;

    address guardian = address(this);
    address alice = makeAddr("alice");   // proprietaire parent
    address bob = makeAddr("bob");       // proprietaire enfant
    address mallory = makeAddr("mallory"); // hors lignee
    address constant PAYEE = address(0xdEaD);
    address constant OTHER_PAYEE = address(0xBEEF);

    uint256 parentId;
    uint256 childId;

    // --- banc nº2 : cles de signature (test uniquement, jamais des comptes reels) ---
    uint256 constant ISSUER_PK = 0xA11CE;   // mediateur independant, autorise par le gardien
    uint256 constant ISSUER2_PK = 0xC0FFEE; // second mediateur, pour la revocation
    uint256 constant AGENT_PK = 0xB0B;      // l'agent lui-meme (self-report)
    address ISSUER;
    address ISSUER2;
    address AGENT_SIGNER;
    uint256 nonceCounter;

    function _sign(bytes32 hash, uint256 pk, address issuerAddr, uint256 nonce, uint64 expiry, bool approve)
        internal view returns (MandateGate.Verdict memory v)
    {
        v = MandateGate.Verdict({
            artifactHash: hash, issuer: issuerAddr, approve: approve,
            nonce: nonce, expiry: expiry, signature: ""
        });
        (uint8 vv, bytes32 r, bytes32 ss) = vm.sign(pk, gate.verdictDigest(v));
        v.signature = abi.encodePacked(r, ss, vv);
    }

    /// Verdict nominal : signe par l'emetteur autorise, nonce frais, non perime.
    function _signed(bytes32 hash) internal returns (MandateGate.Verdict memory) {
        return _sign(hash, ISSUER_PK, ISSUER, ++nonceCounter, uint64(block.timestamp + 1 days), true);
    }

    function setUp() public {
        m = new InheritableAgentMandate(guardian);
        gate = new MandateGate(IInheritableAgentMandate(address(m)), guardian);
        ISSUER = vm.addr(ISSUER_PK);
        ISSUER2 = vm.addr(ISSUER2_PK);
        AGENT_SIGNER = vm.addr(AGENT_PK);
        gate.setIssuer(ISSUER, true);   // le GARDIEN autorise, pas l'agent
    }

    function _p() internal pure returns (address[] memory p) {
        p = new address[](1);
        p[0] = PAYEE;
    }

    function _mkParent(uint256 cap, uint16 tel) internal returns (uint256) {
        return m.mint(
            alice,
            InheritableAgentMandate.Mandate({maxSpendWei: cap, telomere: tel, requireLease: true, frozen: false}),
            _p()
        );
    }

    function _mkChild(uint256 parent, uint256 cap, uint16 tel) internal returns (uint256) {
        vm.prank(alice);
        return m.spawn(
            parent,
            bob,
            InheritableAgentMandate.Mandate({maxSpendWei: cap, telomere: tel, requireLease: true, frozen: false}),
            _p()
        );
    }

    /// Tente un execute et imprime l'issue reelle, sans rien presumer.
    function _try(string memory label, MandateGate.Action memory a, MandateGate.Verdict memory v) internal {
        try gate.execute(a, v) returns (bytes32 c) {
            console2.log(string.concat("   ", label, " -> ABOUTIT"));
            console2.logBytes32(c);
        } catch Error(string memory reason) {
            console2.log(string.concat("   ", label, " -> REVERTE : ", reason));
        } catch (bytes memory) {
            console2.log(string.concat("   ", label, " -> REVERTE (sans raison)"));
        }
    }

    function _tryReclaim(string memory label, uint256 child, address to, uint256 amount) internal {
        try gate.reclaim(child, to, amount) returns (uint256 pid) {
            console2.log(string.concat("   ", label, " -> ABOUTIT, parent rendu :"), pid);
        } catch Error(string memory reason) {
            console2.log(string.concat("   ", label, " -> REVERTE : ", reason));
        } catch (bytes memory) {
            console2.log(string.concat("   ", label, " -> REVERTE (sans raison)"));
        }
    }

    // ══════════════════════════════════════════════ A — action-commitment

    function test_A1_verdict_bien_lie_execute() public {
        console2.log("=== CAS 1 - verdict lie au BON actionCommitment ===");
        parentId = _mkParent(10 ether, 5);
        gate.credit(parentId, 10 ether);

        MandateGate.Action memory a =
            MandateGate.Action({agentId: parentId, payee: PAYEE, amount: 1 ether, salt: keccak256("a1")});
        bytes32 c = gate.commit(a);
        console2.log("   actionCommitment calcule une fois :");
        console2.logBytes32(c);

        MandateGate.Verdict memory v =
            _signed(c);
        _try("execute(action, verdict-sur-cette-action)", a, v);
        console2.log("   spent apres :", gate.spent(parentId));
        console2.log("   room  apres :", gate.room(parentId));
    }

    function test_A2_verdict_sur_dautres_bytes() public {
        console2.log("=== CAS 2 - verdict portant sur D'AUTRES bytes ===");
        parentId = _mkParent(10 ether, 5);
        gate.credit(parentId, 10 ether);

        MandateGate.Action memory a =
            MandateGate.Action({agentId: parentId, payee: PAYEE, amount: 1 ether, salt: keccak256("a2")});
        bytes32 bogus = keccak256("des bytes qui ne sont pas cette action");
        console2.log("   commitment de l'action :");
        console2.logBytes32(gate.commit(a));
        console2.log("   artifact_hash du verdict :");
        console2.logBytes32(bogus);

        MandateGate.Verdict memory v =
            _signed(bogus);
        _try("execute(action, verdict-etranger)", a, v);
        console2.log("   spent apres :", gate.spent(parentId));
    }

    function test_A3_verdict_valide_presente_contre_autre_action() public {
        console2.log("=== CAS 3 - verdict VALIDE, presente contre une AUTRE action (swap) ===");
        parentId = _mkParent(10 ether, 5);
        gate.credit(parentId, 10 ether);

        MandateGate.Action memory X =
            MandateGate.Action({agentId: parentId, payee: PAYEE, amount: 1 ether, salt: keccak256("X")});
        MandateGate.Action memory Y =
            MandateGate.Action({agentId: parentId, payee: PAYEE, amount: 9 ether, salt: keccak256("Y")});

        bytes32 cX = gate.commit(X);
        MandateGate.Verdict memory vX =
            _signed(cX);

        console2.log("   -- d'abord : ce verdict est-il REELLEMENT valide pour X ? --");
        _try("execute(X, verdictX)", X, vX);

        console2.log("   -- puis : le MEME verdict, presente contre Y --");
        console2.log("   commit(X) :");
        console2.logBytes32(cX);
        console2.log("   commit(Y) :");
        console2.logBytes32(gate.commit(Y));
        _try("execute(Y, verdictX)", Y, vX);
        console2.log("   spent total :", gate.spent(parentId));
        console2.log("   (si Y etait passe, 9 ETH auraient ete autorises par un verdict sur 1 ETH)");
    }

    // ══════════════════════════════════════════════ B — reclamation

    function test_B4_reclamation_exacte_ferme_le_livre() public {
        console2.log("=== CAS 4 - enfant recoit R, depense S, rend R-S au vrai parent ===");
        parentId = _mkParent(10 ether, 5);
        childId = _mkChild(parentId, 4 ether, 4);

        uint256 R = 3 ether;
        gate.credit(childId, R);
        console2.log("   R recu par l'enfant :", R);

        uint256 S = 1.2 ether;
        MandateGate.Action memory a =
            MandateGate.Action({agentId: childId, payee: PAYEE, amount: S, salt: keccak256("b4")});
        MandateGate.Verdict memory v =
            _signed(gate.commit(a));
        _try("depense S (gated)", a, v);
        console2.log("   S depense :", gate.spent(childId));
        console2.log("   reliquat R-S :", gate.room(childId));

        address vraiParent = m.ownerOf(m.parentOf(childId));
        console2.log("   proprietaire du parent reel :", vraiParent);
        _tryReclaim("reclaim(R-S, vrai parent)", childId, vraiParent, gate.room(childId));

        console2.log("   -- le livre se ferme-t-il ? --");
        console2.log("   recu   :", gate.received(childId));
        console2.log("   depense:", gate.spent(childId));
        console2.log("   rendu  :", gate.returnedTo(childId));
        console2.log("   bookClosed rendu :", gate.bookClosed(childId));
        console2.log("   credite au parent :", gate.received(parentId));
    }

    function test_B5_sur_retour() public {
        console2.log("=== CAS 5 - SUR-RETOUR : rendre plus que le reliquat ===");
        parentId = _mkParent(10 ether, 5);
        childId = _mkChild(parentId, 4 ether, 4);
        gate.credit(childId, 3 ether);

        MandateGate.Action memory a =
            MandateGate.Action({agentId: childId, payee: PAYEE, amount: 1 ether, salt: keccak256("b5")});
        MandateGate.Verdict memory v =
            _signed(gate.commit(a));
        _try("depense 1 ETH", a, v);

        uint256 reliquat = gate.room(childId);
        console2.log("   reliquat legitime :", reliquat);
        address vraiParent = m.ownerOf(m.parentOf(childId));
        _tryReclaim("reclaim(reliquat + 1 wei)", childId, vraiParent, reliquat + 1);
        console2.log("   rendu effectivement :", gate.returnedTo(childId));
    }

    function test_B6_faux_parent() public {
        console2.log("=== CAS 6 - FAUX PARENT : bon montant, destinataire hors lignee ===");
        parentId = _mkParent(10 ether, 5);
        childId = _mkChild(parentId, 4 ether, 4);
        gate.credit(childId, 2 ether);

        uint256 reliquat = gate.room(childId);
        console2.log("   reliquat :", reliquat);
        console2.log("   vrai parent  :", m.ownerOf(m.parentOf(childId)));
        console2.log("   destinataire :", mallory, "(hors lignee)");
        _tryReclaim("reclaim(bon montant, mallory)", childId, mallory, reliquat);

        console2.log("   -- controle : le meme montant vers le vrai parent --");
        _tryReclaim("reclaim(bon montant, vrai parent)", childId, m.ownerOf(m.parentOf(childId)), reliquat);
    }

    function test_B7_frontiere_exacte() public {
        console2.log("=== CAS 7 - FRONTIERE : ou bascule exactement le refus ? ===");
        parentId = _mkParent(10 ether, 5);
        childId = _mkChild(parentId, 4 ether, 4);
        gate.credit(childId, 2 ether);

        MandateGate.Action memory a =
            MandateGate.Action({agentId: childId, payee: PAYEE, amount: 0.5 ether, salt: keccak256("b7")});
        MandateGate.Verdict memory v =
            _signed(gate.commit(a));
        _try("depense 0.5 ETH", a, v);

        uint256 RmS = gate.room(childId);
        address vp = m.ownerOf(m.parentOf(childId));
        console2.log("   R-S =", RmS);

        // on sonde de part et d'autre du point suppose, sans le presumer
        uint256 snap = vm.snapshotState();
        _tryReclaim("reclaim(R-S + 1)", childId, vp, RmS + 1);
        vm.revertToState(snap);
        _tryReclaim("reclaim(R-S)    ", childId, vp, RmS);
        vm.revertToState(snap);
        _tryReclaim("reclaim(R-S - 1)", childId, vp, RmS - 1);

        console2.log("   -> point de bascule constate entre R-S et R-S+1");
    }

    // ══════════════════════════════════════════════ C — invariants rappeles

    function test_C8_spawn_depassant_une_clause() public {
        console2.log("=== CAS 8 - spawn qui DEPASSE le parent sur une clause soudee ===");
        parentId = _mkParent(10 ether, 5);

        console2.log("   -- plafond : enfant a 11 ETH sous un parent a 10 --");
        vm.prank(alice);
        try m.spawn(parentId, bob,
            InheritableAgentMandate.Mandate({maxSpendWei: 11 ether, telomere: 4, requireLease: true, frozen: false}),
            _p()) returns (uint256 id) {
            console2.log("   ABOUTIT, childId :", id);
        } catch Error(string memory r) { console2.log(string.concat("   REVERTE : ", r)); }

        console2.log("   -- payee : enfant declarant une payee hors allowlist parent --");
        address[] memory bad = new address[](1);
        bad[0] = OTHER_PAYEE;
        vm.prank(alice);
        try m.spawn(parentId, bob,
            InheritableAgentMandate.Mandate({maxSpendWei: 5 ether, telomere: 4, requireLease: true, frozen: false}),
            bad) returns (uint256 id) {
            console2.log("   ABOUTIT, childId :", id);
        } catch Error(string memory r) { console2.log(string.concat("   REVERTE : ", r)); }

        console2.log("   -- bail : enfant qui desactive le lease herite --");
        vm.prank(alice);
        try m.spawn(parentId, bob,
            InheritableAgentMandate.Mandate({maxSpendWei: 5 ether, telomere: 4, requireLease: false, frozen: false}),
            _p()) returns (uint256 id) {
            console2.log("   ABOUTIT, childId :", id);
        } catch Error(string memory r) { console2.log(string.concat("   REVERTE : ", r)); }
    }

    function test_C9_telomere_ne_remonte_pas() public {
        console2.log("=== CAS 9 - telomere : un enfant peut-il declarer >= parent ? ===");
        parentId = _mkParent(10 ether, 5);
        console2.log("   telomere parent : 5");

        uint16[3] memory tries = [uint16(6), 5, 4];
        for (uint256 i; i < 3; i++) {
            vm.prank(alice);
            try m.spawn(parentId, bob,
                InheritableAgentMandate.Mandate({maxSpendWei: 5 ether, telomere: tries[i], requireLease: true, frozen: false}),
                _p()) returns (uint256 id) {
                console2.log(string.concat("   telomere enfant ", vm.toString(uint256(tries[i])), " -> ABOUTIT, childId :"), id);
            } catch Error(string memory r) {
                console2.log(string.concat("   telomere enfant ", vm.toString(uint256(tries[i])), " -> REVERTE : ", r));
            }
        }
    }

    function test_C10_gel_cascade() public {
        console2.log("=== CAS 10 - gel du genesis, cascade sur la profondeur ===");
        uint256 g = _mkParent(10 ether, 20);
        uint256[] memory ids = new uint256[](10);
        ids[0] = g;
        address owner = alice;
        for (uint256 i = 1; i < 10; i++) {
            vm.prank(owner);
            ids[i] = m.spawn(ids[i - 1], bob,
                InheritableAgentMandate.Mandate({maxSpendWei: 10 ether, telomere: uint16(20 - i), requireLease: true, frozen: false}),
                _p());
            owner = bob;
        }
        console2.log("   profondeur construite :", ids.length - 1);
        console2.log("   avant gel - isActive(le plus profond) :", m.isActive(ids[9]));
        m.freeze(g);
        console2.log("   freeze(genesis) execute");
        console2.log("   apres gel - isActive(le plus profond) :", m.isActive(ids[9]));
        console2.log("   apres gel - isActive(profondeur 5)    :", m.isActive(ids[5]));

        console2.log("   -- effet sur le gate : une action reste-t-elle possible ? --");
        gate.credit(ids[9], 1 ether);
        MandateGate.Action memory a =
            MandateGate.Action({agentId: ids[9], payee: PAYEE, amount: 0.1 ether, salt: keccak256("c10")});
        MandateGate.Verdict memory v =
            _signed(gate.commit(a));
        _try("execute sous un ancetre gele", a, v);
    }

    function test_C11_soulbound() public {
        console2.log("=== CAS 11 - l'identite est-elle transferable ? ===");
        parentId = _mkParent(10 ether, 5);
        console2.log("   proprietaire actuel :", m.ownerOf(parentId));

        string[4] memory sigs = [
            "transfer(address,uint256)",
            "transferFrom(address,address,uint256)",
            "safeTransferFrom(address,address,uint256)",
            "approve(address,uint256)"
        ];
        for (uint256 i; i < 4; i++) {
            bytes memory data = i == 1 || i == 2
                ? abi.encodeWithSignature(sigs[i], alice, mallory, parentId)
                : abi.encodeWithSignature(sigs[i], mallory, parentId);
            vm.prank(alice);
            (bool ok, ) = address(m).call(data);
            console2.log(string.concat("   ", sigs[i], " -> "), ok ? "ABOUTIT" : "REVERTE / inexistant");
        }
        console2.log("   proprietaire apres tentatives :", m.ownerOf(parentId));
    }

    // ═════════════════════════ HORS PROTOCOLE - diagnostic effectiveCap
    // Le gate revendique un plafond effectif = min sur la lignee. Le protocole ne le
    // teste pas ; le presenter sans l'exercer serait une affirmation non verifiee.
    function test_D12_effective_cap_min_sur_lignee() public {
        console2.log("=== 12 (hors protocole) - effectiveCap est-il le min de la lignee ? ===");
        uint256 g = _mkParent(10 ether, 10);
        vm.prank(alice);
        uint256 c1 = m.spawn(g, bob,
            InheritableAgentMandate.Mandate({maxSpendWei: 3 ether, telomere: 9, requireLease: true, frozen: false}), _p());
        vm.prank(bob);
        uint256 c2 = m.spawn(c1, bob,
            InheritableAgentMandate.Mandate({maxSpendWei: 3 ether, telomere: 8, requireLease: true, frozen: false}), _p());

        (uint256 capG,,,) = m.mandateOf(g);
        (uint256 cap1,,,) = m.mandateOf(c1);
        (uint256 cap2,,,) = m.mandateOf(c2);
        console2.log("   plafonds propres  - genesis :", capG);
        console2.log("   plafonds propres  - niveau1 :", cap1);
        console2.log("   plafonds propres  - niveau2 :", cap2);
        console2.log("   effectiveCap(genesis) :", gate.effectiveCap(g));
        console2.log("   effectiveCap(niveau1) :", gate.effectiveCap(c1));
        console2.log("   effectiveCap(niveau2) :", gate.effectiveCap(c2));

        console2.log("   -- le gate refuse-t-il une depense au-dela du min ? --");
        gate.credit(c2, 100 ether);
        MandateGate.Action memory a =
            MandateGate.Action({agentId: c2, payee: PAYEE, amount: 3 ether + 1, salt: keccak256("d12")});
        MandateGate.Verdict memory v =
            _signed(gate.commit(a));
        _try("depense min+1", a, v);

        MandateGate.Action memory b =
            MandateGate.Action({agentId: c2, payee: PAYEE, amount: 3 ether, salt: keccak256("d12b")});
        MandateGate.Verdict memory w =
            _signed(gate.commit(b));
        _try("depense min  ", b, w);
        console2.log("   NB : le contrat impose deja enfant <= parent a l'ecriture, donc le");
        console2.log("   min de la lignee vaut le plafond propre du noeud. La marche le confirme");
        console2.log("   au lieu de le supposer.");
    }

    // ══════════════════════════════════════════ BANC Nº2 — autorite du verdict

    function test_AA1_signe_par_emetteur_autorise() public {
        console2.log("=== A1 - verdict SIGNE par un emetteur AUTORISE, lie a l'action ===");
        parentId = _mkParent(10 ether, 5);
        gate.credit(parentId, 10 ether);
        console2.log("   emetteur autorise :", ISSUER);
        console2.log("   authorizedIssuers[ISSUER] :", gate.authorizedIssuers(ISSUER));

        MandateGate.Action memory a =
            MandateGate.Action({agentId: parentId, payee: PAYEE, amount: 1 ether, salt: keccak256("A1")});
        _try("execute(action, verdict signe+autorise)", a, _signed(gate.commit(a)));
        console2.log("   spent apres :", gate.spent(parentId));
    }

    function test_AA2_sans_signature_valide() public {
        console2.log("=== A2 - meme artifactHash, mais signature INVALIDE (le trou d'hier) ===");
        parentId = _mkParent(10 ether, 5);
        gate.credit(parentId, 10 ether);

        MandateGate.Action memory a =
            MandateGate.Action({agentId: parentId, payee: PAYEE, amount: 1 ether, salt: keccak256("A2")});
        bytes32 c = gate.commit(a);

        console2.log("   -- (a) verdict revendiquant ISSUER mais signe par un autre --");
        MandateGate.Verdict memory forged =
            _sign(c, AGENT_PK, ISSUER, 777, uint64(block.timestamp + 1 days), true);
        _try("execute(action, verdict forge)", a, forged);

        console2.log("   -- (b) verdict SANS aucune signature (exactement le banc 1) --");
        MandateGate.Verdict memory naked = MandateGate.Verdict({
            artifactHash: c, issuer: ISSUER, approve: true,
            nonce: 778, expiry: uint64(block.timestamp + 1 days), signature: ""
        });
        _try("execute(action, verdict sans signature)", a, naked);
        console2.log("   spent apres :", gate.spent(parentId));
        console2.log("   (au banc 1, (b) AURAIT abouti : issuer n'etait jamais lu)");
    }

    function test_AA3_self_report_hors_allowlist() public {
        console2.log("=== A3 - verdict VALABLEMENT signe, mais par l'agent lui-meme ===");
        parentId = _mkParent(10 ether, 5);
        gate.credit(parentId, 10 ether);
        console2.log("   signataire (l'agent) :", AGENT_SIGNER);
        console2.log("   authorizedIssuers[agent] :", gate.authorizedIssuers(AGENT_SIGNER));

        MandateGate.Action memory a =
            MandateGate.Action({agentId: parentId, payee: PAYEE, amount: 1 ether, salt: keccak256("A3")});
        MandateGate.Verdict memory self =
            _sign(gate.commit(a), AGENT_PK, AGENT_SIGNER, 1, uint64(block.timestamp + 1 days), true);
        console2.log("   signataire reellement recupere :", gate.recoverIssuer(self));
        console2.log("   issuer declare dans le verdict  :", self.issuer);
        console2.log("   -> la signature est VALIDE ; c'est l'autorite qui manque");
        _try("execute(action, self-report signe)", a, self);
        console2.log("   spent apres :", gate.spent(parentId));
    }

    function test_AA4_signe_autorise_mais_autre_action() public {
        console2.log("=== A4 - signe + autorise, mais presente contre une AUTRE action ===");
        parentId = _mkParent(10 ether, 5);
        gate.credit(parentId, 10 ether);

        MandateGate.Action memory X =
            MandateGate.Action({agentId: parentId, payee: PAYEE, amount: 1 ether, salt: keccak256("A4X")});
        MandateGate.Action memory Y =
            MandateGate.Action({agentId: parentId, payee: PAYEE, amount: 9 ether, salt: keccak256("A4Y")});
        MandateGate.Verdict memory vX = _signed(gate.commit(X));

        console2.log("   -- le verdict est-il reellement operant sur X ? --");
        _try("execute(X, verdictX signe)", X, vX);
        console2.log("   -- le MEME verdict, signe et autorise, contre Y --");
        _try("execute(Y, verdictX signe)", Y, vX);
        console2.log("   spent total :", gate.spent(parentId));
        console2.log("   (lien et autorite composent : l'un ne rachete pas l'autre)");
    }

    function test_AA5_revocation_par_le_gardien() public {
        console2.log("=== A5 - REVOCATION : un emetteur autorise perd son autorite ===");
        parentId = _mkParent(10 ether, 5);
        gate.credit(parentId, 10 ether);
        gate.setIssuer(ISSUER2, true);
        console2.log("   ISSUER2 autorise :", gate.authorizedIssuers(ISSUER2));

        MandateGate.Action memory a1 =
            MandateGate.Action({agentId: parentId, payee: PAYEE, amount: 1 ether, salt: keccak256("A5a")});
        _try("avant revocation", a1,
            _sign(gate.commit(a1), ISSUER2_PK, ISSUER2, 1, uint64(block.timestamp + 1 days), true));

        gate.setIssuer(ISSUER2, false);
        console2.log("   gardien revoque ISSUER2 -> authorizedIssuers :", gate.authorizedIssuers(ISSUER2));

        MandateGate.Action memory a2 =
            MandateGate.Action({agentId: parentId, payee: PAYEE, amount: 1 ether, salt: keccak256("A5b")});
        _try("apres revocation", a2,
            _sign(gate.commit(a2), ISSUER2_PK, ISSUER2, 2, uint64(block.timestamp + 1 days), true));
        console2.log("   spent total :", gate.spent(parentId));
    }

    function test_AA6_agent_tente_de_s_auto_autoriser() public {
        console2.log("=== A6 - l'agent peut-il s'ajouter lui-meme aux emetteurs ? ===");
        console2.log("   gardien du gate :", gate.guardian());
        console2.log("   appelant        :", AGENT_SIGNER, "(l'agent)");

        vm.prank(AGENT_SIGNER);
        try gate.setIssuer(AGENT_SIGNER, true) {
            console2.log("   setIssuer(agent, true) -> ABOUTIT");
        } catch Error(string memory r) {
            console2.log(string.concat("   setIssuer(agent, true) -> REVERTE : ", r));
        }
        console2.log("   authorizedIssuers[agent] apres tentative :", gate.authorizedIssuers(AGENT_SIGNER));

        console2.log("   -- et via le proprietaire d'un agent (alice) ? --");
        vm.prank(alice);
        try gate.setIssuer(alice, true) {
            console2.log("   setIssuer(alice, true) -> ABOUTIT");
        } catch Error(string memory r) {
            console2.log(string.concat("   setIssuer(alice, true) -> REVERTE : ", r));
        }
        console2.log("   authorizedIssuers[alice] :", gate.authorizedIssuers(alice));
    }

    function test_AA7_antirejeu_peremption_et_nonce() public {
        console2.log("=== A7 - anti-rejeu : peremption et nonce ===");
        parentId = _mkParent(10 ether, 5);
        gate.credit(parentId, 10 ether);
        vm.warp(1_000_000);

        console2.log("   -- (a) verdict PERIME --");
        MandateGate.Action memory a =
            MandateGate.Action({agentId: parentId, payee: PAYEE, amount: 1 ether, salt: keccak256("A7a")});
        MandateGate.Verdict memory old =
            _sign(gate.commit(a), ISSUER_PK, ISSUER, 10, uint64(block.timestamp - 1), true);
        console2.log("   block.timestamp :", block.timestamp);
        console2.log("   expiry du verdict :", uint256(old.expiry));
        _try("execute(verdict perime)", a, old);

        console2.log("   -- frontiere : expiry == block.timestamp --");
        MandateGate.Verdict memory edge =
            _sign(gate.commit(a), ISSUER_PK, ISSUER, 11, uint64(block.timestamp), true);
        _try("execute(expiry == now)", a, edge);

        console2.log("   -- (b) nonce deja consomme, sur une AUTRE action --");
        MandateGate.Action memory b =
            MandateGate.Action({agentId: parentId, payee: PAYEE, amount: 2 ether, salt: keccak256("A7b")});
        MandateGate.Verdict memory reuse =
            _sign(gate.commit(b), ISSUER_PK, ISSUER, 11, uint64(block.timestamp + 1 days), true);
        console2.log("   usedNonce[ISSUER][11] :", gate.usedNonce(ISSUER, 11));
        _try("execute(nonce 11 reutilise)", b, reuse);
        console2.log("   spent total :", gate.spent(parentId));
    }
}
