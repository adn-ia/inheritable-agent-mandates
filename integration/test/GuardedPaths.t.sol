// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {InheritableAgentMandateV3} from "adn/InheritableAgentMandateV3.sol";

/**
 * Chemins gardés — étape 1, simulation locale.
 *
 * Question posée : « une action ne doit être possible que par un chemin qui porte
 * la clause. » Ce test ne l'affirme pas. Il monte le même actif deux fois, sous
 * deux régimes, et imprime ce que la machine fait — aboutit, ou reverte avec sa
 * raison exacte. Aucune valeur attendue n'est écrite ici. L'interprétation vient
 * après, à partir de ces lignes.
 *
 * Régime A — une voie directe subsiste à côté du portail.
 * Régime B — l'actif n'accepte que le portail, et le portail n'autorise que les
 *            chemins déclarés (allowlist, héritée enfant ⊆ parent).
 */

// ---------------------------------------------------------------------------
// L'actif contraint. Deux entrées : une gardée, une non gardée.
// ---------------------------------------------------------------------------
contract Asset {
    mapping(address => uint256) public balanceOf;
    address public immutable guard;
    bool public immutable backdoorOpen;

    constructor(address _guard, bool _backdoorOpen) {
        guard = _guard;
        backdoorOpen = _backdoorOpen;
    }

    function credit(address who, uint256 amount) external {
        balanceOf[who] += amount;
    }

    /// Voie gardée : seul le portail peut l'emprunter.
    function transferGated(address from, address to, uint256 amount) external {
        require(msg.sender == guard, "not the guard");
        _move(from, to, amount);
    }

    /// Voie directe. Présente ou non selon le régime de déploiement.
    function transferDirect(address to, uint256 amount) external {
        require(backdoorOpen, "no unguarded path");
        _move(msg.sender, to, amount);
    }

    function _move(address from, address to, uint256 amount) internal {
        require(balanceOf[from] >= amount, "insufficient balance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }
}

// ---------------------------------------------------------------------------
// Le portail. Allowlist de chemins (cible, sélecteur), héritée enfant ⊆ parent.
// Même mécanique que payeeAllowed, appliquée aux chemins d'exécution.
// ---------------------------------------------------------------------------
contract PathGuard {
    InheritableAgentMandateV3 public immutable mandate;

    mapping(uint256 => mapping(bytes32 => bool)) public pathAllowed;
    mapping(uint256 => uint256) public spent;

    constructor(InheritableAgentMandateV3 _mandate) {
        mandate = _mandate;
    }

    function pathId(address target, bytes4 selector) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(target, selector));
    }

    /// Déclaration d'un chemin. Un enfant ne reçoit que ce que le parent détient.
    function declare(uint256 agentId, address target, bytes4 selector) external {
        require(msg.sender == mandate.ownerOf(agentId), "not owner");
        uint256 parentId = mandate.parentOf(agentId);
        bytes32 p = pathId(target, selector);
        if (parentId != 0) {
            require(pathAllowed[parentId][p], "path not in parent allowlist");
        }
        pathAllowed[agentId][p] = true;
    }

    function execute(uint256 agentId, address asset, address to, uint256 amount) external {
        require(msg.sender == mandate.ownerOf(agentId), "not owner");
        bytes32 p = pathId(asset, Asset.transferGated.selector);
        require(pathAllowed[agentId][p], "path not declared");
        require(mandate.payeeAllowed(agentId, to), "payee not allowed");

        (uint256 cap,,,,) = mandate.mandateOf(agentId);
        require(spent[agentId] + amount <= cap, "over cap");

        spent[agentId] += amount;
        Asset(asset).transferGated(address(this), to, amount);
    }
}

contract GuardedPathsTest is Test {
    InheritableAgentMandateV3 mandate;
    PathGuard guard;

    address GUARDIAN;
    address AGENT;
    address PAYEE;

    uint256 constant CAP = 100 ether;
    uint256 agentId;

    function setUp() public {
        GUARDIAN = makeAddr("guardian");
        AGENT    = makeAddr("agent");
        PAYEE    = makeAddr("payee");

        vm.prank(GUARDIAN);
        mandate = new InheritableAgentMandateV3(GUARDIAN);
        guard = new PathGuard(mandate);

        InheritableAgentMandateV3.Mandate memory m = InheritableAgentMandateV3.Mandate({
            maxSpendWei: CAP,
            validUntil: 0,
            telomere: 3,
            requireLease: false,
            frozen: false
        });
        address[] memory payees = new address[](1);
        payees[0] = PAYEE;

        vm.prank(GUARDIAN);
        agentId = mandate.mint(AGENT, m, payees);
    }

    // -----------------------------------------------------------------------
    function test_regimeA_voie_directe_subsiste() public {
        console2.log("=== REGIME A - une voie directe subsiste a cote du portail ===");
        Asset asset = new Asset(address(guard), true);
        asset.credit(address(guard), 1000 ether);
        asset.credit(AGENT, 1000 ether);

        vm.prank(AGENT);
        guard.declare(agentId, address(asset), Asset.transferGated.selector);

        vm.prank(AGENT);
        guard.execute(agentId, address(asset), PAYEE, CAP);
        console2.log("par le portail, jusqu'au plafond :", guard.spent(agentId));

        // Le plafond est atteint. Le portail refuse tout ajout.
        vm.prank(AGENT);
        try guard.execute(agentId, address(asset), PAYEE, 1 ether) {
            console2.log("portail : un depassement a ete accepte");
        } catch Error(string memory reason) {
            console2.log("portail refuse le depassement :", reason);
        }

        // Mais la voie directe existe.
        uint256 avant = asset.balanceOf(PAYEE);
        vm.prank(AGENT);
        try asset.transferDirect(PAYEE, 500 ether) {
            console2.log("voie directe : ABOUTIT, hors de tout plafond");
        } catch Error(string memory reason) {
            console2.log("voie directe refusee :", reason);
        }
        console2.log("recu par le payee au total :", asset.balanceOf(PAYEE));
        console2.log("compte du portail (spent)  :", guard.spent(agentId));
        console2.log("plafond du mandat          :", CAP);
        console2.log("ecart non compte           :", asset.balanceOf(PAYEE) - avant);
    }

    // -----------------------------------------------------------------------
    function test_regimeB_actif_sans_voie_non_gardee() public {
        console2.log("=== REGIME B - l'actif n'accepte que le portail ===");
        Asset asset = new Asset(address(guard), false);
        asset.credit(address(guard), 1000 ether);
        asset.credit(AGENT, 1000 ether);

        vm.prank(AGENT);
        guard.declare(agentId, address(asset), Asset.transferGated.selector);

        vm.prank(AGENT);
        guard.execute(agentId, address(asset), PAYEE, CAP);
        console2.log("par le portail, jusqu'au plafond :", guard.spent(agentId));

        vm.prank(AGENT);
        try asset.transferDirect(PAYEE, 500 ether) {
            console2.log("voie directe : ABOUTIT");
        } catch Error(string memory reason) {
            console2.log("voie directe refusee :", reason);
        }

        // Et l'appel direct sur la voie gardee, sans passer par le portail ?
        vm.prank(AGENT);
        try asset.transferGated(address(guard), PAYEE, 500 ether) {
            console2.log("appel direct de la voie gardee : ABOUTIT");
        } catch Error(string memory reason) {
            console2.log("appel direct de la voie gardee refuse :", reason);
        }

        console2.log("recu par le payee au total :", asset.balanceOf(PAYEE));
        console2.log("compte du portail (spent)  :", guard.spent(agentId));
        console2.log("plafond du mandat          :", CAP);
    }

    // -----------------------------------------------------------------------
    function test_chemin_non_declare() public {
        console2.log("=== Chemin non declare - le portail lui-meme ===");
        Asset asset = new Asset(address(guard), false);
        asset.credit(address(guard), 1000 ether);

        // Aucune declaration prealable.
        vm.prank(AGENT);
        try guard.execute(agentId, address(asset), PAYEE, 1 ether) {
            console2.log("execute sans declaration : ABOUTIT");
        } catch Error(string memory reason) {
            console2.log("execute sans declaration refuse :", reason);
        }
    }
}
