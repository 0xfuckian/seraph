// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../core/SERAPH.sol";
import "../core/Presale.sol";
import "../core/Launchpad.sol";
import "./MockERC20.sol";

/// @dev Simulates a Gnosis Safe / smart-contract multisig treasury with >2300 gas receive hook.
contract MultisigTreasuryMock {
    uint256 public receivedCount;

    receive() external payable {
        receivedCount += 1; // Writes to storage (>2300 gas, would fail .transfer())
    }
}

contract SecurityAuditTest is Test {
    SeraphToken public token;
    SeraphPresale public presale;
    SeraphLaunchpad public launchpad;
    MockERC20 public usdt;
    MockERC20 public usdc;
    MultisigTreasuryMock public multisigTreasury;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    function setUp() public {
        multisigTreasury = new MultisigTreasuryMock();
        usdt = new MockERC20("Tether USD", "USDT", 6, 10_000_000);
        usdc = new MockERC20("USD Coin", "USDC", 6, 10_000_000);

        token = new SeraphToken(address(0), address(multisigTreasury), address(0));
        presale = new SeraphPresale(
            address(token), address(multisigTreasury), address(usdt), address(usdc), block.timestamp + 1 days
        );

        vm.prank(address(multisigTreasury));
        token.setPresale(address(presale));

        launchpad = new SeraphLaunchpad(address(multisigTreasury), 0.001 ether);

        usdt.mint(alice, 100_000e6);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }

    function test_Audit1_RepeatPurchasesAccumulateAllocation() public {
        address[] memory wl = new address[](1);
        wl[0] = alice;
        vm.prank(address(multisigTreasury));
        presale.addToWhitelist(wl);

        vm.startPrank(alice);
        usdt.approve(address(presale), 20_000e6);
        // First purchase: $1,000 USDT in Strategic ($0.02)
        presale.buyWithStablecoin(1, 1_000e6, address(usdt), address(0));
        (uint256 firstTotal,,) = presale.getBuyerAllocation(alice, 1);

        // Second purchase: small $100 USDT in Strategic ($0.02) — must ADD to firstTotal, not overwrite
        presale.buyWithStablecoin(1, 100e6, address(usdt), address(0));
        (uint256 secondTotal,,) = presale.getBuyerAllocation(alice, 1);
        vm.stopPrank();

        assertGt(secondTotal, firstTotal);
        assertEq(secondTotal, (firstTotal * 11) / 10);
    }

    function test_Audit2_VestingReleasesExact100PercentAndNeverOvermints() public {
        address[] memory wl = new address[](1);
        wl[0] = alice;
        vm.prank(address(multisigTreasury));
        presale.addToWhitelist(wl);

        vm.startPrank(alice);
        usdt.approve(address(presale), 10_000e6);
        presale.buyWithStablecoin(1, 10_000e6, address(usdt), address(0));
        vm.stopPrank();

        (uint256 expectedTotal,,) = presale.getBuyerAllocation(alice, 1);

        // Execute TGE
        vm.warp(block.timestamp + 2 days);
        vm.prank(address(multisigTreasury));
        presale.executeTGE();

        // Claim 25% TGE allocation
        vm.prank(alice);
        presale.claimInitialAllocation(1);
        assertEq(token.balanceOf(alice), (expectedTotal * 2500) / 10000);

        // Warp 14-day cliff + half of 365-day vesting
        vm.warp(block.timestamp + 14 days + 182.5 days);
        vm.prank(alice);
        presale.claimVested(1);
        // Should now have 25% TGE + 37.5% vested = 62.5% total
        assertApproxEqAbs(token.balanceOf(alice), (expectedTotal * 6250) / 10000, 1e12);

        // Warp 5 years past vesting completion — must cap at 100% of expectedTotal (no infinite mint)
        vm.warp(block.timestamp + 5 * 365 days);
        vm.prank(alice);
        presale.claimVested(1);
        assertEq(token.balanceOf(alice), expectedTotal);

        // Further claims must revert with "Presale: nothing to claim"
        vm.prank(alice);
        vm.expectRevert("Presale: nothing to claim");
        presale.claimVested(1);
    }

    function test_Audit3_ReceiveFallbackCreditsSenderAndWorksWithMultisigTreasury() public {
        // Send 1 ETH directly to presale contract via fallback receive()
        vm.prank(alice);
        (bool ok,) = address(presale).call{value: 1 ether}("");
        assertTrue(ok);

        // Must credit alice, NOT address(presale)
        (uint256 aliceAlloc,,) = presale.getBuyerAllocation(alice, 3);
        (uint256 contractAlloc,,) = presale.getBuyerAllocation(address(presale), 3);
        assertGt(aliceAlloc, 0);
        assertEq(contractAlloc, 0);
        assertGt(multisigTreasury.receivedCount(), 0);
    }

    function test_Audit4_SeraphTokenMaxSupplyCapEnforced() public {
        uint256 maxSupply = token.MAX_SUPPLY();
        vm.startPrank(address(multisigTreasury));
        token.mint(alice, maxSupply);
        assertEq(token.totalSupply(), maxSupply);

        vm.expectRevert("SeraphToken: max supply exceeded");
        token.mint(alice, 1);
        vm.stopPrank();
    }

    function testFuzz_Audit5_LaunchpadCurveAndPoolSolvency(uint96 buy1Wei, uint96 buy2Wei) public {
        buy1Wei = uint96(bound(buy1Wei, 0.01 ether, 3 ether));
        buy2Wei = uint96(bound(buy2Wei, 0.01 ether, 6 ether));

        SeraphLaunchpad.LaunchParams memory p = SeraphLaunchpad.LaunchParams({
            name: "FuzzToken",
            symbol: "FUZZ",
            description: "Fuzz test launch",
            image: "",
            website: "",
            twitter: "",
            telegram: "",
            model: SeraphLaunchpad.LaunchModel.BondingCurve,
            totalSupply: 1_000_000_000e18,
            feeWallet: address(multisigTreasury),
            buyFeeBps: 200,
            sellFeeBps: 200,
            creatorShareBps: 2500,
            buybackShareBps: 2500,
            dividendsShareBps: 2500,
            liquidityShareBps: 2500,
            platformShareBps: 0,
            devBuyBps: 0
        });

        vm.prank(alice);
        address tk = launchpad.launch{value: 0.001 ether}(p);

        vm.prank(alice);
        uint256 out1 = launchpad.buy{value: buy1Wei}(tk, 0, alice);

        vm.prank(bob);
        uint256 out2 = launchpad.buy{value: buy2Wei}(tk, 0, bob);

        // Both buyers sell 100% of their tokens back — contract must remain solvent
        vm.startPrank(alice);
        LaunchToken(tk).approve(address(launchpad), out1);
        launchpad.sell(tk, out1, 0, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        LaunchToken(tk).approve(address(launchpad), out2);
        launchpad.sell(tk, out2, 0, bob);
        vm.stopPrank();

        SeraphLaunchpad.LaunchInfo memory info = launchpad.getLaunch(tk);
        assertGe(address(launchpad).balance, info.realQuoteReserve + launchpad.claimableFees(address(multisigTreasury)));
    }

    function test_Audit6_DoubleClaimDividendsRevertsAndCannotDrainOtherHolders() public {
        SeraphLaunchpad.LaunchParams memory p = SeraphLaunchpad.LaunchParams({
            name: "DivToken",
            symbol: "DIV",
            description: "Dividend double-claim test",
            image: "",
            website: "",
            twitter: "",
            telegram: "",
            model: SeraphLaunchpad.LaunchModel.BondingCurve,
            totalSupply: 1_000_000_000e18,
            feeWallet: address(multisigTreasury),
            buyFeeBps: 250,
            sellFeeBps: 250,
            creatorShareBps: 0,
            buybackShareBps: 0,
            dividendsShareBps: 10000,
            liquidityShareBps: 0,
            platformShareBps: 0,
            devBuyBps: 0
        });

        vm.prank(alice);
        address tk = launchpad.launch{value: 0.001 ether}(p);

        vm.prank(alice);
        launchpad.buy{value: 1 ether}(tk, 0, alice);
        vm.prank(bob);
        launchpad.buy{value: 1 ether}(tk, 0, bob);

        // Alice claims her dividends once
        vm.prank(alice);
        uint256 firstClaim = LaunchToken(tk).claimDividends(alice);
        assertGt(firstClaim, 0);
        assertEq(LaunchToken(tk).claimableDividends(alice), 0);

        // Calling claimDividends a second time without new trades must revert and leave Bob's share intact
        vm.prank(alice);
        vm.expectRevert("LaunchToken: nothing to claim");
        LaunchToken(tk).claimDividends(alice);

        vm.prank(bob);
        uint256 bobClaim = LaunchToken(tk).claimDividends(bob);
        assertGt(bobClaim, 0);
    }
}
