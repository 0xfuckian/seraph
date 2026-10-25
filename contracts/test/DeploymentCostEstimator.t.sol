// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../core/SERAPH.sol";
import "../core/PrivacyPool.sol";
import "../core/bridges/CrossEVMBridge.sol";
import "../core/gas/GasRelayer.sol";
import "../core/Presale.sol";
import "../core/Launchpad.sol";
import "../modules/messaging/InvoiceRegistry.sol";
import "../modules/ai_payments/UsageVault.sol";
import "../modules/stablecoin/CollateralVault.sol";

contract DeploymentCostEstimatorTest is Test {
    struct DeploymentContext {
        address treasury;
        address tUsdt;
        address tUsdc;
        address tWxmr;
        uint256 totalGas;
    }

    function test_MeasureExactDeploymentGas() public {
        DeploymentContext memory ctx;
        ctx.treasury = address(0x1111111111111111111111111111111111111111);
        ctx.tUsdt = address(0x3333333333333333333333333333333333333333);
        ctx.tUsdc = address(0x4444444444444444444444444444444444444444);
        ctx.tWxmr = address(0x5555555555555555555555555555555555555555);

        console.log("================================================================");
        console.log("   SERAPH PROTOCOL - EXACT CONTRACT DEPLOYMENT GAS AUDIT        ");
        console.log("================================================================");

        // 1. SeraphToken
        uint256 gStart = gasleft();
        SeraphToken ser = new SeraphToken(address(0), address(this), address(0));
        uint256 gEnd = gasleft();
        ctx.totalGas += (gStart - gEnd);
        console.log("1.  SeraphToken (SER):           ", gStart - gEnd, "gas");

        // 2. PrivacyPool
        gStart = gasleft();
        PrivacyPool pool = new PrivacyPool(address(ser), ctx.treasury, address(0), address(0));
        gEnd = gasleft();
        ctx.totalGas += (gStart - gEnd);
        console.log("2.  PrivacyPool:                 ", gStart - gEnd, "gas");

        // 3. CrossEVMBridge
        gStart = gasleft();
        CrossEVMBridge bridge = new CrossEVMBridge(address(ser), keccak256("SERAPH_TESTNET"), ctx.treasury);
        gEnd = gasleft();
        ctx.totalGas += (gStart - gEnd);
        console.log("3.  CrossEVMBridge:              ", gStart - gEnd, "gas");

        // 4. GasRelayer
        gStart = gasleft();
        new GasRelayer(address(ser), ctx.tWxmr, 1000e18, 10e18);
        gEnd = gasleft();
        ctx.totalGas += (gStart - gEnd);
        console.log("4.  GasRelayer:                  ", gStart - gEnd, "gas");

        // 5. SeraphPresale
        gStart = gasleft();
        SeraphPresale presale = new SeraphPresale(address(ser), ctx.treasury, ctx.tUsdt, ctx.tUsdc, block.timestamp + 30 days);
        gEnd = gasleft();
        ctx.totalGas += (gStart - gEnd);
        console.log("5.  SeraphPresale:               ", gStart - gEnd, "gas");

        // 6. SeraphLaunchpad
        gStart = gasleft();
        SeraphLaunchpad launchpad = new SeraphLaunchpad(ctx.treasury, 0.0005 ether);
        gEnd = gasleft();
        ctx.totalGas += (gStart - gEnd);
        console.log("6.  SeraphLaunchpad:             ", gStart - gEnd, "gas");

        // 7. InvoiceRegistry
        gStart = gasleft();
        new InvoiceRegistry();
        gEnd = gasleft();
        ctx.totalGas += (gStart - gEnd);
        console.log("7.  InvoiceRegistry:             ", gStart - gEnd, "gas");

        // 8. UsageVault
        gStart = gasleft();
        new UsageVault(address(ser));
        gEnd = gasleft();
        ctx.totalGas += (gStart - gEnd);
        console.log("8.  UsageVault (AI Payments):    ", gStart - gEnd, "gas");

        // 9. CollateralVault
        gStart = gasleft();
        new CollateralVault(address(ser), 2e18);
        gEnd = gasleft();
        ctx.totalGas += (gStart - gEnd);
        console.log("9.  CollateralVault + xUSD:      ", gStart - gEnd, "gas");

        // 10. Initial Wiring & Permissions
        gStart = gasleft();
        ser.setPrivacyPool(address(pool));
        ser.setPresale(address(presale));
        ser.setMinter(address(presale), true);
        ser.setMinter(address(bridge), true);
        ser.setTaxExempt(address(pool), true);
        ser.setTaxExempt(address(bridge), true);
        ser.setTaxExempt(address(launchpad), true);
        gEnd = gasleft();
        ctx.totalGas += (gStart - gEnd);
        console.log("10. Initial Wiring & Permissions:", gStart - gEnd, "gas");

        console.log("----------------------------------------------------------------");
        console.log("TOTAL PROTOCOL DEPLOYMENT GAS:   ", ctx.totalGas, "gas");
        console.log("================================================================");
    }
}
