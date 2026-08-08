// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title MandateGateV2 — MandateGate + une seconde porte d'entrée, schnorr/NIP-01
 * @notice Le mandat (`InheritableAgentMandate`) dit ce qu'un agent A LE DROIT de faire.
 *         Ce gate est l'étage au-dessus : il décide si une action PRÉCISE peut passer,
 *         maintenant, au vu d'un verdict présenté. Il n'altère ni ne remplace le contrat
 *         de référence — il le lit.
 *
 *         Trois propriétés, chacune ajoutée pour combler un trou constaté :
 *
 *         A. LIEN action↔verdict. Une action est réduite UNE FOIS à
 *            `commit(action) = keccak256(...)`. Le verdict présenté doit porter sur
 *            exactement ces octets. Sans cela, un verdict légitimement émis pour l'action
 *            X serait rejouable contre l'action Y : deux contrôles parleraient de deux
 *            instances différentes.
 *
 *         B. AUTORITÉ du verdict. Le lien seul ne suffit pas : dans une première version,
 *            le champ `issuer` n'était jamais lu, si bien que n'importe qui fabriquait un
 *            verdict acceptable en posant `artifactHash = commit(action)`. Il faut donc
 *            aussi (1) une signature EIP-191 valide de `issuer`, sur un digest couvrant
 *            l'adresse du gate et le `chainid` — séparation de domaine, pas de rejeu
 *            cross-gate ni cross-chain — et (2) `issuer` inscrit dans `authorizedIssuers`,
 *            registre réglable PAR LE GARDIEN SEUL. L'acteur ne peut pas s'auto-autoriser :
 *            c'est un médiateur indépendant, par opposition à un auto-signalement.
 *            Politique retenue : version forte, un verdict auto-signé par l'agent est
 *            refusé. Variante non implémentée : l'accepter en l'étiquetant par une classe
 *            de source.
 *
 *         C. RECLAMATION. Le retour d'un reliquat au parent n'est pas une non-action : il
 *            doit satisfaire `rendu <= reçu − dépensé` ET aller au parent RÉEL de la
 *            lignée, lu dans le contrat de mandat et non fourni par l'appelant. Ce n'est
 *            pas un jugement sur la qualité de l'action, c'est une conservation.
 *
 *         AJOUT DE LA V2 — porte additive. Le chemin ECDSA/EIP-191 (`execute`) est
 *         repris **à l'identique** : mêmes contrôles, même ordre, même coût. On ajoute
 *         `executeSchnorr`, qui accepte un verdict au format d'un tiers — événement
 *         Nostr NIP-01 signé en schnorr BIP-340, tel qu'émis par un serveur de
 *         politique externe. Aucun chemin existant n'est modifié : un déploiement de
 *         la V1 et un de la V2 se comportent identiquement sur `execute`.
 *
 *         La séparation de domaine du côté schnorr ne vient pas du digest — le format
 *         du tiers ne la prévoit pas — mais du CONTENU signé : l'événement doit porter
 *         `intended_verifier = eip155:<chainid>:<adresse de ce gate>`. Le gate
 *         RECONSTRUIT cette chaîne lui-même à partir de `block.chainid` et de
 *         `address(this)` ; elle n'est jamais fournie par l'appelant. Un verdict émis
 *         pour un autre gate, ou une autre chaîne, est donc rejeté.
 *
 *         Démonstrateur NON AUDITÉ, testnet uniquement. Aucun ETH ne transite : la
 *         comptabilité est en unités internes créditées par le gardien, et le contrat NE
 *         DÉTIENT AUCUN FONDS par construction. L'interopérabilité avec un émetteur tiers
 *         n'est pas incluse : le digest est de l'EIP-191, pas de l'EIP-712 typé.
 */
/**
 * Verification schnorr BIP-340 sur EVM, sans boucle de multiplication scalaire.
 *
 * L'idee : `ecrecover` calcule Q = r^-1 * (s'*R' - h*G), ou R' est le point
 * d'abscisse r et de parite donnee par v. En choisissant
 *     r  = px            (l'abscisse de la cle publique, donc R' = P)
 *     h  = n - s*px      (mod n)
 *     s' = (n - e)*px    (mod n)
 * on obtient Q = px^-1 * ( -e*px*P + s*px*G ) = s*G - e*P = R.
 *
 * `ecrecover` ne rend qu'une ADRESSE (keccak des coordonnees, tronque). On la
 * compare donc a l'adresse du point lift_x(r_sig), qui par construction a une
 * ordonnee PAIRE. Egalite des adresses => R == lift_x(r_sig), c'est-a-dire
 * R.x == r_sig ET R.y pair : les deux conditions exigees par BIP-340.
 *
 * Racine carree modulaire via le precompile modexp (0x05) ; hash etiquete via
 * le precompile sha256 (0x02). Aucune arithmetique de courbe en Solidity.
 *
 * NON AUDITE. Ecrit pour un banc de conformite, valide contre les vecteurs
 * officiels BIP-340 avant tout autre usage.
 */
library SchnorrBIP340 {
    uint256 internal constant P = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEFFFFFC2F;
    uint256 internal constant N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
    /// sha256("BIP0340/challenge")
    bytes32 internal constant TAG = 0x7bb52d7a9fef58323eb1bf7a407db382d2f3f2d81bb1224f49fe518f6d48d37c;

    /// Racine carree mod P via le precompile modexp : a^((P+1)/4).
    function _sqrt(uint256 a) private view returns (uint256 r) {
        uint256 e = (P + 1) / 4;
        assembly {
            let m := mload(0x40)
            mstore(m, 0x20) mstore(add(m, 0x20), 0x20) mstore(add(m, 0x40), 0x20)
            mstore(add(m, 0x60), a) mstore(add(m, 0x80), e) mstore(add(m, 0xa0), P)
            if iszero(staticcall(gas(), 0x05, m, 0xc0, m, 0x20)) { revert(0, 0) }
            r := mload(m)
        }
    }

    /// Le point d'abscisse x et d'ordonnee PAIRE. ok=false si x n'est pas sur la courbe.
    function _liftX(uint256 x) private view returns (uint256 y, bool ok) {
        if (x >= P) return (0, false);
        uint256 c = addmod(mulmod(mulmod(x, x, P), x, P), 7, P); // x^3 + 7
        y = _sqrt(c);
        if (mulmod(y, y, P) != c) return (0, false);
        if (y & 1 == 1) y = P - y;
        ok = true;
    }

    function _addr(uint256 x, uint256 y) private pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(x, y)))));
    }

    /// Confort : message de 32 octets (le cas d'usage NIP-01, ou l'id fait 32 octets).
    function verify(bytes32 m32, uint256 px, uint256 rx, uint256 sig) internal view returns (bool) {
        return verify(abi.encodePacked(m32), px, rx, sig);
    }

    /**
     * @param m   le message, BRUT et de longueur quelconque (pas re-hache)
     * @param px  la cle publique x-only
     * @param rx  les 32 premiers octets de la signature
     * @param sig les 32 derniers octets de la signature
     */
    function verify(bytes memory m, uint256 px, uint256 rx, uint256 sig) internal view returns (bool) {
        if (rx >= P || sig >= N || px >= P) return false;

        // `ecrecover` exige r dans [1, N-1] : une cle publique dont l'abscisse
        // tombe dans [N, P) ne peut pas passer par cette astuce. L'intervalle a une
        // largeur d'environ 2^-128 de la courbe ; le cas est rejete, pas ignore.
        if (px == 0 || px >= N) return false;

        // le point public doit etre sur la courbe (ordonnee paire, cle x-only)
        (, bool okP) = _liftX(px);
        if (!okP) return false;

        // R attendu : lift_x(rx), ordonnee paire par construction
        (uint256 ry, bool okR) = _liftX(rx);
        if (!okR) return false;

        // e = int(tagged_hash("BIP0340/challenge", rx || px || m)) mod n
        uint256 e = uint256(sha256(abi.encodePacked(TAG, TAG, bytes32(rx), bytes32(px), m))) % N;
        if (e == 0) return false;

        // Q = px^-1 * ( (n-e)*px * P  -  (n - s*px)*G ) = s*G - e*P
        uint256 h = N - mulmod(sig, px, N);
        uint256 sp = mulmod(N - e, px, N);
        // v = 27 car P a une ordonnee paire apres liftX
        address Q = ecrecover(bytes32(h), 27, bytes32(px), bytes32(sp));
        if (Q == address(0)) return false;

        return Q == _addr(rx, ry);
    }
}

interface IInheritableAgentMandate {
    function ownerOf(uint256 agentId) external view returns (address);
    function parentOf(uint256 agentId) external view returns (uint256);
    function mandateOf(uint256 agentId)
        external
        view
        returns (uint256 maxSpendWei, uint16 telomere, bool requireLease, bool frozen);
    function isActive(uint256 agentId) external view returns (bool);
    function payeeAllowed(uint256 agentId, address payee) external view returns (bool);
}

contract MandateGateV2 {
    IInheritableAgentMandate public immutable mandate;
    address public immutable guardian;

    // livre de comptes, par agentId
    mapping(uint256 => uint256) public received;
    mapping(uint256 => uint256) public spent;
    mapping(uint256 => uint256) public returnedTo;

    // anti-rejeu : un commitment ne s'exécute qu'une fois
    mapping(bytes32 => bool) public usedCommitment;

    /// Émetteurs reconnus. Réglé par le gardien SEUL, jamais par l'agent agissant.
    mapping(address => bool) public authorizedIssuers;
    /// Anti-rejeu par émetteur.
    mapping(address => mapping(uint256 => bool)) public usedNonce;

    struct Action {
        uint256 agentId;
        address payee;
        uint256 amount;
        bytes32 salt;
    }

    /// `artifactHash` désigne l'action canonique ; `signature` prouve que `issuer` l'a
    /// bien émis ; `nonce` et `expiry` bornent son rejeu.
    struct Verdict {
        bytes32 artifactHash;
        address issuer;
        bool approve;
        uint256 nonce;
        uint64 expiry;
        bytes signature;
    }

    event Executed(uint256 indexed agentId, bytes32 indexed commitment, address indexed issuer, uint256 amount);
    event Reclaimed(uint256 indexed childId, uint256 indexed parentId, uint256 amount);
    event IssuerSet(address indexed issuer, bool allowed);

    modifier onlyGuardian() {
        require(msg.sender == guardian, "only guardian");
        _;
    }

    constructor(IInheritableAgentMandate _mandate, address _guardian) {
        mandate = _mandate;
        guardian = _guardian;
    }

    /// Le registre d'émetteurs est hors du contrôle de l'acteur : gardien uniquement.
    function setIssuer(address issuer, bool allowed) external onlyGuardian {
        authorizedIssuers[issuer] = allowed;
        emit IssuerSet(issuer, allowed);
    }

    /// Crédite un agent (comptabilité interne, aucun ETH).
    function credit(uint256 agentId, uint256 amount) external onlyGuardian {
        require(mandate.ownerOf(agentId) != address(0), "no such agent");
        received[agentId] += amount;
    }

    /// L'action canonique, réduite à des octets. UNE seule définition, utilisée partout.
    function commit(Action calldata a) public pure returns (bytes32) {
        return keccak256(abi.encode(a.agentId, a.payee, a.amount, a.salt));
    }

    /// Digest EIP-191 signé par l'émetteur. Couvre le gate et la chaîne : un verdict émis
    /// pour un autre déploiement ou un autre réseau ne peut pas être rejoué ici.
    function verdictDigest(Verdict memory v) public view returns (bytes32) {
        bytes32 inner = keccak256(
            abi.encode(v.artifactHash, v.issuer, v.approve, v.nonce, v.expiry, address(this), block.chainid)
        );
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", inner));
    }

    function _recover(bytes32 digest, bytes memory sig) internal pure returns (address) {
        if (sig.length != 65) return address(0);
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
        if (v < 27) v += 27;
        return ecrecover(digest, v, r, s);
    }

    /// Diagnostic : qui a RÉELLEMENT signé ce verdict ? (lecture, pas un contrôle)
    function recoverIssuer(Verdict memory v) public view returns (address) {
        return _recover(verdictDigest(v), v.signature);
    }

    /// Plafond effectif = minimum des plafonds sur toute la lignée.
    function effectiveCap(uint256 id) public view returns (uint256 cap) {
        cap = type(uint256).max;
        uint256 cur = id;
        while (cur != 0) {
            (uint256 c,,,) = mandate.mandateOf(cur);
            if (c < cap) cap = c;
            cur = mandate.parentOf(cur);
        }
    }

    /// Reste disponible d'un agent : ce qu'il a reçu, moins dépensé, moins rendu.
    function room(uint256 agentId) public view returns (uint256) {
        return received[agentId] - spent[agentId] - returnedTo[agentId];
    }

    /**
     * Exécute une action si et seulement si le verdict porte sur CETTE action ET émane
     * d'un émetteur autorisé qui l'a réellement signé.
     *
     * L'ordre des contrôles est délibéré et testable :
     *   1. lien       — un verdict qui parle d'autre chose est écarté avant tout le reste ;
     *   2. péremption — un verdict périmé n'est pas examiné plus loin ;
     *   3. signature  — l'émetteur déclaré a-t-il réellement émis ce verdict ?
     *   4. autorité   — cet émetteur est-il reconnu par le gardien ?
     *   5. rejeu      — ce nonce a-t-il déjà servi ?
     * Signature AVANT autorité, pour qu'un verdict auto-signé correctement échoue bien sur
     * l'autorité et non sur la signature : c'est la distinction qui porte le dispositif.
     */
    function execute(Action calldata a, Verdict calldata v) external returns (bytes32 c) {
        c = commit(a);

        // --- A : un seul jeu d'octets, pour les deux contrôles ---
        require(v.artifactHash == c, "verdict not bound to this action");

        // --- B : autorité du verdict ---
        require(block.timestamp <= v.expiry, "verdict expired");
        require(
            _recover(verdictDigest(v), v.signature) == v.issuer && v.issuer != address(0),
            "verdict signature invalid"
        );
        require(authorizedIssuers[v.issuer], "issuer not authorized");
        require(!usedNonce[v.issuer][v.nonce], "verdict nonce already used");

        require(v.approve, "verdict does not approve");
        require(!usedCommitment[c], "commitment already used");

        // --- contrôles portés par le contrat de mandat ---
        require(mandate.isActive(a.agentId), "agent not active");
        require(mandate.payeeAllowed(a.agentId, a.payee), "payee not allowed");
        require(spent[a.agentId] + a.amount <= effectiveCap(a.agentId), "over effective cap");
        require(a.amount <= room(a.agentId), "insufficient room");

        usedNonce[v.issuer][v.nonce] = true;
        usedCommitment[c] = true;
        spent[a.agentId] += a.amount;
        emit Executed(a.agentId, c, v.issuer, a.amount);
    }

    /**
     * C. Reclamation d'un reliquat vers le parent. Deux conditions, aucune n'est un
     *    jugement de valeur : on ne rend pas plus que ce qui reste, et le destinataire est
     *    le propriétaire du parent réel, lu dans le contrat de mandat.
     */
    function reclaim(uint256 childId, address to, uint256 amount) external returns (uint256 parentId) {
        parentId = mandate.parentOf(childId);
        require(parentId != 0, "no parent in lineage");
        require(to == mandate.ownerOf(parentId), "not the real parent");
        require(amount <= room(childId), "over-return");

        returnedTo[childId] += amount;
        received[parentId] += amount;
        emit Reclaimed(childId, parentId, amount);
    }


    // ─────────────────────────────────────────────────────────────────────────
    //  PORTE ADDITIVE — verdict au format d'un tiers (Nostr NIP-01 + schnorr)
    // ─────────────────────────────────────────────────────────────────────────

    /// Émetteurs schnorr reconnus, par clé publique x-only. Gardien uniquement.
    mapping(uint256 => bool) public authorizedIssuerKeys;

    event IssuerKeySet(uint256 indexed issuerKey, bool allowed);

    /// Ce qu'un verdict tiers doit fournir. `preimage` est la sérialisation NIP-01
    /// exacte — `[0,pubkey,created_at,kind,tags,content]` — telle qu'elle a été signée.
    /// Les offsets évitent au contrat de fouiller la préimage : il vérifie que les
    /// champs sont bien là où on le dit. Un offset mensonger fait échouer la comparaison.
    struct SchnorrVerdict {
        bytes preimage;
        uint256 issuerKey;
        uint256 sigR;
        uint256 sigS;
        uint256 offArtifact;
        uint256 offVerifier;
    }

    function setIssuerKey(uint256 issuerKey, bool allowed) external onlyGuardian {
        authorizedIssuerKeys[issuerKey] = allowed;
        emit IssuerKeySet(issuerKey, allowed);
    }

    /// `eip155:<chainid>:0x<adresse de ce contrat, minuscules>` — reconstruit ici,
    /// jamais accepté de l'appelant.
    function expectedVerifierTag() public view returns (bytes memory) {
        return abi.encodePacked("eip155:", _dec(block.chainid), ":0x", _addrLower(address(this)));
    }

    function _dec(uint256 v) private pure returns (bytes memory) {
        if (v == 0) return "0";
        uint256 n = v; uint256 len;
        while (n != 0) { len++; n /= 10; }
        bytes memory b = new bytes(len);
        while (v != 0) { b[--len] = bytes1(uint8(48 + v % 10)); v /= 10; }
        return b;
    }

    function _addrLower(address a) private pure returns (bytes memory out) {
        bytes memory H = "0123456789abcdef";
        out = new bytes(40);
        uint160 x = uint160(a);
        for (uint256 i; i < 20; i++) {
            uint8 b = uint8(x >> (8 * (19 - i)));
            out[i * 2] = H[b >> 4];
            out[i * 2 + 1] = H[b & 0x0f];
        }
    }

    function _at(bytes memory hay, uint256 off, bytes memory exp) private pure returns (bool) {
        unchecked {
            if (exp.length > hay.length || off > hay.length - exp.length) return false;
            for (uint256 j; j < exp.length; j++) if (hay[off + j] != exp[j]) return false;
        }
        return true;
    }

    function _hex32(bytes32 v) private pure returns (bytes memory out) {
        bytes memory H = "0123456789abcdef";
        out = new bytes(64);
        for (uint256 i; i < 32; i++) {
            out[i * 2] = H[uint8(v[i]) >> 4];
            out[i * 2 + 1] = H[uint8(v[i]) & 0x0f];
        }
    }

    /**
     * Exécute une action sur présentation d'un verdict TIERS.
     *
     * Mêmes exigences de fond que `execute`, transposées au format de l'émetteur :
     *   1. lien       — la préimage doit porter `artifact_hash == commit(action)` ;
     *   2. domaine    — elle doit porter `intended_verifier` = CE gate, CETTE chaîne ;
     *   3. signature  — schnorr BIP-340 valide sur l'id NIP-01 recalculé ;
     *   4. autorité   — la clé de l'émetteur doit être inscrite par le gardien ;
     *   5. rejeu      — un commitment ne s'exécute qu'une fois.
     * Puis les contrôles du mandat, identiques au chemin ECDSA.
     */
    function executeSchnorr(Action calldata a, SchnorrVerdict calldata v)
        external
        returns (bytes32 c)
    {
        c = commit(a);

        SchnorrVerdict memory m = v;
        require(_at(m.preimage, m.offArtifact, _hex32(c)), "verdict not bound to this action");
        require(_at(m.preimage, m.offVerifier, expectedVerifierTag()), "verdict not for this gate");
        require(
            SchnorrBIP340.verify(sha256(m.preimage), m.issuerKey, m.sigR, m.sigS),
            "schnorr signature invalid"
        );
        require(authorizedIssuerKeys[m.issuerKey], "issuer key not authorized");
        require(!usedCommitment[c], "commitment already used");

        require(mandate.isActive(a.agentId), "agent not active");
        require(mandate.payeeAllowed(a.agentId, a.payee), "payee not allowed");
        require(spent[a.agentId] + a.amount <= effectiveCap(a.agentId), "over effective cap");
        require(a.amount <= room(a.agentId), "insufficient room");

        usedCommitment[c] = true;
        spent[a.agentId] += a.amount;
        emit Executed(a.agentId, c, address(uint160(m.issuerKey)), a.amount);
    }

    /// Le livre est-il fermé ? reçu == dépensé + rendu.
    function bookClosed(uint256 agentId) external view returns (bool) {
        return received[agentId] == spent[agentId] + returnedTo[agentId];
    }
}
