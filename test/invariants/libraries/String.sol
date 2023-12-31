// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.17;

library String {
    function equal(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }
}
