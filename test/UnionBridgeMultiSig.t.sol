// test/UBRegression.t.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/UnionBridgeMultiSig.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Optional tiny interface for new methods added in later impls
interface IVersionTag { function versionTag() external view returns (string memory); }

contract UBRegression is Test {
    // Members
    address M1 = address(0x86fEa303737F5219d7b5E4f30Cb7268Bec1775Fa);
    address M2 = address(0xbD405055317EF6089a771008453365060BB97aC1);
    address M3 = address(0xeb1b36D046AC9d13E7547cd936D135fd9e8542Cd);

    // Fixed bridge address that the contract expects
    address constant BRIDGE_ADDR = 0x0000000000000000000000000000000001000006;

    // Proxy we interact with
    UnionBridgeMultiSig proxy;

    // Mock bridge
    MockBridge mockBridge;

    // ---------- Fixture ----------
    function _deployV1AndProxy(address owner) internal returns (UnionBridgeMultiSig) {
        // Etch mock bridge code at fixed address
        mockBridge = new MockBridge();
        vm.etch(BRIDGE_ADDR, address(mockBridge).code);

        // Initial members for both groups
        address[] memory locking = new address[](3);
        locking[0] = M1; locking[1] = M2; locking[2] = M3;

        address[] memory perms = new address[](3);
        perms[0] = M1; perms[1] = M2; perms[2] = M3;

        // Deploy implementation
        UnionBridgeMultiSig implementation = new UnionBridgeMultiSig();

        // Encode initialize
        bytes memory initData = abi.encodeWithSelector(
            UnionBridgeMultiSig.initialize.selector,
            locking,
            perms,
            owner
        );

        // Deploy proxy
        ERC1967Proxy pxy = new ERC1967Proxy(address(implementation), initData);
        proxy = UnionBridgeMultiSig(payable(address(pxy)));
        return proxy;
    }

    // ---------- Upgrade helper (uses your wrapper) ----------
    function _upgradeTo(address newImpl, address owner) internal {
        vm.prank(owner);
        proxy.upgradeToNewImplementation(newImpl);
    }

    // ---------- “Whole suite” of reusable checks ----------
    function _assertInit() internal view {
        assertEq(proxy.getLockingCapMembersCount(), 3);
        assertEq(proxy.getLockingCapThreshold(), 2);
        assertEq(proxy.getTransferPermissionsMembersCount(), 3);
        assertEq(proxy.getTransferPermissionsThreshold(), 2);
    }

    function _assertLockingCapVoting() internal {
        // baseline: set cap = 111 with 2 votes
        vm.prank(M1); proxy.voteToIncreaseUnionBridgeLockingCap(111);
        vm.prank(M2); proxy.voteToIncreaseUnionBridgeLockingCap(111);
        assertEq(MockBridge(BRIDGE_ADDR).getUnionBridgeLockingCap(), 111);

        // competing values: 200, 300, 400 each at threshold-1
        vm.prank(M1); proxy.voteToIncreaseUnionBridgeLockingCap(200);
        vm.prank(M2); proxy.voteToIncreaseUnionBridgeLockingCap(300);
        vm.prank(M3); proxy.voteToIncreaseUnionBridgeLockingCap(400);

        // finalize 300
        vm.prank(M1); proxy.voteToIncreaseUnionBridgeLockingCap(300);
        assertEq(MockBridge(BRIDGE_ADDR).getUnionBridgeLockingCap(), 300);
    }

    function _assertTransferPermissionsVoting() internal {
        // set (true,false)
        vm.prank(M1); proxy.voteToSetUnionBridgeTransferPermissions(true, false);
        vm.prank(M2); proxy.voteToSetUnionBridgeTransferPermissions(true, false);
        assertTrue(MockBridge(BRIDGE_ADDR).lastReq());
        assertFalse(MockBridge(BRIDGE_ADDR).lastRel());

        // competing tuples
        vm.prank(M1); proxy.voteToSetUnionBridgeTransferPermissions(true, true);
        vm.prank(M2); proxy.voteToSetUnionBridgeTransferPermissions(false, true);
        vm.prank(M3); proxy.voteToSetUnionBridgeTransferPermissions(true, true);
        assertTrue(MockBridge(BRIDGE_ADDR).lastReq());
        assertTrue(MockBridge(BRIDGE_ADDR).lastRel());
    }

    function _assertNoDoubleVotes() internal {
        // lock cap double vote
        vm.startPrank(M1);
        proxy.voteToIncreaseUnionBridgeLockingCap(777);
        vm.expectRevert(UnionBridgeMultiSig.AlreadyVoted.selector);
        proxy.voteToIncreaseUnionBridgeLockingCap(777);
        vm.stopPrank();

        // perms double vote
        vm.startPrank(M2);
        proxy.voteToSetUnionBridgeTransferPermissions(true, false);
        vm.expectRevert(UnionBridgeMultiSig.AlreadyVoted.selector);
        proxy.voteToSetUnionBridgeTransferPermissions(true, false);
        vm.stopPrank();
    }

    function _assertOwnerOnlyUpgrade(address nonOwner, address owner) internal {
        // Prepare targets first
        address implForNonOwner = address(new UnionBridgeMultiSig());
        address implForOwner    = address(new UnionBridgeMultiSig());

        // --- Non-owner cannot upgrade ---
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", nonOwner));
        vm.prank(nonOwner);
        proxy.upgradeToNewImplementation(implForNonOwner);

        // --- Owner can upgrade ---
        vm.prank(owner);
        proxy.upgradeToNewImplementation(implForOwner);
    }

    // ---------- The single “runner” test ----------
    function test_RunFullSuite_AfterEachUpgrade() public {
        address owner = M1;

        // 1) Deploy V1 + proxy
        _deployV1AndProxy(owner);

        // Take a snapshot for V1 run
        uint256 snapV1 = vm.snapshotState();
        {
            _assertInit();
            _assertLockingCapVoting();
            _assertTransferPermissionsVoting();
            _assertNoDoubleVotes();
            _assertOwnerOnlyUpgrade(address(0xDEAD), owner);
        }
        vm.revertTo(snapV1);

        // 2) Deploy V2 (extends V1 with versionTag) and upgrade
        UnionBridgeMultiSigV2 implV2 = new UnionBridgeMultiSigV2();
        _upgradeTo(address(implV2), owner);

        // Snapshot for V2 run
        uint256 snapV2 = vm.snapshotState();
        {
            // Optional: check new surface
            assertEq(IVersionTag(address(proxy)).versionTag(), "v2");

            _assertInit();
            _assertLockingCapVoting();
            _assertTransferPermissionsVoting();
            _assertNoDoubleVotes();
            _assertOwnerOnlyUpgrade(address(0xBEEF), owner);
        }
        vm.revertTo(snapV2);

        // 3) Deploy V3 and upgrade
        UnionBridgeMultiSigV3 implV3 = new UnionBridgeMultiSigV3();
        _upgradeTo(address(implV3), owner);

        // Snapshot for V3 run
        uint256 snapV3 = vm.snapshotState();
        {
            assertEq(IVersionTag(address(proxy)).versionTag(), "v3");

            _assertInit();
            _assertLockingCapVoting();
            _assertTransferPermissionsVoting();
            _assertNoDoubleVotes();
            _assertOwnerOnlyUpgrade(address(0xFEED), owner);
        }
        vm.revertTo(snapV3);
    }
}

/* ====== Minimal mock bridge (same as your other tests) ====== */
contract MockBridge is BridgeInterface {
    uint256 private lockingCap;
    bool public lastReq;
    bool public lastRel;

    function increaseUnionBridgeLockingCap(uint256 newLockingCap) external returns (UnionResponseCode) {
        lockingCap = newLockingCap;
        return UnionResponseCode.SUCCESS;
    }
    function getUnionBridgeLockingCap() external view returns (uint256) { return lockingCap; }
    function setUnionBridgeTransferPermissions(bool requestEnabled, bool releaseEnabled) external returns (UnionResponseCode) {
        lastReq = requestEnabled; lastRel = releaseEnabled; return UnionResponseCode.SUCCESS;
    }
}

/* ====== Test-only upgraded impls that preserve storage layout ====== */
contract UnionBridgeMultiSigV2 is UnionBridgeMultiSig {
    function versionTag() external pure returns (string memory) { return "v2"; }
}
contract UnionBridgeMultiSigV3 is UnionBridgeMultiSig {
    function versionTag() external pure returns (string memory) { return "v3"; }
}
