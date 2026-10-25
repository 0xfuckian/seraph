// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../contracts/core/SERAPH.sol";
import "../contracts/core/Presale.sol";
import "../contracts/core/PrivacyPool.sol";
import "../contracts/core/Launchpad.sol";
import "../contracts/core/bridges/CrossEVMBridge.sol";
import "../contracts/core/gas/GasRelayer.sol";
import "../contracts/modules/messaging/InvoiceRegistry.sol";
import "../contracts/modules/ai_payments/UsageVault.sol";
import "../contracts/modules/stablecoin/CollateralVault.sol";

/**
 * @title TestnetFaucetERC20
 * @notice Testnet ERC-20 (for tUSDT, tUSDC, tWXMR) with an open `faucet()` so testers
 *         only need Base Sepolia ETH for gas and can mint test stablecoins/wXMR on demand.
 */
contract TestnetFaucetERC20 is ERC20 {
    uint8 private immutable _dec;

    constructor(string memory name_, string memory symbol_, uint8 decimals_, address initialHolder, uint256 initialUnits)
        ERC20(name_, symbol_)
    {
        _dec = decimals_;
        _mint(initialHolder, initialUnits * (10 ** decimals_));
    }

    function decimals() public view override returns (uint8) {
        return _dec;
    }

    function faucet(uint256 amount) external {
        _mint(msg.sender, amount);
    }
}

/**
 * @title DeployTestnet
 * @notice Deploys the complete Seraph Protocol suite + testnet faucet tokens (tUSDT, tUSDC, tWXMR)
 *         to Anvil (local) or Base Sepolia (chain ID 84532).
 *
 *         Usage (Base Sepolia):
 *         forge script script/DeployTestnet.s.sol:DeployTestnet --rpc-url https://sepolia.base.org --broadcast -vvv
 */
contract DeployTestnet is Script {
    function run() external {
        uint256 deployerKey = vm.envOr(
            "PRIVATE_KEY",
            uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
        );
        address deployer = vm.addr(deployerKey);
        address treasury = vm.envOr("TREASURY_ADDRESS", address(0xa287FC2B8f89023eF1c82af09aee351cCdDa8a76));
        uint256 tgeTimestamp = vm.envOr("TGE_TIMESTAMP", block.timestamp + 7 days);

        console.log("=====================================================");
        console.log("  SERAPH PROTOCOL - FULL TESTNET DEPLOYMENT SUMMARY  ");
        console.log("=====================================================");
        console.log("Deployer / Treasury: ", deployer);

        vm.startBroadcast(deployerKey);

        address tUsdt = address(new TestnetFaucetERC20("Testnet USDT", "tUSDT", 6, deployer, 1_000_000));
        address tUsdc = address(new TestnetFaucetERC20("Testnet USDC", "tUSDC", 6, deployer, 1_000_000));
        address tWxmr = address(new TestnetFaucetERC20("Testnet Wrapped XMR", "tWXMR", 18, deployer, 10_000));
        console.log("tUSDT (6 dec):       ", tUsdt);
        console.log("tUSDC (6 dec):       ", tUsdc);
        console.log("tWXMR (18 dec):      ", tWxmr);

        SeraphToken ser = new SeraphToken(address(0), treasury, address(0));
        SeraphPresale presale = new SeraphPresale(address(ser), treasury, tUsdt, tUsdc, tgeTimestamp);
        PrivacyPool privacyPool = new PrivacyPool(address(ser), treasury, address(0), address(0));
        if (treasury == deployer) {
            ser.setPresale(address(presale));
            ser.setPrivacyPool(address(privacyPool));
        }
        console.log("SeraphToken (SER):   ", address(ser));
        console.log("SeraphPresale:       ", address(presale));
        console.log("PrivacyPool:         ", address(privacyPool));

        SeraphLaunchpad launchpad = new SeraphLaunchpad(treasury, 0.001 ether);
        console.log("SeraphLaunchpad:     ", address(launchpad));

        CrossEVMBridge bridge = new CrossEVMBridge(address(ser), keccak256("SERAPH_TESTNET"), treasury);
        if (treasury == deployer) {
            ser.setMinter(address(bridge), true);
        }
        console.log("CrossEVMBridge:      ", address(bridge));
        console.log("GasRelayer:          ", address(new GasRelayer(address(ser), tWxmr, 1000e18, 10e18)));
        console.log("InvoiceRegistry:     ", address(new InvoiceRegistry()));
        console.log("UsageVault (AI):     ", address(new UsageVault(address(ser))));

        CollateralVault collateralVault = new CollateralVault(address(ser), 2e18);
        console.log("CollateralVault:     ", address(collateralVault));
        console.log("PrivateStable (xUSD):", address(collateralVault.xUSD()));
        console.log("=====================================================");

        vm.stopBroadcast();
    }
}
