// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../src/UnionBridgeMultiSig.sol";

/* ====== Same MockBridge used elsewhere ====== */
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

contract InitializationGuardTest is Test {
    address M1 = address(0x86fEa303737F5219d7b5E4f30Cb7268Bec1775Fa);
    address M2 = address(0xbD405055317EF6089a771008453365060BB97aC1);
    address M3 = address(0xeb1b36D046AC9d13E7547cd936D135fd9e8542Cd);

    address constant BRIDGE_ADDR = 0x0000000000000000000000000000000001000006;

    MockBridge mockBridge;

    function setUp() public {
        mockBridge = new MockBridge();
        vm.etch(BRIDGE_ADDR, address(mockBridge).code);
    }

    function _members() internal pure returns (address[] memory a) {
        a = new address[](3);
        a[0] = address(0x86fEa303737F5219d7b5E4f30Cb7268Bec1775Fa);
        a[1] = address(0xbD405055317EF6089a771008453365060BB97aC1);
        a[2] = address(0xeb1b36D046AC9d13E7547cd936D135fd9e8542Cd);
    }

    /// @notice Calling any guarded function on an *uninitialized implementation* should revert NotInitialized().
    function test_UninitializedImplementation_RevertsOnCalls() public {
        UnionBridgeMultiSig impl = new UnionBridgeMultiSig();

        // Static (view) also reverts due to onlyInitialized on views:
        vm.expectRevert(UnionBridgeMultiSig.NotInitialized.selector);
        UnionBridgeMultiSig(address(impl)).getLockingCapMembersCount();

        // Voting reverts
        vm.expectRevert(UnionBridgeMultiSig.NotInitialized.selector);
        UnionBridgeMultiSig(address(impl)).voteToIncreaseUnionBridgeLockingCap(123);

        // Owner-only upgrade also reverts because not initialized
        vm.expectRevert(UnionBridgeMultiSig.NotInitialized.selector);
        UnionBridgeMultiSig(address(impl)).upgradeToNewImplementation(address(impl));
    }

    /// @notice Once initialized via proxy, the same calls should pass (modulo membership).
    function test_ProxyInitialized_AllowsCalls() public {
        // Deploy implementation
        UnionBridgeMultiSig implementation = new UnionBridgeMultiSig();

        // Deploy proxy with initialize
        bytes memory initData = abi.encodeWithSelector(
            UnionBridgeMultiSig.initialize.selector,
            _members(), // locking-cap members
            _members(), // transfer-permissions members
            M1          // owner
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        UnionBridgeMultiSig u = UnionBridgeMultiSig(payable(address(proxy)));

        // Views do not revert
        assertEq(u.getLockingCapMembersCount(), 3);
        assertEq(u.getTransferPermissionsMembersCount(), 3);

        // A member can vote successfully
        vm.prank(M1);
        u.voteToIncreaseUnionBridgeLockingCap(111);

        // Owner can call upgrade entrypoint (it will run but do nothing meaningful since impl==newimpl)
        vm.prank(M1);
        u.upgradeToNewImplementation(address(implementation));
    }
}
