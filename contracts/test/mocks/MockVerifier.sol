// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../core/PrivacyPool.sol";
import "../../core/bridges/CrossEVMBridge.sol";

contract MockVerifier is IVerifier, IBridgeVerifier {
    bool public shouldPass = true;
    bool public shouldPassBridge = true;

    function setShouldPass(bool _pass) external {
        shouldPass = _pass;
    }

    function setShouldPassBridge(bool _pass) external {
        shouldPassBridge = _pass;
    }

    function verifyProof(bytes calldata, uint256[] calldata) external view override returns (bool) {
        return shouldPass;
    }

    function verifyFraudProof(
        bytes32,
        bytes32,
        bytes calldata,
        bytes32[] calldata
    ) external view override returns (bool) {
        return shouldPassBridge;
    }
}
