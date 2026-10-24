// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../contracts/core/Launchpad.sol";
import "../contracts/core/Presale.sol";
import "./DeployTestnet.s.sol";

/**
 * @title LiveTestnetScenarios
 * @notice Executes a multi-wallet live scenario on Base Sepolia (Chain ID 84532):
 *         1. Deployer funds 3 deterministic test actors (Creator, Buyer1, Buyer2) with 0.003 ETH each.
 *         2. Creator launches "Seraph Privacy Coin" ($SPRIV) on SeraphLaunchpad with 2.5% buy/sell fee
 *            split 40% Creator, 30% Holder Dividends, 20% Buyback & Burn, 10% Auto-LP.
 *         3. Buyer1 buys $SPRIV with 0.0015 ETH.
 *         4. Buyer2 buys $SPRIV with 0.0015 ETH, then approves & sells 50% of their $SPRIV back to the curve.
 *         5. Buyer1 claims accrued ETH holder dividends from LaunchToken($SPRIV).
 *         6. Creator and Deployer (Platform) both claim their accrued ETH fees from SeraphLaunchpad.
 *         7. Deployer whitelists Buyer1 & Buyer2 on SeraphPresale; Buyer1 mints 500 tUSDC via faucet and buys
 *            Strategic Tier 1 (with Creator as referrer); Buyer2 mints 600 tUSDT via faucet and buys
 *            Private Tier 2 (with Creator as referrer).
 */
contract LiveTestnetScenarios is Script {
    address constant LAUNCHPAD_ADDR = 0xe0349E4cC431329207e98C5205062776e058A846;
    address constant PRESALE_ADDR   = 0x2c4156e4bFE0bE6A4e683C7Be521E1cC10B798bE;
    address constant TUSDT_ADDR     = 0x1C4b16a6d0f53a088144Bba6f1C0854b1cF05397;
    address constant TUSDC_ADDR     = 0xA34a029ADC16c4E85C87E7851a2f3AA86867DFd0;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        uint256 creatorKey  = uint256(keccak256("seraph_creator_actor"));
        uint256 buyer1Key   = uint256(keccak256("seraph_buyer1_actor"));
        uint256 buyer2Key   = uint256(keccak256("seraph_buyer2_actor"));

        console.log("=====================================================");
        console.log("  SERAPH PROTOCOL - MULTI-WALLET TESTNET SCENARIOS   ");
        console.log("=====================================================");
        console.log("Deployer (Platform): ", vm.addr(deployerKey));
        console.log("Actor 1 (Creator):   ", vm.addr(creatorKey));
        console.log("Actor 2 (Buyer1):    ", vm.addr(buyer1Key));
        console.log("Actor 3 (Buyer2):    ", vm.addr(buyer2Key));

        _fundActors(deployerKey, vm.addr(creatorKey), vm.addr(buyer1Key), vm.addr(buyer2Key));
        address spriv = _launchToken(creatorKey);
        _tradeAndClaimLaunchpad(spriv, deployerKey, creatorKey, buyer1Key, buyer2Key);
        _runPresaleScenario(deployerKey, buyer1Key, buyer2Key, vm.addr(creatorKey));

        console.log("Final $SPRIV Address:", spriv);
        console.log("=====================================================");
    }

    function _fundActors(uint256 deployerKey, address creator, address buyer1, address buyer2) internal {
        vm.startBroadcast(deployerKey);
        (bool s1, ) = payable(creator).call{value: 0.003 ether}("");
        require(s1, "Fund creator failed");
        (bool s2, ) = payable(buyer1).call{value: 0.003 ether}("");
        require(s2, "Fund buyer1 failed");
        (bool s3, ) = payable(buyer2).call{value: 0.003 ether}("");
        require(s3, "Fund buyer2 failed");
        vm.stopBroadcast();
    }

    function _launchToken(uint256 creatorKey) internal returns (address spriv) {
        SeraphLaunchpad launchpad = SeraphLaunchpad(LAUNCHPAD_ADDR);
        address creator = vm.addr(creatorKey);
        uint256 launchFee = launchpad.launchFee();

        vm.startBroadcast(creatorKey);
        spriv = launchpad.launch{value: launchFee}(
            SeraphLaunchpad.LaunchParams({
                name: "Seraph Privacy Coin",
                symbol: "SPRIV",
                description: "Privacy-preserving bonding curve launch with holder dividends & buyback-burn on Base Sepolia",
                image: "https://seraph.network/assets/spriv.png",
                website: "https://seraph.network",
                twitter: "https://x.com/SeraphProtocol",
                telegram: "https://t.me/SeraphProtocol",
                model: SeraphLaunchpad.LaunchModel.BondingCurve,
                totalSupply: 1_000_000_000e18,
                feeWallet: creator,
                buyFeeBps: 250,
                sellFeeBps: 250,
                creatorShareBps: 4000,
                buybackShareBps: 2000,
                dividendsShareBps: 3000,
                liquidityShareBps: 1000,
                platformShareBps: 0,
                devBuyBps: 0
            })
        );
        vm.stopBroadcast();
        console.log("Launched $SPRIV at:  ", spriv);
    }

    function _tradeAndClaimLaunchpad(
        address spriv,
        uint256 deployerKey,
        uint256 creatorKey,
        uint256 buyer1Key,
        uint256 buyer2Key
    ) internal {
        SeraphLaunchpad launchpad = SeraphLaunchpad(LAUNCHPAD_ADDR);

        // 2. Buyer1 buys $SPRIV with 0.0015 ETH
        vm.startBroadcast(buyer1Key);
        uint256 buyer1Tokens = launchpad.buy{value: 0.0015 ether}(spriv, 0, vm.addr(buyer1Key));
        vm.stopBroadcast();
        console.log("Buyer1 bought SPRIV: ", buyer1Tokens);

        // 3. Buyer2 buys $SPRIV with 0.0015 ETH, then sells half back to the curve
        vm.startBroadcast(buyer2Key);
        uint256 buyer2Tokens = launchpad.buy{value: 0.0015 ether}(spriv, 0, vm.addr(buyer2Key));
        uint256 sellAmount = buyer2Tokens / 2;
        LaunchToken(spriv).approve(LAUNCHPAD_ADDR, sellAmount);
        uint256 ethFromSell = launchpad.sell(spriv, sellAmount, 0, vm.addr(buyer2Key));
        vm.stopBroadcast();
        console.log("Buyer2 bought SPRIV: ", buyer2Tokens);
        console.log("Buyer2 sold SPRIV:   ", sellAmount);
        console.log("Buyer2 ETH received: ", ethFromSell);

        // 4. Buyer1 claims real ETH holder dividends
        vm.startBroadcast(buyer1Key);
        uint256 claimedDivs = LaunchToken(spriv).claimDividends(vm.addr(buyer1Key));
        vm.stopBroadcast();
        console.log("Buyer1 claimed div:  ", claimedDivs);

        // 5. Creator & Deployer (Platform) claim Launchpad ETH fees
        vm.startBroadcast(creatorKey);
        uint256 creatorClaimed = launchpad.claimFees();
        vm.stopBroadcast();
        console.log("Creator claimed fee: ", creatorClaimed);

        vm.startBroadcast(deployerKey);
        uint256 platformClaimed = launchpad.claimFees();
        vm.stopBroadcast();
        console.log("Platform claimed fee:", platformClaimed);
        console.log("Total burned SPRIV:  ", 1_000_000_000e18 - LaunchToken(spriv).totalSupply());
    }

    function _runPresaleScenario(
        uint256 deployerKey,
        uint256 buyer1Key,
        uint256 buyer2Key,
        address creator
    ) internal {
        SeraphPresale presale    = SeraphPresale(payable(PRESALE_ADDR));
        TestnetFaucetERC20 tUsdc = TestnetFaucetERC20(TUSDC_ADDR);
        TestnetFaucetERC20 tUsdt = TestnetFaucetERC20(TUSDT_ADDR);

        // 6a. Deployer whitelists Buyer1 & Buyer2
        vm.startBroadcast(deployerKey);
        address[] memory wl = new address[](2);
        wl[0] = vm.addr(buyer1Key);
        wl[1] = vm.addr(buyer2Key);
        presale.addToWhitelist(wl);
        vm.stopBroadcast();

        // 6b. Buyer1 mints 500 tUSDC and buys Strategic Tier 1
        vm.startBroadcast(buyer1Key);
        tUsdc.faucet(500e6);
        tUsdc.approve(PRESALE_ADDR, 500e6);
        presale.buyWithStablecoin(1, 500e6, TUSDC_ADDR, creator);
        vm.stopBroadcast();

        // 6c. Buyer2 mints 600 tUSDT and buys Private Tier 2
        vm.startBroadcast(buyer2Key);
        tUsdt.faucet(600e6);
        tUsdt.approve(PRESALE_ADDR, 600e6);
        presale.buyWithStablecoin(2, 600e6, TUSDT_ADDR, creator);
        vm.stopBroadcast();

        (uint256 b1Total, , ) = presale.getBuyerAllocation(vm.addr(buyer1Key), 1);
        (uint256 b2Total, , ) = presale.getBuyerAllocation(vm.addr(buyer2Key), 2);
        console.log("Buyer1 Tier 1 SER:   ", b1Total);
        console.log("Buyer2 Tier 2 SER:   ", b2Total);
    }
}
