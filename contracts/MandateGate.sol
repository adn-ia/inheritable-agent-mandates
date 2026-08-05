// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title MandateGate — démonstrateur d'exécution adossé au mandat héritable
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
 *         Démonstrateur NON AUDITÉ, testnet uniquement. Aucun ETH ne transite : la
 *         comptabilité est en unités internes créditées par le gardien, et le contrat NE
 *         DÉTIENT AUCUN FONDS par construction. L'interopérabilité avec un émetteur tiers
 *         n'est pas incluse : le digest est de l'EIP-191, pas de l'EIP-712 typé.
 */
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

contract MandateGate {
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

    /// Le livre est-il fermé ? reçu == dépensé + rendu.
    function bookClosed(uint256 agentId) external view returns (bool) {
        return received[agentId] == spent[agentId] + returnedTo[agentId];
    }
}
