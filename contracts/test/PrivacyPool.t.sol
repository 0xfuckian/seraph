// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../core/SERAPH.sol";
import "../core/PrivacyPool.sol";

contract MockVerifier is IVerifier {
    bool public shouldPass = true;

    function setShouldPass(bool _pass) external {
        shouldPass = _pass;
    }

    function verifyProof(bytes calldata, uint256[] calldata) external view returns (bool) {
        return shouldPass;
    }
}

contract PrivacyPoolTest is Test {
    SeraphToken token;
    PrivacyPool pool;
    MockVerifier verifier;

    address treasury = address(0x111);
    address alice = address(0x222);
    address bob = address(0x333);

    function setUp() public {
        // Deploy Mock verifier
        verifier = new MockVerifier();

        // Deploy token
        token = new SeraphToken(address(0), treasury, address(0));

        // Deploy PrivacyPool
        pool = new PrivacyPool(
            address(token),
            treasury,
            address(verifier),
            address(0)
        );

        // Link pool on token
        vm.prank(treasury);
        token.setPrivacyPool(address(pool));

        // Mint initial tokens to alice for shielding tests
        vm.prank(treasury);
        token.mint(alice, 10_000e18);

        // Mint initial tokens to pool for unshielding tests
        vm.prank(treasury);
        token.mint(address(pool), 50_000e18);
    }

    function test_InitialMerkleRoot() public view {
        bytes32 root = pool.getLastRoot();
        assertTrue(root != bytes32(0), "Initial root should not be zero");
        assertTrue(pool.isKnownRoot(root), "Initial root should be recognized as known");
        assertEq(pool.nextLeafIndex(), 0, "Initial tree should have 0 leaves");
    }

    function test_Shield_DepositsTokensAndUpdatesTree() public {
        uint256 shieldAmount = 500e18;
        bytes32 commitment = keccak256("note_secret_commitment_1");
        bytes32 initialRoot = pool.getLastRoot();

        vm.startPrank(alice);
        token.approve(address(pool), shieldAmount);

        uint256 aliceBefore = token.balanceOf(alice);
        uint256 poolBefore = token.balanceOf(address(pool));

        uint32 leafIndex = pool.shield(shieldAmount, commitment, "");
        vm.stopPrank();

        assertEq(leafIndex, 0, "First leaf should be index 0");
        assertEq(pool.nextLeafIndex(), 1, "nextLeafIndex incremented");
        assertEq(token.balanceOf(alice), aliceBefore - shieldAmount, "Alice tokens deducted");
        assertEq(token.balanceOf(address(pool)), poolBefore + shieldAmount, "Pool received tokens");

        bytes32 newRoot = pool.getLastRoot();
        assertTrue(newRoot != initialRoot, "Root must change after insertion");
        assertTrue(pool.isKnownRoot(newRoot), "New root is recognized");
        assertTrue(pool.isKnownRoot(initialRoot), "Previous root remains valid in history buffer");
    }

    function test_Shield_TaxExempt() public {
        // Transfers into and out of PrivacyPool must have 0% sell tax
        uint256 shieldAmount = 1000e18;
        bytes32 commitment = keccak256("note_tax_exempt");

        vm.startPrank(alice);
        token.approve(address(pool), shieldAmount);
        pool.shield(shieldAmount, commitment, "");
        vm.stopPrank();

        // If untaxed, pool receives exactly 1000e18, alice loses exactly 1000e18
        assertEq(token.balanceOf(alice), 9_000e18, "No tax deducted from alice");
    }

    function test_MultipleShields_EvolveMerkleTree() public {
        vm.startPrank(alice);
        token.approve(address(pool), type(uint256).max);

        bytes32[] memory rootsHistory = new bytes32[](5);
        for (uint256 i = 0; i < 5; i++) {
            bytes32 commitment = keccak256(abi.encodePacked("note", i));
            pool.shield(100e18, commitment, "");
            rootsHistory[i] = pool.getLastRoot();
        }
        vm.stopPrank();

        assertEq(pool.nextLeafIndex(), 5, "5 leaves inserted");

        // Every historical root must still be known
        for (uint256 i = 0; i < 5; i++) {
            assertTrue(pool.isKnownRoot(rootsHistory[i]), "Historical root valid");
        }
    }

    function test_PrivateTransfer_ConsumesNullifiersAndInsertsOutputs() public {
        // Shield first to establish a root
        vm.startPrank(alice);
        token.approve(address(pool), 1000e18);
        pool.shield(1000e18, keccak256("input_note_1"), "");
        vm.stopPrank();

        bytes32 currentRoot = pool.getLastRoot();

        bytes32[] memory nullifiers = new bytes32[](2);
        nullifiers[0] = keccak256("nullifier_1");
        nullifiers[1] = keccak256("nullifier_2");

        bytes32[] memory commitments = new bytes32[](2);
        commitments[0] = keccak256("output_note_1");
        commitments[1] = keccak256("output_note_2");

        // Execute private transfer
        pool.privateTransfer(nullifiers, commitments, currentRoot, "");

        // Nullifiers must now be marked spent
        assertTrue(pool.nullified(nullifiers[0]), "Nullifier 1 spent");
        assertTrue(pool.nullified(nullifiers[1]), "Nullifier 2 spent");

        // Next leaf index advanced by 2
        assertEq(pool.nextLeafIndex(), 3, "1 deposit + 2 outputs = 3 leaves");
    }

    function test_PrivateTransfer_RevertsOnDoubleSpend() public {
        vm.startPrank(alice);
        token.approve(address(pool), 1000e18);
        pool.shield(1000e18, keccak256("input_note_1"), "");
        vm.stopPrank();

        bytes32 currentRoot = pool.getLastRoot();

        bytes32[] memory nullifiers = new bytes32[](1);
        nullifiers[0] = keccak256("nullifier_spent");

        bytes32[] memory commitments = new bytes32[](1);
        commitments[0] = keccak256("output_note_1");

        // First spend succeeds
        pool.privateTransfer(nullifiers, commitments, currentRoot, "");

        // Second spend with the same nullifier MUST revert
        bytes32 latestRoot = pool.getLastRoot();
        vm.expectRevert("PrivacyPool: nullifier already spent");
        pool.privateTransfer(nullifiers, commitments, latestRoot, "");
    }

    function test_PrivateTransfer_RevertsOnInvalidProof() public {
        vm.startPrank(alice);
        token.approve(address(pool), 1000e18);
        pool.shield(1000e18, keccak256("input_note_1"), "");
        vm.stopPrank();

        bytes32 currentRoot = pool.getLastRoot();

        bytes32[] memory nullifiers = new bytes32[](1);
        nullifiers[0] = keccak256("nullifier_bad_proof");

        bytes32[] memory commitments = new bytes32[](1);
        commitments[0] = keccak256("output_note_bad_proof");

        // Configure verifier to reject
        verifier.setShouldPass(false);

        vm.expectRevert("PrivacyPool: invalid proof");
        pool.privateTransfer(nullifiers, commitments, currentRoot, "bad_proof");
    }

    function test_Unshield_ReleasesTokensToRecipient() public {
        // Shield to advance root
        vm.startPrank(alice);
        token.approve(address(pool), 1000e18);
        pool.shield(1000e18, keccak256("unshield_note"), "");
        vm.stopPrank();

        bytes32 currentRoot = pool.getLastRoot();
        bytes32 nullifier = keccak256("unshield_nullifier_1");
        uint256 unshieldAmount = 300e18;

        uint256 bobBefore = token.balanceOf(bob);
        uint256 poolBefore = token.balanceOf(address(pool));

        pool.unshield(nullifier, unshieldAmount, bob, currentRoot, "");

        assertTrue(pool.nullified(nullifier), "Nullifier marked spent");
        assertEq(token.balanceOf(bob), bobBefore + unshieldAmount, "Bob received unshielded tokens");
        assertEq(token.balanceOf(address(pool)), poolBefore - unshieldAmount, "Pool balance decreased");
    }

    function test_Unshield_RevertsOnReusedNullifier() public {
        vm.startPrank(alice);
        token.approve(address(pool), 1000e18);
        pool.shield(1000e18, keccak256("unshield_note_double"), "");
        vm.stopPrank();

        bytes32 currentRoot = pool.getLastRoot();
        bytes32 nullifier = keccak256("unshield_nullifier_reuse");

        pool.unshield(nullifier, 100e18, bob, currentRoot, "");

        vm.expectRevert("PrivacyPool: nullifier already spent");
        pool.unshield(nullifier, 100e18, bob, currentRoot, "");
    }

    function test_Token_ApproveAndShieldWrapper() public {
        bytes32 commitment = keccak256("wrapper_shield");
        uint256 amount = 250e18;

        vm.prank(alice);
        token.approveAndShield(amount, commitment);

        assertEq(pool.nextLeafIndex(), 1, "Leaf inserted via token wrapper");
        assertTrue(pool.isKnownRoot(pool.getLastRoot()));
    }
}
