// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/UnionBridgeMultiSig.sol";

contract MockBridge is BridgeInterface {
    uint256 private lockingCap;
    bool public lastReq;
    bool public lastRel;

    function increaseUnionBridgeLockingCap(uint256 newLockingCap) external returns (UnionResponseCode) {
        lockingCap = newLockingCap;
        return UnionResponseCode.SUCCESS;
    }

    function getUnionBridgeLockingCap() external view returns (uint256) {
        return lockingCap;
    }

    function setUnionBridgeTransferPermissions(bool requestEnabled, bool releaseEnabled) external returns (UnionResponseCode) {
        lastReq = requestEnabled;
        lastRel = releaseEnabled;
        return UnionResponseCode.SUCCESS;
    }
}

contract UnionBridgeMultiSigTest is Test {

    address M1 = address(0x86fEa303737F5219d7b5E4f30Cb7268Bec1775Fa); // seed 'member1'
    address M2 = address(0xbD405055317EF6089a771008453365060BB97aC1); // seed 'member2'
    address M3 = address(0xeb1b36D046AC9d13E7547cd936D135fd9e8542Cd); // seed 'member3'
    address M4 = address(0xCbB27fd0bFbA64828063F11222AF8E8fe899D6CD); // seed 'member4'
    address NON = address(0x775dd06aAEd73791B44bE3d3f16fE5571B1709fA); // seed 'nonmember'
    address randomAddress = address(0xe899D4fE48da746223F9Ad56f1511FB146EC86fF); // seed 'randomAddress'

    UnionBridgeMultiSig unionBridgeMultiSig;
    MockBridge mockBridge;

    address constant BRIDGE_ADDR = 0x0000000000000000000000000000000001000006;

    function setUp() public {
        mockBridge = new MockBridge();
        // Inject mock code into the fixed BRIDGE_ADDRESS used by the contract
        vm.etch(BRIDGE_ADDR, address(mockBridge).code);

        address[] memory members = new address[](3);
        members[0] = M1;
        members[1] = M2;
        members[2] = M3;

        unionBridgeMultiSig = new UnionBridgeMultiSig(members);
    }

    function testInit() public view {
        assertEq(unionBridgeMultiSig.getMembersCount(), 3);
        assertEq(unionBridgeMultiSig.getThreshold(), 2);
        assertTrue(unionBridgeMultiSig.isMember(M1));
        assertTrue(unionBridgeMultiSig.isMember(M2));
        assertTrue(unionBridgeMultiSig.isMember(M3));
        assertFalse(unionBridgeMultiSig.isMember(M4));
    }

    function testLockingCapVoting_PerValueThreshold() public {

        uint256 cap = 10_000;

        vm.prank(M1);
        unionBridgeMultiSig.voteToIncreaseUnionBridgeLockingCap(cap);
        // Not enough votes yet
        assertEq(MockBridge(BRIDGE_ADDR).getUnionBridgeLockingCap(), 0);

        vm.prank(M2);
        unionBridgeMultiSig.voteToIncreaseUnionBridgeLockingCap(cap);
        // Reached threshold -> executes
        assertEq(MockBridge(BRIDGE_ADDR).getUnionBridgeLockingCap(), cap);

    }

    function testLockingCapVoting_CompetingValuesInvalidateOnExecute() public {

        // First finalize a cap to bump the cap-version

        vm.prank(M1);
        unionBridgeMultiSig.voteToIncreaseUnionBridgeLockingCap(111);

        vm.prank(M2);
        unionBridgeMultiSig.voteToIncreaseUnionBridgeLockingCap(111);

        assertEq(MockBridge(BRIDGE_ADDR).getUnionBridgeLockingCap(), 111);

        // New version: set up three competing values, each at threshold-1
        uint256 v1 = 200;
        uint256 v2 = 300;
        uint256 v3 = 400;

        vm.prank(M1);
        unionBridgeMultiSig.voteToIncreaseUnionBridgeLockingCap(v1);

        vm.prank(M2);
        unionBridgeMultiSig.voteToIncreaseUnionBridgeLockingCap(v2);

        vm.prank(M3);
        unionBridgeMultiSig.voteToIncreaseUnionBridgeLockingCap(v3);

        // Finalize v2 -> executes and bumps version, invalidating v1/v3 pending state
        vm.prank(M1);
        unionBridgeMultiSig.voteToIncreaseUnionBridgeLockingCap(v2);

        assertEq(MockBridge(BRIDGE_ADDR).getUnionBridgeLockingCap(), v2);

        // Now trying to "finish" old v1 with one more vote is actually first vote in the NEW version
        vm.prank(M2);
        unionBridgeMultiSig.voteToIncreaseUnionBridgeLockingCap(v1);

        assertEq(MockBridge(BRIDGE_ADDR).getUnionBridgeLockingCap(), v2);

        // Give v1 its second vote in the new version -> executes now
        vm.prank(M3);
        unionBridgeMultiSig.voteToIncreaseUnionBridgeLockingCap(v1);

        assertEq(MockBridge(BRIDGE_ADDR).getUnionBridgeLockingCap(), v1);
    }

    function testLockingCapVoting_NoDoubleVoteSameValueSameVersion() public {

        uint256 capValue = 777;

        vm.startPrank(M1);
        unionBridgeMultiSig.voteToIncreaseUnionBridgeLockingCap(capValue);

        vm.expectRevert(bytes("Already voted for this locking cap in current version."));

        unionBridgeMultiSig.voteToIncreaseUnionBridgeLockingCap(capValue);

        vm.stopPrank();

    }

    function testLockingCapVoting_MemberCanVoteAgainAfterVersionBump() public {

        uint256 valueA = 10;
        uint256 valueB = 20;

        vm.prank(M1);
        unionBridgeMultiSig.voteToIncreaseUnionBridgeLockingCap(valueA);

        vm.prank(M2);
        unionBridgeMultiSig.voteToIncreaseUnionBridgeLockingCap(valueA);

        assertEq(MockBridge(BRIDGE_ADDR).getUnionBridgeLockingCap(), valueA);

        // After version bump, member can vote again for a new value
        vm.prank(M1);
        unionBridgeMultiSig.voteToIncreaseUnionBridgeLockingCap(valueB);

        vm.prank(M2);
        unionBridgeMultiSig.voteToIncreaseUnionBridgeLockingCap(valueB);

        assertEq(MockBridge(BRIDGE_ADDR).getUnionBridgeLockingCap(), valueB);

    }

    function testTransferPermissionsVoting_PerTupleThreshold() public {

        bool req = true;
        bool rel = false;

        vm.prank(M1);
        unionBridgeMultiSig.voteToSetUnionBridgeTransferPermissions(req, rel);

        // Not enough votes yet
        assertEq(MockBridge(BRIDGE_ADDR).lastReq(), false);
        assertEq(MockBridge(BRIDGE_ADDR).lastRel(), false);

        vm.prank(M2);
        unionBridgeMultiSig.voteToSetUnionBridgeTransferPermissions(req, rel);

        // Reached threshold -> executes
        assertEq(MockBridge(BRIDGE_ADDR).lastReq(), req);
        assertEq(MockBridge(BRIDGE_ADDR).lastRel(), rel);

    }

    function testTransferPermissionsVoting_CompetingTuplesInvalidateOnExecute() public {

        // First finalize (false,false) to bump version
        vm.prank(M1);
        unionBridgeMultiSig.voteToSetUnionBridgeTransferPermissions(false, false);

        vm.prank(M2);
        unionBridgeMultiSig.voteToSetUnionBridgeTransferPermissions(false, false);

        assertEq(MockBridge(BRIDGE_ADDR).lastReq(), false);
        assertEq(MockBridge(BRIDGE_ADDR).lastRel(), false);

        // Competing tuples: each at threshold-1
        vm.prank(M1);
        unionBridgeMultiSig.voteToSetUnionBridgeTransferPermissions(true, true);   // T1: (true,true)

        vm.prank(M2);
        unionBridgeMultiSig.voteToSetUnionBridgeTransferPermissions(false, true);  // T2: (false,true)

        // Finalize T1 with member3
        vm.prank(M3);
        unionBridgeMultiSig.voteToSetUnionBridgeTransferPermissions(true, true);

        assertEq(MockBridge(BRIDGE_ADDR).lastReq(), true);
        assertEq(MockBridge(BRIDGE_ADDR).lastRel(), true);

        // After version bump, the old T2 needs 2 fresh votes; one vote won't execute
        vm.prank(M1);
        unionBridgeMultiSig.voteToSetUnionBridgeTransferPermissions(false, true);

        assertEq(MockBridge(BRIDGE_ADDR).lastReq(), true);
        assertEq(MockBridge(BRIDGE_ADDR).lastRel(), true);

        // Second vote in the new version -> executes
        vm.prank(M3);
        unionBridgeMultiSig.voteToSetUnionBridgeTransferPermissions(false, true);

        assertEq(MockBridge(BRIDGE_ADDR).lastReq(), false);
        assertEq(MockBridge(BRIDGE_ADDR).lastRel(), true);
        
    }

    function testTransferPermissionsVoting_NoDoubleVoteSameTupleSameVersion() public {

        vm.startPrank(M2);
        unionBridgeMultiSig.voteToSetUnionBridgeTransferPermissions(true, false);

        vm.expectRevert(bytes("Already voted for these permissions in current version."));

        unionBridgeMultiSig.voteToSetUnionBridgeTransferPermissions(true, false);

        vm.stopPrank();

    }

    function testOnlyMembersCanVote() public {

        vm.expectRevert(bytes("Sender is not a member."));
        vm.prank(NON);
        unionBridgeMultiSig.voteToIncreaseUnionBridgeLockingCap(123);

        vm.expectRevert(bytes("Sender is not a member."));
        vm.prank(NON);
        unionBridgeMultiSig.voteToSetUnionBridgeTransferPermissions(true, false);
        
    }
}
