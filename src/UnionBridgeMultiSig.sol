// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "MultiSigLib/MultiSigLib.sol";

enum UnionResponseCode { SUCCESS, UNAUTHORIZED_CALLER, INVALID_VALUE, REQUEST_DISABLED, RELEASE_DISABLED, ENVIRONMENT_DISABLED, GENERIC_ERROR }

interface BridgeInterface {
    function increaseUnionBridgeLockingCap(uint256 newLockingCap) external returns (UnionResponseCode);
    function setUnionBridgeTransferPermissions(bool requestEnabled, bool releaseEnabled) external returns (UnionResponseCode);
}

contract UnionBridgeMultiSig {
    using MultiSigLib for MultiSigLib.State;

    event LockingCapIncreaseVoted(address indexed voter, uint256 newLockingCap);
    event LockingCapIncreased(uint256 newLockingCap);
    event TransferPermissionsVoted(address indexed voter, bool requestEnabled, bool releaseEnabled);
    event TransferPermissionsSet(bool requestEnabled, bool releaseEnabled);

    address payable public constant BRIDGE_ADDRESS = payable(0x0000000000000000000000000000000001000006);

    MultiSigLib.State private state;
    BridgeInterface private bridgeContract = BridgeInterface(BRIDGE_ADDRESS);

    struct ValueVote {
        uint256 votes;
        uint256 proposedAtVersion;
        mapping(bytes32 => bool) memberVoted;
    }

    // Locking cap voting (per-value)
    uint256 private lockingCapVotingVersion = 1;
    mapping(uint256 => ValueVote) private lockingCapVotesByValue;

    // Transfer permissions voting (per (requestEnabled,releaseEnabled))
    uint256 private transferPermissionsVotingVersion = 1;
    mapping(uint8 => ValueVote) private transferPermissionsVotesByKey;

    constructor(address[] memory initialMembers) {
        state.init(initialMembers);
    }

    modifier onlyMember() {
        require(MultiSigLib.isMember(state, msg.sender), "Sender is not a member.");
        _;
    }

    function voteToAddNewMember(address candidate) external onlyMember {
        state.voteToAddNewMember(candidate);
    }

    function voteToRemoveMember(address member) external onlyMember {
        state.voteToRemoveMember(member);
    }

    function voteToIncreaseUnionBridgeLockingCap(uint256 newLockingCap) external onlyMember {
        ValueVote storage valueVote = lockingCapVotesByValue[newLockingCap];

        if (valueVote.proposedAtVersion != lockingCapVotingVersion) {
            delete lockingCapVotesByValue[newLockingCap];
            valueVote = lockingCapVotesByValue[newLockingCap];
            valueVote.proposedAtVersion = lockingCapVotingVersion;
        }

        bytes32 voteKey = keccak256(abi.encodePacked(msg.sender, newLockingCap, valueVote.proposedAtVersion));
        require(!valueVote.memberVoted[voteKey], "Already voted for this locking cap in current version.");

        valueVote.memberVoted[voteKey] = true;
        valueVote.votes++;

        emit LockingCapIncreaseVoted(msg.sender, newLockingCap);

        if (valueVote.votes >= state.getThreshold()) {
            bridgeContract.increaseUnionBridgeLockingCap(newLockingCap);
            lockingCapVotingVersion++;
            emit LockingCapIncreased(newLockingCap);
        }
    }

    function voteToSetUnionBridgeTransferPermissions(bool requestEnabled, bool releaseEnabled) external onlyMember {
        uint8 permissionsKey = _packPermissionsKey(requestEnabled, releaseEnabled);
        ValueVote storage valueVote = transferPermissionsVotesByKey[permissionsKey];

        if (valueVote.proposedAtVersion != transferPermissionsVotingVersion) {
            delete transferPermissionsVotesByKey[permissionsKey];
            valueVote = transferPermissionsVotesByKey[permissionsKey];
            valueVote.proposedAtVersion = transferPermissionsVotingVersion;
        }

        bytes32 voteKey = keccak256(abi.encodePacked(msg.sender, permissionsKey, valueVote.proposedAtVersion));
        require(!valueVote.memberVoted[voteKey], "Already voted for these permissions in current version.");

        valueVote.memberVoted[voteKey] = true;
        valueVote.votes++;

        emit TransferPermissionsVoted(msg.sender, requestEnabled, releaseEnabled);

        if (valueVote.votes >= state.getThreshold()) {
            bridgeContract.setUnionBridgeTransferPermissions(requestEnabled, releaseEnabled);
            transferPermissionsVotingVersion++;
            emit TransferPermissionsSet(requestEnabled, releaseEnabled);
        }
    }

    function isMember(address who) external view returns (bool) {
        return MultiSigLib.isMember(state, who);
    }

    function getMembersCount() external view returns (uint256) {
        return state.getMembersCount();
    }

    function getThreshold() external view returns (uint256) {
        return state.getThreshold();
    }

    function getMultisigVersion() external view returns (uint256) {
        return state.getMultisigVersion();
    }

    function getAddNewMemberVotesForThisCandidate(address candidate) external view returns (uint256) {
        return state.getAddNewMemberVotesForThisCandidate(candidate);
    }

    function getRemoveMemberVotesForMember(address member) external view returns (uint256) {
        return state.getRemoveMemberVotesForMember(member);
    }

    function getAddNewMemberProposedAtVersion(address candidate) external view returns (uint256) {
        return state.getAddNewMemberProposedAtVersion(candidate);
    }

    function getRemoveMemberProposedAtVersion(address member) external view returns (uint256) {
        return state.getRemoveMemberProposedAtVersion(member);
    }

    function getLockingCapVotesFor(uint256 lockingCap) external view returns (uint256 votes, uint256 proposedAtVersion, uint256 currentVersion) {
        ValueVote storage valueVote = lockingCapVotesByValue[lockingCap];
        return (valueVote.votes, valueVote.proposedAtVersion, lockingCapVotingVersion);
    }

    function getTransferPermissionsVotesFor(bool requestEnabled, bool releaseEnabled) external view returns (uint256 votes, uint256 proposedAtVersion, uint256 currentVersion) {
        uint8 permissionsKey = _packPermissionsKey(requestEnabled, releaseEnabled);
        ValueVote storage valueVote = transferPermissionsVotesByKey[permissionsKey];
        return (valueVote.votes, valueVote.proposedAtVersion, transferPermissionsVotingVersion);
    }

    function amIAMember() external view returns (bool) {
        return MultiSigLib.isMember(state, msg.sender);
    }

    function _packPermissionsKey(bool requestEnabled, bool releaseEnabled) private pure returns (uint8) {
        return (requestEnabled ? uint8(1) : uint8(0)) | (releaseEnabled ? uint8(2) : uint8(0));
    }
}
