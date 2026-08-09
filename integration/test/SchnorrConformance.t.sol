// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {SchnorrBIP340} from "adn/MandateGateV2.sol";
import {SchnorrVectors} from "./SchnorrVectors.sol";

/**
 * Le verrou : notre verification schnorr rend-elle EXACTEMENT le meme verdict que
 * les 19 vecteurs officiels BIP-340 (bitcoin/bips) ? Accepter les valides ne suffit
 * pas — il faut rejeter les invalides, et pour la bonne raison.
 *
 * Ce test tourne en CI. S'il casse, la porte schnorr n'est plus digne de confiance.
 */
contract SchnorrConformanceTest is Test {
    function _verify(bytes memory pk, bytes memory m, bytes memory sig) internal view returns (bool) {
        if (pk.length != 32 || sig.length != 64) return false;
        uint256 px = uint256(bytes32(pk));
        uint256 rx;
        uint256 s;
        assembly {
            rx := mload(add(sig, 32))
            s := mload(add(sig, 64))
        }
        return SchnorrBIP340.verify(m, px, rx, s);
    }

    function test_vecteurs_officiels_bip340() public view {
        SchnorrVectors.V[] memory vs = SchnorrVectors.all();
        uint256 ok;
        uint256 bad;
        for (uint256 i; i < vs.length; i++) {
            bool got = _verify(vs[i].pk, vs[i].msg, vs[i].sig);
            if (got == vs[i].expected) ok++;
            else {
                bad++;
                console2.log(string.concat("  DIVERGENCE vecteur ", vs[i].idx, " : ", vs[i].comment));
            }
        }
        console2.log("  vecteurs officiels BIP-340 :", ok, "/", vs.length);
        console2.log("  divergences :", bad);
        assertEq(bad, 0, "divergence avec les vecteurs officiels BIP-340");
        assertEq(ok, 19, "les 19 vecteurs doivent etre couverts");
    }
}
