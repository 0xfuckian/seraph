// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../core/SERAPH.sol";
import "../core/Presale.sol";
import "./MockERC20.sol";

contract PresaleTest is Test {
    SeraphToken token;
    SeraphPresale presale;
    MockERC20 usdt;
    MockERC20 usdc;

    address treasury = address(0x123);
    address buyer = address(0x456);
    address stranger = address(0x789);

    function setUp() public {
        // Deploy mock tokens: 6 decimals each
        usdt = new MockERC20("Tether", "USDT", 6, 1_000_000);
        usdc = new MockERC20("USD Coin", "USDC", 6, 1_000_000);

        // Deploy SERAPH token (deploy with placeholder presale, set later)
        token = new SeraphToken(address(0), treasury, address(0));

        // Deploy presale with tge in 1 day
        presale = new SeraphPresale(
            address(token),
            treasury,
            address(usdt),
            address(usdc),
            block.timestamp + 1 days
        );

        // Set the presale address on the token so transfers from presale are tax-exempt
        vm.prank(treasury);
        token.setPresale(address(presale));

        // Give buyer USDT and ETH
        vm.deal(buyer, 10 ether);
        usdt.transfer(buyer, 100_000 * 1e6); // 100,000 USDT
        usdc.transfer(buyer, 100_000 * 1e6); // 100,000 USDC

        // Add buyer to whitelist for KYC tiers
        vm.startPrank(treasury);
        address[] memory whitelistAddrs = new address[](1);
        whitelistAddrs[0] = buyer;
        presale.addToWhitelist(whitelistAddrs);
        vm.stopPrank();
    }

    function test_PresaleFee_USDT() public {
        uint256 amount = 1000 * 1e6; // 1000 USDT
        vm.startPrank(buyer);
        usdt.approve(address(presale), amount);

        uint256 treasuryBefore = usdt.balanceOf(treasury);
        presale.buyWithStablecoin(3, amount, address(usdt), address(0));
        uint256 treasuryAfter = usdt.balanceOf(treasury);

        uint256 feeTaken = treasuryAfter - treasuryBefore;
        assertEq(feeTaken, 5 * 1e6, "Fee should be 0.5% = 5 USDT");

        uint256 netAmount = 995 * 1e6;
        uint256 expectedTokens = (netAmount * 1e18) / 40000;
        (uint256 total, , ) = presale.getBuyerAllocation(buyer, 3);
        assertEq(total, expectedTokens, "Should receive correct token amount after fee");
    }

    function test_PresaleFee_USDC() public {
        uint256 amount = 500 * 1e6; // 500 USDC
        vm.startPrank(buyer);
        usdc.approve(address(presale), amount);

        uint256 treasuryBefore = usdc.balanceOf(treasury);
        presale.buyWithStablecoin(3, amount, address(usdc), address(0));
        uint256 treasuryAfter = usdc.balanceOf(treasury);

        assertEq(treasuryAfter - treasuryBefore, 2500000, "Fee should be 0.5% = 2.5 USDC");
    }

    function test_PresaleFee_ETH() public {
        uint256 ethAmount = 1 ether;
        uint256 treasuryBefore = address(treasury).balance;
        vm.prank(buyer);
        presale.buyWithETH{value: ethAmount}(3);
        uint256 treasuryAfter = address(treasury).balance;

        uint256 feeTaken = treasuryAfter - treasuryBefore;
        assertEq(feeTaken, 5000000000000000, "Fee should be 0.5% = 0.005 ETH");

        // Token calc: tokens = (netValue * ethUsdPrice * 1e6) / tier.price
        uint256 netValue = ethAmount - feeTaken;
        uint256 expectedTokens = (netValue * presale.ethUsdPrice() * 1e6) / 40000;
        (uint256 total, , ) = presale.getBuyerAllocation(buyer, 3);
        assertEq(total, expectedTokens, "ETH token amount should use ethUsdPrice conversion");

        // Verify: 1 ETH at $2000 = $2000; $2000 / $0.04 = 50000 tokens
        // After 0.5% fee: $1990 / $0.04 = 49750 tokens
        assertEq(total / 1e18, 49750, "1 ETH should yield ~49750 tokens at $0.04 token price");
    }

    function test_FeeZeroOnTinyAmount() public {
        uint256 amount = 100; // 0.0001 USDT
        vm.startPrank(buyer);
        usdt.approve(address(presale), amount);
        presale.buyWithStablecoin(3, amount, address(usdt), address(0));
        assertEq(presale.feesCollectedUSDT(), 0, "Tiny amounts round fee down to 0");
    }

    function test_TokenAmounts_1000USDT() public {
        uint256 amount = 1000 * 1e6;
        vm.startPrank(buyer);
        usdt.approve(address(presale), amount);
        presale.buyWithStablecoin(3, amount, address(usdt), address(0));

        uint256 fee = (amount * 50) / 10000;
        uint256 netAmount = amount - fee;
        uint256 expectedTokens = (netAmount * 1e18) / 40000;

        (uint256 total, , ) = presale.getBuyerAllocation(buyer, 3);
        assertEq(total, expectedTokens);

        // 995 USDT / $0.04 = 24875 tokens
        assertEq(total / 1e18, 24875, "1000 USDT should yield 24875 tokens");
    }

    function test_BUG_NoAccessControls() public {
        // addToWhitelist callable by anyone
        vm.prank(stranger);
        address[] memory wl = new address[](1);
        wl[0] = stranger;
        presale.addToWhitelist(wl);
        assertTrue(presale.isWhitelisted(stranger, 2), "BUG: Anyone can whitelist");

        // executeTGE callable by anyone
        vm.warp(block.timestamp + 2 days);
        vm.prank(stranger);
        presale.executeTGE();
        assertTrue(presale.tgeExecuted(), "BUG: Anyone can execute TGE");

        // withdrawStable callable by anyone (need to fund presale first)
        vm.startPrank(buyer);
        usdt.approve(address(presale), 1000 * 1e6);
        presale.buyWithStablecoin(3, 1000 * 1e6, address(usdt), address(0));
        vm.stopPrank();
        vm.prank(stranger);
        presale.withdrawStable(50 * 1e6, address(usdt));
    }

    function test_FeesCollected_Accuracy() public {
        // USDT purchase
        vm.startPrank(buyer);
        usdt.approve(address(presale), 1000 * 1e6);
        presale.buyWithStablecoin(3, 1000 * 1e6, address(usdt), address(0));

        (uint256 usdtFees, , , ) = presale.getFeesCollected();
        assertEq(usdtFees, 5 * 1e6, "USDT fees tracked");
    }

    function test_TierCap_Enforced() public {
        vm.startPrank(buyer);
        usdt.approve(address(presale), type(uint256).max);
        presale.buyWithStablecoin(3, 10000 * 1e6, address(usdt), address(0));

        (uint256 sold, uint256 cap) = presale.getProgress();
        assertTrue(sold < cap, "Should be within cap");
    }
}
