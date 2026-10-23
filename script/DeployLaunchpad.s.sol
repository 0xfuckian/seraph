// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../contracts/core/Launchpad.sol";

/**
 * @title DeployLaunchpad
 * @notice Deploys SeraphLaunchpad to Base or Arc.
 *         Usage:
 *         forge script script/DeployLaunchpad.s.sol:DeployLaunchpad --rpc-url $BASE_RPC_URL --broadcast
 */
contract DeployLaunchpad is Script {
    function run() external returns (SeraphLaunchpad launchpad) {
        uint256 deployerKey = vm.envOr("PRIVATE_KEY", uint256(0));
        address deployer = deployerKey != 0 ? vm.addr(deployerKey) : msg.sender;
        address feeRecipient = vm.envOr("PLATFORM_FEE_RECIPIENT", deployer);
        uint256 launchFee = vm.envOr("LAUNCH_FEE_WEI", uint256(0.0005 ether));

        if (deployerKey != 0) {
            vm.startBroadcast(deployerKey);
        } else {
            vm.startBroadcast();
        }

        launchpad = new SeraphLaunchpad(feeRecipient, launchFee);

        vm.stopBroadcast();

        console.log("=== SeraphLaunchpad Deployed ===");
        console.log("Launchpad address:     ", address(launchpad));
        console.log("Platform fee recipient:", feeRecipient);
        console.log("Flat launch fee (wei): ", launchFee);
    }
}
