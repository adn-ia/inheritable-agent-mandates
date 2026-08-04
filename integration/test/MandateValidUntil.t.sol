// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {InheritableAgentMandateV2} from "adn/InheritableAgentMandateV2.sol";

/**
 * validUntil : la clause que le white paper liste et que l'implementation n'avait pas.
 *
 * Le point a etablir, PAS a supposer : le check d'expiration peut-il etre LOCAL ?
 * L'argument est que spawn impose enfant <= parent, donc par transitivite un noeud
 * expire toujours avant ou en meme temps que chacun de ses ancetres. Si c'est vrai,
 * lire le seul noeud suffit. Si c'est faux, il existe un instant ou un ancetre est
 * expire et le noeud se lit encore actif.
 *
 * Ce test ne l'affirme pas : il construit un oracle qui MARCHE la lignee entiere, et
 * compare le rendu du contrat a l'oracle sur un balayage de timestamps. Toute
 * divergence est imprimee. Aucune valeur attendue n'est ecrite en dur.
 */
contract MandateValidUntilTest is Test {
    InheritableAgentMandateV2 m;

    address agent = makeAddr("agent");
    address constant PAYEE = address(0xdEaD);
    uint256 constant CAP = 100 ether;

    function setUp() public {
        m = new InheritableAgentMandateV2(address(this)); // le test est gardien
        vm.warp(1_000_000); // base de temps stable, sinon block.timestamp = 1
    }

    function _payees() internal pure returns (address[] memory p) {
        p = new address[](1);
        p[0] = PAYEE;
    }

    function _mint(uint16 tel, uint64 vu) internal returns (uint256) {
        return m.mint(
            agent,
            InheritableAgentMandateV2.Mandate({
                maxSpendWei: CAP, validUntil: vu, telomere: tel, requireLease: true, frozen: false
            }),
            _payees()
        );
    }

    function _spawn(uint256 parent, uint16 tel, uint64 vu) internal returns (uint256) {
        return m.spawn(
            parent,
            agent,
            InheritableAgentMandateV2.Mandate({
                maxSpendWei: CAP, validUntil: vu, telomere: tel, requireLease: true, frozen: false
            }),
            _payees()
        );
    }

    /// Oracle independant : marche TOUTE la lignee, gel ET expiration.
    function _walkOracle(uint256 id) internal view returns (bool) {
        uint256 cur = id;
        while (cur != 0) {
            (, uint64 vu,,, bool frozen) = m.mandateOf(cur);
            if (frozen) return false;
            if (vu != 0 && block.timestamp > vu) return false;
            cur = m.parentOf(cur);
        }
        return true;
    }

    // ================================================================ 1
    function test_1_spawn_expiration_posterieure_au_parent() public {
        console2.log("=== 1 - un enfant peut-il viser une expiration plus tardive ? ===");
        uint256 p = _mint(5, uint64(block.timestamp + 1000));
        console2.log("   parent validUntil = now + 1000");

        console2.log("   -- enfant a now + 1001 (plus tard d'une seconde) --");
        vm.expectRevert(bytes("validUntil cannot exceed parent"));
        _spawn(p, 4, uint64(block.timestamp + 1001));
        console2.log("   reverte");

        console2.log("   -- enfant a 0 (= illimite, retrait de l'expiration heritee) --");
        vm.expectRevert(bytes("validUntil cannot exceed parent"));
        _spawn(p, 4, 0);
        console2.log("   reverte");

        console2.log("   -- enfant a now + 999 (resserrement) --");
        uint256 c = _spawn(p, 4, uint64(block.timestamp + 999));
        (, uint64 vuc,,,) = m.mandateOf(c);
        console2.log("   aboutit, validUntil enfant rendu :", uint256(vuc));

        console2.log("   -- enfant a l'identique (now + 1000) --");
        uint256 c2 = _spawn(p, 4, uint64(block.timestamp + 1000));
        console2.log("   aboutit, agentId :", c2);
    }

    // ================================================================ 2
    function test_2_parent_illimite_enfant_borne() public {
        console2.log("=== 2 - parent SANS expiration (0), enfant qui s'en donne une ===");
        uint256 p = _mint(5, 0);
        uint256 c = _spawn(p, 4, uint64(block.timestamp + 100));
        console2.log("   spawn aboutit (resserrement depuis l'illimite), agentId :", c);
        console2.log("   avant echeance - isActive(parent) :", m.isActive(p));
        console2.log("   avant echeance - isActive(enfant) :", m.isActive(c));

        vm.warp(block.timestamp + 101);
        console2.log("   apres warp de +101 s");
        console2.log("   isActive(parent) rendu :", m.isActive(p));
        console2.log("   isActive(enfant) rendu :", m.isActive(c));
        console2.log("   (parent non gele et non expire ; l'enfant est juge sur son propre champ)");
    }

    // ================================================================ 3
    function test_3_localite_vs_oracle_de_marche() public {
        console2.log("=== 3 - LE POINT : le check local rend-il la meme chose qu'une marche ? ===");
        // lignee de 8, expirations strictement decroissantes (donc legales)
        uint64 base = uint64(block.timestamp);
        uint256[] memory ids = new uint256[](8);
        ids[0] = _mint(50, base + 800);
        for (uint256 i = 1; i < 8; i++) {
            ids[i] = _spawn(ids[i - 1], uint16(50 - i), base + uint64(800 - i * 100));
        }
        console2.log("   lignee de 8 ; expirations base+800 (genesis) .. base+100 (feuille)");

        uint256 divergences;
        console2.log("   t (offset) | profondeur | isActive | oracle-marche");
        for (uint256 t = 0; t <= 900; t += 50) {
            vm.warp(base + t);
            for (uint256 d = 0; d < 8; d++) {
                bool local = m.isActive(ids[d]);
                bool walked = _walkOracle(ids[d]);
                if (local != walked) {
                    divergences++;
                    console2.log(
                        string.concat(
                            "   DIVERGENCE t=+", vm.toString(t), " prof=", vm.toString(d),
                            " local=", local ? "true" : "false",
                            " marche=", walked ? "true" : "false"
                        )
                    );
                }
            }
        }
        console2.log("   points de comparaison : 19 timestamps x 8 profondeurs = 152");
        console2.log("   divergences constatees :", divergences);
        console2.log("   (0 divergence = le check local suffit SUR CE JEU ; ce n'est pas une preuve generale)");
    }

    // ================================================================ 3bis
    function testFuzz_3bis_localite(uint16 t0, uint16 t1, uint16 t2, uint32 when) public {
        // le fuzz cherche activement un contre-exemple a la localite
        uint64 base = uint64(block.timestamp);
        uint64 v0 = base + uint64(t0) + 1;
        uint64 v1 = v0 - uint64(bound(t1, 0, t0)); // <= v0
        uint64 v2 = v1 - uint64(bound(t2, 0, v1 - base - 1)); // <= v1

        uint256 a = _mint(50, v0);
        uint256 b = _spawn(a, 49, v1);
        uint256 c = _spawn(b, 48, v2);

        vm.warp(base + bound(when, 0, uint32(type(uint16).max) * 2));
        assertEq(m.isActive(a), _walkOracle(a), "divergence local/marche au genesis");
        assertEq(m.isActive(b), _walkOracle(b), "divergence local/marche au milieu");
        assertEq(m.isActive(c), _walkOracle(c), "divergence local/marche a la feuille");
    }

    // ================================================================ 4
    function test_4_ancetre_expire_noeud_vivant() public {
        console2.log("=== 4 - peut-on obtenir un ancetre expire ET un noeud encore actif ? ===");
        console2.log("   ce serait le seul cas ou le check local sur-permettrait.");
        console2.log("   il exige feuille.validUntil > ancetre.validUntil :");

        uint256 p = _mint(5, uint64(block.timestamp + 100));
        uint256 c = _spawn(p, 4, uint64(block.timestamp + 100));

        console2.log("   tentative de spawn d'un petit-enfant a +200 (au-dela du grand-parent) :");
        vm.expectRevert(bytes("validUntil cannot exceed parent"));
        _spawn(c, 3, uint64(block.timestamp + 200));
        console2.log("   reverte -> la configuration n'est pas constructible");

        vm.warp(block.timestamp + 150);
        console2.log("   apres echeance des deux :");
        console2.log("   isActive(ancetre) :", m.isActive(p));
        console2.log("   isActive(enfant)  :", m.isActive(c));
    }

    // ================================================================ 5
    function test_5_monotonie_aucune_fonction_ne_repousse() public {
        console2.log("=== 5 - une fonction du contrat repousse-t-elle un validUntil existant ? ===");
        uint64 v = uint64(block.timestamp + 500);
        uint256 p = _mint(5, v);
        (, uint64 avant,,,) = m.mandateOf(p);
        console2.log("   validUntil au mint :", uint256(avant));

        // on exerce TOUT ce que le contrat expose : spawn (x2), freeze
        _spawn(p, 4, v);
        _spawn(p, 4, uint64(block.timestamp + 10));
        m.freeze(p);
        console2.log("   exerce : spawn x2, freeze");

        (, uint64 apres,,,) = m.mandateOf(p);
        console2.log("   validUntil apres :", uint256(apres));
        assertEq(apres, avant, "le validUntil d'un noeud existant a bouge");
        console2.log("   surface d'ecriture lue dans la source : mint, spawn (nouveaux ids),");
        console2.log("   freeze (touche .frozen seul). Aucun setter de validUntil.");
    }

    // ================================================================ 6
    function test_6_non_strippable_identite() public {
        console2.log("=== 6 - changer validUntil, est-ce changer d'identite ? ===");
        uint256 a = _mint(5, uint64(block.timestamp + 100));
        uint256 b = _mint(5, uint64(block.timestamp + 200));
        console2.log("   deux mints identiques sauf validUntil -> agentIds :", a, b);
        console2.log("   cote Solidity l'identite est un agentId sequentiel : un mandat");
        console2.log("   different est un AUTRE agent, l'ancien reste tel quel.");
        (, uint64 va,,,) = m.mandateOf(a);
        console2.log("   validUntil de l'agent", a, "toujours :", uint256(va));
        console2.log("   NB : le soudage par hachage (geneId) est cote TypeScript,");
        console2.log("   src/genome.ts -> tests/invariants.ts.");
    }

    // ================================================================ 7
    function test_7_le_gel_garde_sa_marche() public {
        console2.log("=== 7 - regression : le gel cascade toujours (marche non bornee) ===");
        uint256[] memory ids = new uint256[](20);
        ids[0] = _mint(50, 0);
        for (uint256 i = 1; i < 20; i++) ids[i] = _spawn(ids[i - 1], uint16(50 - i), 0);

        console2.log("   avant gel - isActive(prof. 19) :", m.isActive(ids[19]));
        m.freeze(ids[0]);
        console2.log("   freeze(genesis)");
        console2.log("   apres gel - isActive(prof. 19) :", m.isActive(ids[19]));

        uint256 g0 = gasleft();
        m.isActive(ids[19]);
        console2.log("   gaz isActive a prof. 19 :", g0 - gasleft());
        uint256 g1 = gasleft();
        m.isActive(ids[1]);
        console2.log("   gaz isActive a prof.  1 :", g1 - gasleft());
    }

    // ================================================================ 8
    function test_8_mandate_root_inclut_validUntil() public {
        console2.log("=== 8 - le hash d'identite couvre-t-il validUntil ? ===");
        console2.log("   (en v1 le hash de couture omettait la clause : c'est ce qu'on ferme ici)");

        uint256 a = _mint(5, uint64(block.timestamp + 100));
        uint256 b = _mint(5, uint64(block.timestamp + 200));
        console2.log("   deux mandats identiques SAUF validUntil (+100 vs +200)");
        console2.logBytes32(m.mandateRoot(a));
        console2.logBytes32(m.mandateRoot(b));
        assertTrue(m.mandateRoot(a) != m.mandateRoot(b), "meme racine malgre deux echeances");
        console2.log("   racines differentes -> l'echeance ne peut pas etre retiree du hash");

        console2.log("   -- controle : deux mandats en tous points identiques --");
        uint256 c = _mint(5, uint64(block.timestamp + 100));
        console2.logBytes32(m.mandateRoot(c));
        console2.log("   (agentId different -> racine differente, l'id entre dans le hash)");
        assertTrue(m.mandateRoot(a) != m.mandateRoot(c), "l'agentId n'entre pas dans le hash");

        console2.log("   -- la racine bouge-t-elle quand une clause change vraiment ? --");
        bytes32 avant = m.mandateRoot(a);
        m.freeze(a);
        console2.log("   apres freeze(a) :");
        console2.logBytes32(m.mandateRoot(a));
        assertTrue(avant != m.mandateRoot(a), "le gel ne change pas la racine");
    }

    // ================================================================ 9
    function testFuzz_9_root_injectif_sur_validUntil(uint64 v1, uint64 v2) public {
        // deux echeances distinctes ne doivent jamais donner la meme racine
        vm.assume(v1 != v2);
        uint256 a = _mint(5, v1);
        uint256 b = _mint(5, v2);
        // les ids different, donc on compare a id egal en recalculant a la main
        bytes32 ra = keccak256(abi.encode(address(m), a, CAP, v1, uint16(5), true, false));
        bytes32 rb = keccak256(abi.encode(address(m), a, CAP, v2, uint16(5), true, false));
        assertEq(m.mandateRoot(a), ra, "mandateRoot ne suit pas la formule annoncee");
        assertTrue(ra != rb, "collision de racine sur deux echeances distinctes");
        b; // silence
    }
}
