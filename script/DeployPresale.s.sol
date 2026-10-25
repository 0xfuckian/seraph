// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {SeraphToken} from "../contracts/core/SERAPH.sol";
import {SeraphPresale} from "../contracts/core/Presale.sol";

/**
 * @title DeployPresale
 * @notice Foundry deployment script for Seraph Protocol presale contracts on Base mainnet.
 *
 * @dev Deployment order:
 *   1. SeraphToken   — privacyPool=address(0), treasury=deployer, presale=address(0)
 *   2. SeraphPresale — token, treasury, usdt, usdc, tgeTimestamp
 *   3. token.setPresale(address(presale)) — links them together
 *
 * Environment variables (see .env.example):
 *   TREASURY_ADDRESS  — treasury wallet (defaults to deployer)
 *   USDT_ADDRESS      — USDT contract on Base
 *   USDC_ADDRESS      — USDC contract on Base
 *   TGE_TIMESTAMP     — TGE unix timestamp
 *   ETH_USD_PRICE     — ETH/USD price for the presale's ETH pricing
 *
 * Usage:
 *   source .env
 *   forge script script/DeployPresale.s.sol:DeployPresale \
 *       --rpc-url $BASE_RPC_URL \
 *       --broadcast \
 *       --verify \
 *       -vvvv
 */
contract DeployPresale is Script {
    function run() external {
        // ── Load deployer private key ──────────────────────────────────
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        // ── Resolve configurable parameters ───────────────────────────
        address treasury = vm.envOr("TREASURY_ADDRESS", address(0xa287FC2B8f89023eF1c82af09aee351cCdDa8a76));

        address usdtAddress = vm.envOr("USDT_ADDRESS", address(0x0000000000000000000000000000000000000001));

        address usdcAddress = vm.envOr(
            "USDC_ADDRESS",
            address(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913) // Base mainnet USDC
        );

        uint256 tgeTimestamp = vm.envUint("TGE_TIMESTAMP");
        uint256 ethUsdPrice = vm.envOr("ETH_USD_PRICE", uint256(2000));

        // ── Log deployment parameters ─────────────────────────────────
        console.log("===========================================");
        console.log("  Seraph Protocol - Presale Deployment");
        console.log("  Target: Base Mainnet (chain ID 8453)");
        console.log("===========================================");
        console.log("");
        console.log("Deployer:       ", deployer);
        console.log("Treasury:       ", treasury);
        console.log("USDT:           ", usdtAddress);
        console.log("USDC:           ", usdcAddress);
        console.log("TGE Timestamp:  ", tgeTimestamp);
        console.log("ETH/USD Price:  ", ethUsdPrice);
        console.log("");

        // ── Begin broadcast ───────────────────────────────────────────
        vm.startBroadcast(deployerKey);

        // 1. Deploy SeraphToken
        //    privacyPool = address(0) — placeholder; not needed for presale
        //    presale     = address(0) — will be set after presale deployment
        SeraphToken token = new SeraphToken(
            address(0), // privacyPool placeholder
            treasury,
            address(0) // presale — set below
        );
        console.log("[1/3] SeraphToken deployed at:  ", address(token));

        // 2. Deploy SeraphPresale
        SeraphPresale presale = new SeraphPresale(address(token), treasury, usdtAddress, usdcAddress, tgeTimestamp);
        console.log("[2/3] SeraphPresale deployed at:", address(presale));

        // 3. Link token ↔ presale
        //    Sets presale address on token and grants it minter role
        token.setPresale(address(presale));
        console.log("[3/3] token.setPresale() called - presale linked");

        // 4. Set ETH/USD price on presale (if non-default)
        if (ethUsdPrice != 2000) {
            presale.updateEthUsdPrice(ethUsdPrice);
            console.log("      ETH/USD price updated to:", ethUsdPrice);
        }

        vm.stopBroadcast();

        // ── Summary ───────────────────────────────────────────────────
        console.log("");
        console.log("===========================================");
        console.log("  Deployment Complete");
        console.log("===========================================");
        console.log("SeraphToken:    ", address(token));
        console.log("SeraphPresale:  ", address(presale));
        console.log("Treasury:       ", treasury);
        console.log("Presale minter: ", token.minters(address(presale)));
        console.log("===========================================");
    }
}
