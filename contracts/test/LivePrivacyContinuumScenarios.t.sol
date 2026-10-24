// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../../script/LivePrivacyContinuumScenarios.s.sol";

contract LivePrivacyContinuumScenariosTest is Test {
    LivePrivacyContinuumScenarios scenarioScript;

    function setUp() public {
        scenarioScript = new LivePrivacyContinuumScenarios();
    }

    function test_LivePrivacyContinuumScenarios_EndToEndExecution() public {
        // Skip in local Anvil if Base Sepolia deployment contracts are not present
        if (0x1d734185220Bd4024c60fC8C1897Aefc08Bcb16F.code.length == 0) {
            vm.skip(true);
            return;
        }
        scenarioScript.run();
    }
}
