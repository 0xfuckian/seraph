// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../contracts/core/SERAPH.sol";
import "../contracts/core/PrivacyPool.sol";
import "../contracts/core/bridges/CrossEVMBridge.sol";
import "../contracts/core/gas/GasRelayer.sol";
import "../contracts/modules/messaging/InvoiceRegistry.sol";

/**
 * @title LivePrivacyContinuumScenarios
 * @notice Multi-actor end-to-end simulation of the Seraph Privacy Continuum.
 */
contract LivePrivacyContinuumScenarios is Script {
    address constant SER_ADDR          = 0x1d734185220Bd4024c60fC8C1897Aefc08Bcb16F;
    address constant PRIVACY_POOL_ADDR = 0x06fA7CAfC96Bf988F3d601138976a448e8B99aE6;
    address constant BRIDGE_ADDR       = 0x5dbdC525f9eA7D3076b285Bf77753a7A1AA10E8d;
    address constant RELAYER_ADDR      = 0xD8dB7BE5F9CC850B1047E0A2D856c454cC617885;
    address constant INVOICE_ADDR      = 0xF5eC3a1CE0A1e2905401A78984b44631e931A733;

    function run() external {
        uint256 deployerKey = vm.envOr(
            "PRIVATE_KEY",
            uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80)
        );
        uint256 aliceKey   = uint256(keccak256("seraph_alice_privacy_actor"));
        uint256 bobKey     = uint256(keccak256("seraph_bob_merchant_actor"));
        uint256 relayerKey = uint256(keccak256("seraph_bonded_relayer_actor"));

        address alice   = vm.addr(aliceKey);
        address bob     = vm.addr(bobKey);
        address relayer = vm.addr(relayerKey);

        console.log("=====================================================");
        console.log("  SERAPH PROTOCOL - LIVE PRIVACY CONTINUUM SCENARIOS ");
        console.log("=====================================================");
        console.log("Deployer (Faucet):   ", vm.addr(deployerKey));
        console.log("Actor 1 (Alice):     ", alice);
        console.log("Actor 2 (Bob):       ", bob);
        console.log("Actor 3 (Relayer):   ", relayer);

        _fundActors(deployerKey, alice, bob, relayer);
        _shieldSER(aliceKey, alice);
        bytes32 invoiceId = _createMerchantInvoice(bobKey, bob);
        bytes32 voucherNullifier = _fundGasVoucher(aliceKey);
        _executeRelayedSettlement(relayerKey, invoiceId, voucherNullifier);
        _bridgeAndBatch(aliceKey, relayerKey, bob);

        console.log("=====================================================");
        console.log("  ALL CONTINUUM SCENARIOS COMPLETED SUCCESSFULLY!    ");
        console.log("=====================================================");
    }

    function _fundActors(uint256 deployerKey, address alice, address bob, address relayer) internal {
        vm.startBroadcast(deployerKey);
        (bool s1, ) = payable(alice).call{value: 0.05 ether}("");
        require(s1, "Fund alice ETH failed");
        (bool s2, ) = payable(bob).call{value: 0.01 ether}("");
        require(s2, "Fund bob ETH failed");
        (bool s3, ) = payable(relayer).call{value: 2.0 ether}("");
        require(s3, "Fund relayer ETH failed");

        SeraphToken ser = SeraphToken(payable(SER_ADDR));
        ser.transfer(alice, 200 ether);
        vm.stopBroadcast();
        console.log("[1] Alice received 200 SER and gas funds");
    }

    function _shieldSER(uint256 aliceKey, address alice) internal {
        vm.startBroadcast(aliceKey);
        SeraphToken(payable(SER_ADDR)).approve(PRIVACY_POOL_ADDR, 50 ether);
        PrivacyPool pool = PrivacyPool(payable(PRIVACY_POOL_ADDR));

        bytes32 blinding = keccak256(abi.encodePacked("alice_blinding_secret_1"));
        bytes32 commitment = keccak256(abi.encodePacked("seraph_note_commitment_v1", uint8(0), uint256(50 ether), alice, blinding));
        bytes memory encMemo = abi.encodePacked("Private note deposit 50 SER");

        pool.shield(50 ether, commitment, encMemo);
        console.log("[2] Alice shielded 50 SER. Pool Merkle root updated.");
        vm.stopBroadcast();
    }

    function _createMerchantInvoice(uint256 bobKey, address bob) internal returns (bytes32 invoiceId) {
        vm.startBroadcast(bobKey);
        InvoiceRegistry invoiceRegistry = InvoiceRegistry(INVOICE_ADDR);
        invoiceId = keccak256(abi.encodePacked("invoice_#88921", block.timestamp));
        bytes32 stealthRecipient = keccak256(abi.encodePacked("bob_stealth_ephemeral_pubkey"));
        bytes memory invoiceMemo = abi.encodePacked("Confidential API Subscription: Tier 3 compute");

        invoiceRegistry.createInvoice(
            invoiceId,
            stealthRecipient,
            bob,
            SER_ADDR,
            25 ether,
            invoiceMemo
        );
        console.log("[3] Bob created Invoice #88921 for 25 SER on InvoiceRegistry");
        vm.stopBroadcast();
    }

    function _fundGasVoucher(uint256 aliceKey) internal returns (bytes32 voucherNullifier) {
        vm.startBroadcast(aliceKey);
        SeraphToken ser = SeraphToken(payable(SER_ADDR));
        ser.approve(RELAYER_ADDR, 5 ether);

        bytes32 voucherSecret = keccak256(abi.encodePacked("alice_gas_secret_alpha"));
        voucherNullifier = keccak256(abi.encodePacked("seraph_gas_nullifier", voucherSecret));
        bytes32 voucherCommitment = keccak256(
            abi.encodePacked(
                "seraph_gas_voucher_v1",
                voucherSecret,
                bytes32(uint256(5 ether)),
                bytes32(uint256(uint160(SER_ADDR)))
            )
        );

        GasRelayer(RELAYER_ADDR).fundGasVoucher(SER_ADDR, 5 ether, voucherCommitment);
        console.log("[4] Alice funded GasRelayer voucher with 5 SER");

        ser.approve(INVOICE_ADDR, 25 ether);
        vm.stopBroadcast();
    }

    function _executeRelayedSettlement(uint256 relayerKey, bytes32 invoiceId, bytes32 voucherNullifier) internal {
        vm.startBroadcast(relayerKey);
        InvoiceRegistry invoiceRegistry = InvoiceRegistry(INVOICE_ADDR);
        bytes memory settleCalldata = abi.encodeWithSelector(
            invoiceRegistry.settleInvoice.selector,
            invoiceId,
            voucherNullifier
        );

        GasRelayer(RELAYER_ADDR).executeWithGasAbstraction(
            voucherNullifier,
            SER_ADDR,
            1 ether,
            INVOICE_ADDR,
            settleCalldata
        );
        console.log("[5] Relayer executed gas-abstracted settlement. Relayer earned 1 SER.");
        vm.stopBroadcast();
    }

    function _bridgeAndBatch(uint256 aliceKey, uint256 relayerKey, address bob) internal {
        vm.startBroadcast(aliceKey);
        SeraphToken(payable(SER_ADDR)).approve(BRIDGE_ADDR, 10 ether);
        CrossEVMBridge bridge = CrossEVMBridge(payable(BRIDGE_ADDR));
        bridge.bridgeOut(bob, 10 ether, keccak256("XMR_EVM"));
        console.log("[6] Alice bridged 10 SER to XMR EVM recipient:", bob);
        vm.stopBroadcast();

        vm.startBroadcast(relayerKey);
        bridge.bondRelayer{value: 1.0 ether}();
        bytes32 mockBatchRoot = keccak256(abi.encodePacked("merkle_batch_root_block_", block.number));
        bytes32 mockStateData = keccak256(abi.encodePacked("batch_state_payload_data"));
        uint256 batchId = bridge.submitStateBatch(mockBatchRoot, mockStateData);
        console.log("[7] Relayer submitted state batch #", batchId, "with 1 ETH bond");
        vm.stopBroadcast();
    }
}
