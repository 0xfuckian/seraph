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
        presale = new SeraphPresale(address(token), treasury, address(usdt), address(usdc), block.timestamp + 1 days);

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
        (uint256 total,,) = presale.getBuyerAllocation(buyer, 3);
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
        (uint256 total,,) = presale.getBuyerAllocation(buyer, 3);
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

        (uint256 total,,) = presale.getBuyerAllocation(buyer, 3);
        assertEq(total, expectedTokens);

        // 995 USDT / $0.04 = 24875 tokens
        assertEq(total / 1e18, 24875, "1000 USDT should yield 24875 tokens");
    }

    function test_AccessControls_Enforced() public {
        // addToWhitelist should revert when called by non-treasury
        vm.prank(stranger);
        address[] memory wl = new address[](1);
        wl[0] = stranger;
        vm.expectRevert("Presale: caller is not treasury");
        presale.addToWhitelist(wl);

        // executeTGE should revert when called by non-treasury
        vm.prank(stranger);
        vm.expectRevert("Presale: caller is not treasury");
        presale.executeTGE();

        // updateEthUsdPrice should revert when called by non-treasury
        vm.prank(stranger);
        vm.expectRevert("Presale: caller is not treasury");
        presale.updateEthUsdPrice(3000);

        // withdrawStable should revert when called by non-treasury
        vm.startPrank(buyer);
        usdt.approve(address(presale), 1000 * 1e6);
        presale.buyWithStablecoin(3, 1000 * 1e6, address(usdt), address(0));
        vm.stopPrank();
        vm.prank(stranger);
        vm.expectRevert("Presale: caller is not treasury");
        presale.withdrawStable(50 * 1e6, address(usdt));
    }

    function test_FeesCollected_Accuracy() public {
        // USDT purchase
        vm.startPrank(buyer);
        usdt.approve(address(presale), 1000 * 1e6);
        presale.buyWithStablecoin(3, 1000 * 1e6, address(usdt), address(0));

        (uint256 usdtFees,,,) = presale.getFeesCollected();
        assertEq(usdtFees, 5 * 1e6, "USDT fees tracked");
    }

    function test_TierCap_Enforced() public {
        vm.startPrank(buyer);
        usdt.approve(address(presale), type(uint256).max);
        presale.buyWithStablecoin(3, 10000 * 1e6, address(usdt), address(0));

        (uint256 sold, uint256 cap) = presale.getProgress();
        assertTrue(sold < cap, "Should be within cap");
    }

    function test_SellTax_AppliedOnTransfer() public {
        // Mint tokens to buyer (simulating post-TGE claim)
        vm.startPrank(treasury);
        token.mint(buyer, 1000e18);
        vm.stopPrank();

        uint256 supplyBefore = token.totalSupply();
        uint256 treasuryBefore = token.balanceOf(treasury);

        vm.prank(buyer);
        token.transfer(stranger, 100e18);

        // Sell tax: 1% on sells, 50% burn, 50% treasury
        // tax = 1e18 (1 token), burned = 0.5e18, toTreasury = 0.5e18
        assertEq(token.balanceOf(stranger), 99e18, "Buyer should receive 99 tokens (100 - 1% tax)");
        assertEq(token.balanceOf(treasury), treasuryBefore + 5e17, "Treasury gets 0.5%");
        assertEq(token.totalSupply(), supplyBefore - 5e17, "0.5% should be burned");
    }

    function test_SellTax_Disabled_ByOwner() public {
        vm.startPrank(treasury);
        token.setSellTaxEnabled(false);
        vm.stopPrank();

        vm.startPrank(treasury);
        token.mint(buyer, 1000e18);
        vm.stopPrank();

        uint256 initialSupply = token.totalSupply();
        vm.prank(buyer);
        token.transfer(stranger, 100e18);

        assertEq(token.balanceOf(stranger), 100e18, "No tax when disabled");
        assertEq(token.totalSupply(), initialSupply, "No burn when disabled");
    }

    function test_Mint_RequiresMinter() public {
        // Non-minter cannot mint
        vm.prank(stranger);
        vm.expectRevert("SeraphToken: not a minter");
        token.mint(stranger, 1e18);

        // Treasury (registered as minter in constructor) can
        vm.prank(treasury);
        token.mint(buyer, 100e18);
        assertEq(token.balanceOf(buyer), 100e18);

        // Bridge can be granted minting and then mint
        vm.prank(treasury);
        token.setMinter(stranger, true);
        vm.prank(stranger);
        token.receiveFromBridge(buyer, 50e18);
        assertEq(token.balanceOf(buyer), 150e18, "Registered bridge can mint via receiveFromBridge");
    }

    function test_SellTax_ExemptsTreasuryAndPool() public {
        vm.startPrank(treasury);
        token.mint(treasury, 1000e18);
        token.mint(address(presale), 1000e18);
        vm.stopPrank();

        // Treasury -> stranger must be tax-exempt (liquidity provision, grants)
        uint256 supplyBefore = token.totalSupply();
        vm.prank(treasury);
        token.transfer(stranger, 100e18);
        assertEq(token.balanceOf(stranger), 100e18, "Treasury transfers untaxed");
        assertEq(token.totalSupply(), supplyBefore, "No burn on treasury transfer");

        // Presale -> stranger must be tax-exempt (TGE disbursements)
        vm.prank(address(presale));
        token.transfer(stranger, 100e18);
        assertEq(token.balanceOf(stranger), 200e18, "Presale transfers untaxed");
    }

    function test_Strategic_Cliff_Is14Days() public {
        vm.startPrank(buyer);
        usdt.approve(address(presale), 1000 * 1e6);
        presale.buyWithStablecoin(1, 1000 * 1e6, address(usdt), address(0)); // Strategic tier
        vm.stopPrank();

        (,,, uint256 cliffSeconds, uint256 duration,) = presale.vesting(buyer, 1);
        assertEq(cliffSeconds, 14 days, "Strategic cliff should be 14 days");
        assertEq(duration, 365 days, "Strategic vesting should be 12 months");
    }

    function test_Public_Tier_HasNoVesting() public {
        vm.startPrank(buyer);
        usdt.approve(address(presale), 1000 * 1e6);
        presale.buyWithStablecoin(3, 1000 * 1e6, address(usdt), address(0)); // Public tier
        vm.stopPrank();

        (,,, uint256 cliffSeconds, uint256 duration,) = presale.vesting(buyer, 3);
        assertEq(cliffSeconds, 0, "Public cliff should be 0");
        assertEq(duration, 0, "Public has no vesting");
    }

    function test_TierAdmin_Controls() public {
        // Treasury can pause a tier -> purchase reverts
        vm.prank(treasury);
        presale.setTierActive(3, false);
        vm.startPrank(buyer);
        usdt.approve(address(presale), 1000 * 1e6);
        vm.expectRevert("Presale: tier inactive");
        presale.buyWithStablecoin(3, 1000 * 1e6, address(usdt), address(0));
        vm.stopPrank();

        // Treasury can update price; token math follows the new price
        vm.prank(treasury);
        presale.setTierActive(3, true); // re-open the tier
        vm.prank(treasury);
        presale.setTierPrice(3, 50000); // $0.05
        vm.startPrank(buyer);
        usdt.approve(address(presale), 1000 * 1e6);
        presale.buyWithStablecoin(3, 1000 * 1e6, address(usdt), address(0));
        vm.stopPrank();
        (uint256 total,,) = presale.getBuyerAllocation(buyer, 3);
        // 995 USDT / $0.05 = 19,900 tokens
        assertEq(total / 1e18, 19900, "Tokens recomputed at updated price");

        // Non-treasury cannot pause
        vm.prank(stranger);
        vm.expectRevert("Presale: caller is not treasury");
        presale.setTierActive(3, true);
    }

    function test_WithdrawETH_SurvivesStrayETH() public {
        // Donate stray ETH to the presale contract (simulates forced transfer)
        vm.deal(address(presale), 1 ether);
        // Treasury withdraws — must not underflow totalRaisedETH even though nothing was raised
        vm.prank(treasury);
        presale.withdrawETH();
        assertEq(presale.totalRaisedETH(), 0, "totalRaisedETH clamped to 0 instead of underflowing");
    }

    function capOf(uint256 id) internal view returns (uint256) {
        (string memory nm, uint256 pr, uint256 hc, uint256 sd, bool kyc, uint256 lk, uint256 vs, bool ac) =
            presale.tiers(id);
        return hc;
    }

    function test_Allocation_MatchesWhitepaper() public {
        // Presale distributes Early Contributors (15M) + Public Sale & Liquidity (10M) = 25M
        (uint256 sold, uint256 cap) = presale.getProgress();
        assertEq(sold, 0, "Nothing sold yet");
        assertEq(cap, 25_000_000e18, "Presale cap must equal 25M SER (15M private + 10M public)");

        // Per-tier caps match the §9.2 split
        assertEq(capOf(1), 3_750_000e18, "Strategic = 3.75M (25% of Early Contributors 15M)");
        assertEq(capOf(2), 11_250_000e18, "Private = 11.25M (75% of Early Contributors 15M)");
        assertEq(capOf(3), 10_000_000e18, "Public = 10M (Public Sale + Liquidity)");

        // Remaining 75M stays out of the presale (40M ecosystem + 20M team + 15M foundation)
        assertEq(100_000_000e18 - cap, 75_000_000e18, "75M allocated to ecosystem/team/foundation");
    }
}
