// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../core/SERAPH.sol";
import "../core/gas/GasRelayer.sol";
import "../modules/messaging/InvoiceRegistry.sol";
import "./MockERC20.sol";

contract MockExecutionTarget {
    uint256 public counter;
    string public lastMessage;
    address public lastCaller;

    event ActionExecuted(address indexed caller, uint256 val, string msg);

    function increment(uint256 val, string calldata msg_) external returns (uint256, bytes32) {
        counter += val;
        lastMessage = msg_;
        lastCaller = msg.sender;
        emit ActionExecuted(msg.sender, val, msg_);
        return (counter, keccak256(bytes(msg_)));
    }

    function failingCall() external pure {
        revert("MockExecutionTarget: intentional failure");
    }

    function reenterRelayer(address relayer, bytes32 nullifier, address feeToken, uint256 feeAmount) external {
        GasRelayer(relayer)
            .executeWithGasAbstraction(
                nullifier,
                feeToken,
                feeAmount,
                address(this),
                abi.encodeWithSelector(this.increment.selector, 1, "reenter")
            );
    }
}

contract GasRelayerDeepTest is Test {
    SeraphToken public ser;
    MockERC20 public wxmr;
    MockERC20 public dai;
    GasRelayer public relayerContract;
    InvoiceRegistry public invoices;
    MockExecutionTarget public target;

    address public owner = makeAddr("owner");
    address public relayer = makeAddr("relayer");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public eve = makeAddr("eve");

    event RelayedCall(
        bytes32 indexed voucherNullifier,
        address indexed target,
        address indexed relayer,
        address feeToken,
        uint256 feePaid
    );

    function setUp() public {
        ser = new SeraphToken(address(0), owner, address(0));
        vm.prank(owner);
        ser.setSellTaxEnabled(false);

        wxmr = new MockERC20("Wrapped XMR", "wXMR", 18, 0);
        dai = new MockERC20("Dai Stablecoin", "DAI", 18, 0);

        vm.prank(owner);
        relayerContract = new GasRelayer(address(ser), address(wxmr), 1000e18, 10e18);

        invoices = new InvoiceRegistry();
        target = new MockExecutionTarget();

        // Mint tokens to users
        vm.prank(owner);
        ser.mint(alice, 100_000e18);
        wxmr.mint(alice, 10_000e18);

        vm.prank(owner);
        ser.mint(bob, 100_000e18);
        wxmr.mint(bob, 10_000e18);

        dai.mint(alice, 10_000e18);
    }

    /* ========================================================================= */
    /* 1. PRE-FUNDED GAS VOUCHERS WITH SER AND WXMR                              */
    /* ========================================================================= */

    function test_FundGasVoucher_SER_Success() public {
        bytes32 commit = keccak256("ser_voucher_01");
        uint256 amount = 1_000e18;

        uint256 aliceBalBefore = ser.balanceOf(alice);
        uint256 poolBalBefore = relayerContract.voucherPoolBalance(address(ser));

        vm.startPrank(alice);
        ser.approve(address(relayerContract), amount);
        relayerContract.fundGasVoucher(address(ser), amount, commit);
        vm.stopPrank();

        assertEq(ser.balanceOf(alice), aliceBalBefore - amount);
        assertEq(relayerContract.voucherPoolBalance(address(ser)), poolBalBefore + amount);
        assertTrue(relayerContract.voucherCommitments(commit));
    }

    function test_FundGasVoucher_WXMR_Success() public {
        bytes32 commit = keccak256("wxmr_voucher_01");
        uint256 amount = 50e18;

        uint256 bobBalBefore = wxmr.balanceOf(bob);
        uint256 poolBalBefore = relayerContract.voucherPoolBalance(address(wxmr));

        vm.startPrank(bob);
        wxmr.approve(address(relayerContract), amount);
        relayerContract.fundGasVoucher(address(wxmr), amount, commit);
        vm.stopPrank();

        assertEq(wxmr.balanceOf(bob), bobBalBefore - amount);
        assertEq(relayerContract.voucherPoolBalance(address(wxmr)), poolBalBefore + amount);
        assertTrue(relayerContract.voucherCommitments(commit));
    }

    function test_FundGasVoucher_DuplicateCommitment_Reverts() public {
        bytes32 commit = keccak256("duplicate_commit");
        uint256 amount = 100e18;

        vm.startPrank(alice);
        ser.approve(address(relayerContract), amount * 2);
        relayerContract.fundGasVoucher(address(ser), amount, commit);

        // Second funding with same commitment must revert
        vm.expectRevert(GasRelayer.CommitmentAlreadyExists.selector);
        relayerContract.fundGasVoucher(address(ser), amount, commit);
        vm.stopPrank();
    }

    function test_FundGasVoucher_InvalidParameters_Reverts() public {
        bytes32 validCommit = keccak256("valid_commit");

        vm.startPrank(alice);
        ser.approve(address(relayerContract), 100e18);

        // Zero amount
        vm.expectRevert("GasRelayer: invalid voucher");
        relayerContract.fundGasVoucher(address(ser), 0, validCommit);

        // Zero commitment
        vm.expectRevert("GasRelayer: invalid voucher");
        relayerContract.fundGasVoucher(address(ser), 100e18, bytes32(0));

        // Unsupported fee token (DAI not yet registered)
        dai.approve(address(relayerContract), 100e18);
        vm.expectRevert(GasRelayer.UnsupportedFeeToken.selector);
        relayerContract.fundGasVoucher(address(dai), 100e18, validCommit);
        vm.stopPrank();
    }

    function test_SetTokenGasRate_AccessControlAndNewTokenFunding() public {
        bytes32 commit = keccak256("dai_commit");

        // Non-owner cannot set gas rate
        vm.prank(eve);
        vm.expectRevert(GasRelayer.Unauthorized.selector);
        relayerContract.setTokenGasRate(address(dai), 500e18);

        // Owner sets rate for DAI
        vm.prank(owner);
        relayerContract.setTokenGasRate(address(dai), 500e18);
        assertEq(relayerContract.tokenGasRate(address(dai)), 500e18);

        // Now DAI funding succeeds
        vm.startPrank(alice);
        dai.approve(address(relayerContract), 50e18);
        relayerContract.fundGasVoucher(address(dai), 50e18, commit);
        vm.stopPrank();

        assertEq(relayerContract.voucherPoolBalance(address(dai)), 50e18);
    }

    /* ========================================================================= */
    /* 2. EXECUTION WITH VOUCHER NULLIFIER & ARBITRARY TARGET CALLS              */
    /* ========================================================================= */

    function test_ExecuteWithGasAbstraction_SER_Success() public {
        // Fund SER voucher pool
        bytes32 commit = keccak256("ser_exec_commit");
        vm.startPrank(alice);
        ser.approve(address(relayerContract), 500e18);
        relayerContract.fundGasVoucher(address(ser), 500e18, commit);
        vm.stopPrank();

        bytes32 nullifier = keccak256("ser_exec_nullifier");
        uint256 feeAmount = 25e18;
        bytes memory callData =
            abi.encodeWithSelector(MockExecutionTarget.increment.selector, 77, "Hello Seraph Relayer");

        uint256 relayerSerBefore = ser.balanceOf(relayer);
        uint256 poolBefore = relayerContract.voucherPoolBalance(address(ser));

        vm.expectEmit(true, true, true, true);
        emit RelayedCall(nullifier, address(target), relayer, address(ser), feeAmount);

        vm.prank(relayer);
        bytes memory result =
            relayerContract.executeWithGasAbstraction(nullifier, address(ser), feeAmount, address(target), callData);

        // Verify decoded return values
        (uint256 newCount, bytes32 msgHash) = abi.decode(result, (uint256, bytes32));
        assertEq(newCount, 77);
        assertEq(msgHash, keccak256(bytes("Hello Seraph Relayer")));

        // Verify target state
        assertEq(target.counter(), 77);
        assertEq(target.lastMessage(), "Hello Seraph Relayer");
        assertEq(target.lastCaller(), address(relayerContract));

        // Verify relayer fee payment and pool deduction
        assertEq(ser.balanceOf(relayer), relayerSerBefore + feeAmount);
        assertEq(relayerContract.voucherPoolBalance(address(ser)), poolBefore - feeAmount);
        assertTrue(relayerContract.usedVouchers(nullifier));
    }

    function test_ExecuteWithGasAbstraction_WXMR_Success() public {
        bytes32 commit = keccak256("wxmr_exec_commit");
        vm.startPrank(bob);
        wxmr.approve(address(relayerContract), 20e18);
        relayerContract.fundGasVoucher(address(wxmr), 20e18, commit);
        vm.stopPrank();

        bytes32 nullifier = keccak256("wxmr_exec_nullifier");
        uint256 feeAmount = 0.75e18;
        bytes memory callData = abi.encodeWithSelector(MockExecutionTarget.increment.selector, 123, "Private Relaying");

        uint256 relayerWxmrBefore = wxmr.balanceOf(relayer);
        uint256 poolBefore = relayerContract.voucherPoolBalance(address(wxmr));

        vm.prank(relayer);
        relayerContract.executeWithGasAbstraction(nullifier, address(wxmr), feeAmount, address(target), callData);

        assertEq(target.counter(), 123);
        assertEq(wxmr.balanceOf(relayer), relayerWxmrBefore + feeAmount);
        assertEq(relayerContract.voucherPoolBalance(address(wxmr)), poolBefore - feeAmount);
        assertTrue(relayerContract.usedVouchers(nullifier));
    }

    function test_ExecuteWithGasAbstraction_ZeroFeeExecution_Success() public {
        bytes32 commit = keccak256("zero_fee_commit");
        vm.startPrank(alice);
        ser.approve(address(relayerContract), 100e18);
        relayerContract.fundGasVoucher(address(ser), 100e18, commit);
        vm.stopPrank();

        bytes32 nullifier = keccak256("zero_fee_nullifier");
        uint256 poolBefore = relayerContract.voucherPoolBalance(address(ser));
        uint256 relayerBalBefore = ser.balanceOf(relayer);

        bytes memory callData = abi.encodeWithSelector(MockExecutionTarget.increment.selector, 10, "Zero fee call");

        vm.prank(relayer);
        relayerContract.executeWithGasAbstraction(
            nullifier,
            address(ser),
            0, // feeAmount is 0
            address(target),
            callData
        );

        assertEq(target.counter(), 10);
        assertEq(ser.balanceOf(relayer), relayerBalBefore);
        assertEq(relayerContract.voucherPoolBalance(address(ser)), poolBefore);
        assertTrue(relayerContract.usedVouchers(nullifier));
    }

    function test_ExecuteWithGasAbstraction_CallInvoiceRegistry_Success() public {
        bytes32 commit = keccak256("invoice_relayed_commit");
        vm.startPrank(alice);
        ser.approve(address(relayerContract), 100e18);
        relayerContract.fundGasVoucher(address(ser), 100e18, commit);
        vm.stopPrank();

        bytes32 nullifier = keccak256("invoice_relayed_nullifier");
        bytes memory callData = abi.encodeWithSelector(
            InvoiceRegistry.sendEncryptedMessage.selector,
            keccak256("recipient_stealth_key"),
            keccak256("ephemeral_key"),
            bytes("encrypted_invoice_payload")
        );

        vm.prank(relayer);
        relayerContract.executeWithGasAbstraction(nullifier, address(ser), 5e18, address(invoices), callData);

        assertTrue(relayerContract.usedVouchers(nullifier));
        assertEq(ser.balanceOf(relayer), 5e18);
    }

    /* ========================================================================= */
    /* 3. ATTACK SCENARIOS: FORBIDDEN TARGET REVERSION                           */
    /* ========================================================================= */

    function test_AttackScenarios_ForbiddenTargets_AllRevert() public {
        // Pre-fund voucher pool so insufficient balance is not the cause
        bytes32 commit = keccak256("attack_commit");
        vm.startPrank(alice);
        ser.approve(address(relayerContract), 500e18);
        relayerContract.fundGasVoucher(address(ser), 500e18, commit);
        vm.stopPrank();

        bytes32 nullifier = keccak256("attack_nullifier_01");

        // 1. FORBIDDEN TARGET: seraphToken
        bytes memory drainSerCall = abi.encodeWithSelector(IERC20.transfer.selector, eve, 100e18);
        vm.prank(relayer);
        vm.expectRevert(GasRelayer.ForbiddenTarget.selector);
        relayerContract.executeWithGasAbstraction(nullifier, address(ser), 1e18, address(ser), drainSerCall);

        // 2. FORBIDDEN TARGET: xmrToken
        bytes memory drainXmrCall = abi.encodeWithSelector(IERC20.transfer.selector, eve, 10e18);
        vm.prank(relayer);
        vm.expectRevert(GasRelayer.ForbiddenTarget.selector);
        relayerContract.executeWithGasAbstraction(nullifier, address(ser), 1e18, address(wxmr), drainXmrCall);

        // 3. FORBIDDEN TARGET: address(this) [GasRelayer itself]
        bytes memory selfCall =
            abi.encodeWithSelector(GasRelayer.fundGasVoucher.selector, address(ser), 10e18, keccak256("hack"));
        vm.prank(relayer);
        vm.expectRevert(GasRelayer.ForbiddenTarget.selector);
        relayerContract.executeWithGasAbstraction(nullifier, address(ser), 1e18, address(relayerContract), selfCall);

        // 4. FORBIDDEN TARGET: address(0)
        vm.prank(relayer);
        vm.expectRevert(GasRelayer.ForbiddenTarget.selector);
        relayerContract.executeWithGasAbstraction(nullifier, address(ser), 1e18, address(0), hex"00");

        // 5. FORBIDDEN TARGET: Registered fee token (tokenGasRate[target] != 0)
        vm.prank(owner);
        relayerContract.setTokenGasRate(address(dai), 500e18);

        vm.prank(relayer);
        vm.expectRevert(GasRelayer.ForbiddenTarget.selector);
        relayerContract.executeWithGasAbstraction(nullifier, address(ser), 1e18, address(dai), hex"1234");

        // Crucial invariant: Nullifier must NOT have been consumed by any failed forbidden call
        assertFalse(relayerContract.usedVouchers(nullifier));
        // Pool balance must remain completely intact
        assertEq(relayerContract.voucherPoolBalance(address(ser)), 500e18);
    }

    /* ========================================================================= */
    /* 4. REPLAY ATTACKS WITH VOUCHER NULLIFIERS                                 */
    /* ========================================================================= */

    function test_ReplayAttack_SameVoucherNullifier_Reverts() public {
        bytes32 commit = keccak256("replay_commit");
        vm.startPrank(alice);
        ser.approve(address(relayerContract), 500e18);
        relayerContract.fundGasVoucher(address(ser), 500e18, commit);
        vm.stopPrank();

        bytes32 nullifier = keccak256("nullifier_to_replay");
        bytes memory callData = abi.encodeWithSelector(MockExecutionTarget.increment.selector, 1, "First call");

        // First execution succeeds
        vm.prank(relayer);
        relayerContract.executeWithGasAbstraction(nullifier, address(ser), 10e18, address(target), callData);
        assertTrue(relayerContract.usedVouchers(nullifier));

        // ATTACK 1: Exact identical replay
        vm.prank(relayer);
        vm.expectRevert(GasRelayer.VoucherAlreadyUsed.selector);
        relayerContract.executeWithGasAbstraction(nullifier, address(ser), 10e18, address(target), callData);

        // ATTACK 2: Replay with different feeToken
        vm.prank(relayer);
        vm.expectRevert(GasRelayer.VoucherAlreadyUsed.selector);
        relayerContract.executeWithGasAbstraction(nullifier, address(wxmr), 1e18, address(target), callData);

        // ATTACK 3: Replay with different target and data
        vm.prank(relayer);
        vm.expectRevert(GasRelayer.VoucherAlreadyUsed.selector);
        relayerContract.executeWithGasAbstraction(nullifier, address(ser), 5e18, address(invoices), hex"1234");

        // ATTACK 4: Replay with 0 fee
        vm.prank(relayer);
        vm.expectRevert(GasRelayer.VoucherAlreadyUsed.selector);
        relayerContract.executeWithGasAbstraction(nullifier, address(ser), 0, address(target), callData);
    }

    function test_ExecuteWithGasAbstraction_ZeroNullifier_Reverts() public {
        vm.prank(relayer);
        vm.expectRevert(GasRelayer.VoucherAlreadyUsed.selector);
        relayerContract.executeWithGasAbstraction(bytes32(0), address(ser), 0, address(target), hex"00");
    }

    /* ========================================================================= */
    /* 5. FAILURE ROLLBACKS & REENTRANCY DEFENSES                                */
    /* ========================================================================= */

    function test_ExecuteWithGasAbstraction_TargetCallFailed_RollsBackState() public {
        bytes32 commit = keccak256("fail_commit");
        vm.startPrank(alice);
        ser.approve(address(relayerContract), 200e18);
        relayerContract.fundGasVoucher(address(ser), 200e18, commit);
        vm.stopPrank();

        bytes32 nullifier = keccak256("fail_nullifier");
        bytes memory failingCall = abi.encodeWithSelector(MockExecutionTarget.failingCall.selector);

        uint256 relayerBalBefore = ser.balanceOf(relayer);
        uint256 poolBefore = relayerContract.voucherPoolBalance(address(ser));

        vm.prank(relayer);
        vm.expectRevert(GasRelayer.TargetCallFailed.selector);
        relayerContract.executeWithGasAbstraction(nullifier, address(ser), 50e18, address(target), failingCall);

        // Whole transaction rolls back:
        // Relayer did not receive fee
        assertEq(ser.balanceOf(relayer), relayerBalBefore);
        // Voucher pool not decremented
        assertEq(relayerContract.voucherPoolBalance(address(ser)), poolBefore);
        // Voucher nullifier remains unused
        assertFalse(relayerContract.usedVouchers(nullifier));
    }

    function test_ExecuteWithGasAbstraction_InsufficientVoucherPool_Reverts() public {
        bytes32 commit = keccak256("small_pool_commit");
        vm.startPrank(alice);
        ser.approve(address(relayerContract), 50e18);
        relayerContract.fundGasVoucher(address(ser), 50e18, commit);
        vm.stopPrank();

        bytes32 nullifier = keccak256("excessive_fee_nullifier");
        bytes memory callData = abi.encodeWithSelector(MockExecutionTarget.increment.selector, 1, "test");

        // Relayer requests 50.0001e18 fee from a 50e18 pool
        vm.prank(relayer);
        vm.expectRevert(GasRelayer.InsufficientVoucherPool.selector);
        relayerContract.executeWithGasAbstraction(nullifier, address(ser), 50.0001e18, address(target), callData);
    }

    function test_ExecuteWithGasAbstraction_Reentrancy_Blocked() public {
        bytes32 commit = keccak256("reenter_commit");
        vm.startPrank(alice);
        ser.approve(address(relayerContract), 500e18);
        relayerContract.fundGasVoucher(address(ser), 500e18, commit);
        vm.stopPrank();

        bytes32 outerNullifier = keccak256("outer_nullifier");
        bytes32 innerNullifier = keccak256("inner_nullifier");

        bytes memory attackData = abi.encodeWithSelector(
            MockExecutionTarget.reenterRelayer.selector, address(relayerContract), innerNullifier, address(ser), 10e18
        );

        vm.prank(relayer);
        // Reentrancy is blocked by nonReentrant on GasRelayer -> causes the inner call to revert
        // which triggers TargetCallFailed in the outer call
        vm.expectRevert(GasRelayer.TargetCallFailed.selector);
        relayerContract.executeWithGasAbstraction(outerNullifier, address(ser), 10e18, address(target), attackData);
    }
}
