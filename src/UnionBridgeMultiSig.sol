// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IERC1822ProxiableUpgradeableMinimal {
    function proxiableUUID() external view returns (bytes32);
}

import "MultiSigLib/MultiSigLib.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "openzeppelin-contracts/interfaces/draft-IERC1822.sol";
import "openzeppelin-contracts/interfaces/IERC1967.sol";

/**
 * @notice Response codes returned by the external BridgeInterface.
 */
enum UnionResponseCode {
    SUCCESS,
    UNAUTHORIZED_CALLER,
    INVALID_VALUE,
    REQUEST_DISABLED,
    RELEASE_DISABLED,
    ENVIRONMENT_DISABLED,
    GENERIC_ERROR
}

/**
 * @notice Minimal interface of the external bridge the multisig governs.
 */
interface BridgeInterface {
    function increaseUnionBridgeLockingCap(uint256 newLockingCap) external returns (UnionResponseCode);
    function setUnionBridgeTransferPermissions(bool requestEnabled, bool releaseEnabled) external returns (UnionResponseCode);
}

/**
 * @title UnionBridgeMultiSig
 * @notice Upgradeable governance contract that manages two *independent* multisig groups:
 *         1) A multisig for increasing the Bridge locking cap.
 *         2) A multisig for setting the Bridge transfer permissions.
 *         Each group has its own membership, threshold, and proposal/versioning space.
 *         Per-value voting uses a "version" bump to invalidate other in-flight values once one passes.
 */
contract UnionBridgeMultiSig is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    using MultiSigLib for MultiSigLib.State;

    error OnlySigner();
    error AlreadyVoted();
    error NotInitialized();

    event LockingCapIncreaseVoted(address indexed voter, uint256 newLockingCap);
    event IncreaseUnionBridgeLockingCapCalled(uint256 newLockingCap, UnionResponseCode responseCode);
    event TransferPermissionsVoted(address indexed voter, bool requestEnabled, bool releaseEnabled);
    event SetUnionBridgeTransferPermissionsCalled(bool requestEnabled, bool releaseEnabled, UnionResponseCode responseCode);

    /// @notice Fixed bridge address; code is expected at this address (can be mocked in tests).
    address payable public constant BRIDGE_ADDRESS =
        payable(0x0000000000000000000000000000000001000006);

    BridgeInterface private bridgeContract;

    /// @notice Multisig group that governs increasing the Bridge locking cap.
    MultiSigLib.State private lockingCapState;

    /// @notice Multisig group that governs setting the Bridge transfer permissions.
    MultiSigLib.State private transferPermissionsState;

    /**
     * @dev Tracks votes for a specific proposal value within a given "voting version".
     *      Each key (value) maps to its own ValueVote which prevents double-voting via a unique vote key.
     */
    struct ValueVote {
        uint256 votes;
        uint256 proposedAtVersion;
        mapping(bytes32 => bool) memberVoted;
    }

    /// @notice Current version for locking-cap proposals; bumping invalidates pending alternative values.
    uint256 private lockingCapVotingVersion;

    /// @notice Per-value votes for locking-cap proposals: lockingCapValue => ValueVote.
    mapping(uint256 => ValueVote) private lockingCapVotesByValue;

    /// @notice Current version for transfer-permissions tuples; bumping invalidates pending alternatives.
    uint256 private transferPermissionsVotingVersion;
    
    /// @notice Per-tuple votes for transfer-permissions: permissionsKey => ValueVote.
    mapping(uint8 => ValueVote) private transferPermissionsVotesByKey;

    /// @dev Local initialization flag to guard all external entrypoints pre-initialize.
    bool private _isInitialized;

    /**
     * @notice Initializes the contract with two independent membership sets and an owner.
     * @dev This replaces a constructor for upgradeable contracts.
     * @param initialLockingCapMembers The initial members of the locking-cap multisig group.
     * @param initialTransferPermissionsMembers The initial members of the transfer-permissions multisig group.
     * @param initialOwner The initial owner (authorizes UUPS upgrades).
     */
    function initialize(
        address[] memory initialLockingCapMembers,
        address[] memory initialTransferPermissionsMembers,
        address initialOwner
    ) public initializer {
        __Ownable_init(initialOwner);
        __UUPSUpgradeable_init();

        bridgeContract = BridgeInterface(BRIDGE_ADDRESS);

        lockingCapState.init(initialLockingCapMembers);
        transferPermissionsState.init(initialTransferPermissionsMembers);

        lockingCapVotingVersion = 1;
        transferPermissionsVotingVersion = 1;

        _isInitialized = true;
    }

    /**
     * @notice UUPS authorization hook — restricts upgrades to the owner.
     * @param newImplementation Address of the new implementation.
     */
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}

    /// @dev Ensures the contract has been initialized (local flag).
    modifier onlyInitialized() {
        if (!_isInitialized) {
            revert NotInitialized();
        }
        _;
    }

    /// @notice Owner-only upgrade entrypoint (used by tests/scripts).
    /// Relies on UUPS to verify compatibility and perform the upgrade.
    function upgradeToNewImplementation(address newImplementation)
        external
        onlyInitialized
        onlyOwner
    {
        upgradeToAndCall(newImplementation, "");
    }

    /**
     * @dev Restricts a function so that only members of the locking-cap multisig group can call it.
     */
    modifier onlyLockingCapMember() {
        if (!MultiSigLib.isMember(lockingCapState, msg.sender)) {
            revert OnlySigner();
        }
        _;
    }

    /**
     * @dev Restricts a function so that only members of the transfer-permissions multisig group can call it.
     */
    modifier onlyTransferPermissionsMember() {
        if (!MultiSigLib.isMember(transferPermissionsState, msg.sender)) {
            revert OnlySigner();
        }
        _;
    }

    // ---------------- Membership — Locking Cap ----------------

    /// @notice Proposes and votes to add a new member to the locking-cap multisig group.
    function voteToAddLockingCapMember(address candidate)
        external
        onlyInitialized
        onlyLockingCapMember
    {
        lockingCapState.voteToAddNewMember(candidate);
    }

    /// @notice Proposes and votes to remove a member from the locking-cap multisig group.
    function voteToRemoveLockingCapMember(address member)
        external
        onlyInitialized
        onlyLockingCapMember
    {
        lockingCapState.voteToRemoveMember(member);
    }

    // ------------- Membership — Transfer Permissions ----------

    /// @notice Proposes and votes to add a new member to the transfer-permissions multisig group.
    function voteToAddTransferPermissionsMember(address candidate)
        external
        onlyInitialized
        onlyTransferPermissionsMember
    {
        transferPermissionsState.voteToAddNewMember(candidate);
    }

    /// @notice Proposes and votes to remove a member from the transfer-permissions multisig group.
    function voteToRemoveTransferPermissionsMember(address member)
        external
        onlyInitialized
        onlyTransferPermissionsMember
    {
        transferPermissionsState.voteToRemoveMember(member);
    }

    // ---------------- Action — Locking Cap --------------------

    function lockingCapValueVoteHasBeenOutdated(ValueVote storage valueVote) internal view returns (bool) {
        return valueVote.proposedAtVersion != lockingCapVotingVersion;
    }

    /// @notice Vote for a specific locking cap value; executes and bumps version once threshold is reached.
    function voteToIncreaseUnionBridgeLockingCap(uint256 newLockingCap)
        external
        onlyInitialized
        onlyLockingCapMember
    {
        ValueVote storage valueVote = lockingCapVotesByValue[newLockingCap];

        if (lockingCapValueVoteHasBeenOutdated(valueVote)) {
            delete lockingCapVotesByValue[newLockingCap];
            valueVote.proposedAtVersion = lockingCapVotingVersion;
        }

        bytes32 voteKey =
            keccak256(abi.encodePacked(msg.sender, newLockingCap, valueVote.proposedAtVersion));

        if (valueVote.memberVoted[voteKey]) {
            revert AlreadyVoted();
        }

        valueVote.memberVoted[voteKey] = true;
        valueVote.votes += 1;

        emit LockingCapIncreaseVoted(msg.sender, newLockingCap);

        if (valueVote.votes >= lockingCapState.getThreshold()) {
            lockingCapVotingVersion += 1;
            UnionResponseCode responseCode = bridgeContract.increaseUnionBridgeLockingCap(newLockingCap);
            emit IncreaseUnionBridgeLockingCapCalled(newLockingCap, responseCode);
        }
    }

    // -------- Action — Transfer Permissions (tuple) ----------

    function transferPermissionsValueVoteHasBeenOutdated(ValueVote storage valueVote) internal view returns (bool) {
        return valueVote.proposedAtVersion != transferPermissionsVotingVersion;
    }

    /// @notice Vote for a `(requestEnabled, releaseEnabled)` tuple; executes and bumps version once threshold is reached.
    function voteToSetUnionBridgeTransferPermissions(
        bool requestEnabled,
        bool releaseEnabled
    ) external onlyInitialized onlyTransferPermissionsMember {
        uint8 permissionsKey = _packPermissionsKey(requestEnabled, releaseEnabled);
        ValueVote storage valueVote = transferPermissionsVotesByKey[permissionsKey];

        if (transferPermissionsValueVoteHasBeenOutdated(valueVote)) {
            delete transferPermissionsVotesByKey[permissionsKey];
            valueVote.proposedAtVersion = transferPermissionsVotingVersion;
        }

        bytes32 voteKey =
            keccak256(abi.encodePacked(msg.sender, permissionsKey, valueVote.proposedAtVersion));

        if (valueVote.memberVoted[voteKey]) {
            revert AlreadyVoted();
        }

        valueVote.memberVoted[voteKey] = true;
        valueVote.votes += 1;

        emit TransferPermissionsVoted(msg.sender, requestEnabled, releaseEnabled);

        if (valueVote.votes >= transferPermissionsState.getThreshold()) {
            transferPermissionsVotingVersion += 1;
            UnionResponseCode responseCode = bridgeContract.setUnionBridgeTransferPermissions(requestEnabled, releaseEnabled);
            emit SetUnionBridgeTransferPermissionsCalled(requestEnabled, releaseEnabled, responseCode);
        }
    }

    // ---------------- Views — Locking Cap ---------------------

    function isLockingCapMember(address who) external view onlyInitialized returns (bool) {
        return MultiSigLib.isMember(lockingCapState, who);
    }

    function getLockingCapMembersCount() external view onlyInitialized returns (uint256) {
        return lockingCapState.getMembersCount();
    }

    function getLockingCapThreshold() external view onlyInitialized returns (uint256) {
        return lockingCapState.getThreshold();
    }

    function getLockingCapMultisigVersion() external view onlyInitialized returns (uint256) {
        return lockingCapState.getMultisigVersion();
    }

    function getLockingCapAddNewMemberVotesForThisCandidate(address candidate)
        external
        view
        onlyInitialized
        returns (uint256)
    {
        return lockingCapState.getAddNewMemberVotesForThisCandidate(candidate);
    }

    function getLockingCapRemoveMemberVotesForMember(address member)
        external
        view
        onlyInitialized
        returns (uint256)
    {
        return lockingCapState.getRemoveMemberVotesForMember(member);
    }

    function getLockingCapAddNewMemberProposedAtVersion(address candidate)
        external
        view
        onlyInitialized
        returns (uint256)
    {
        return lockingCapState.getAddNewMemberProposedAtVersion(candidate);
    }

    function getLockingCapRemoveMemberProposedAtVersion(address member)
        external
        view
        onlyInitialized
        returns (uint256)
    {
        return lockingCapState.getRemoveMemberProposedAtVersion(member);
    }

    function getLockingCapVotesFor(uint256 lockingCap)
        external
        view
        onlyInitialized
        returns (uint256 votes)
    {
        ValueVote storage valueVote = lockingCapVotesByValue[lockingCap];
        return valueVote.votes;
    }

    // -------- Views — Transfer Permissions (tuple) -----------

    function isTransferPermissionsMember(address who) external view onlyInitialized returns (bool) {
        return MultiSigLib.isMember(transferPermissionsState, who);
    }

    function getTransferPermissionsMembersCount() external view onlyInitialized returns (uint256) {
        return transferPermissionsState.getMembersCount();
    }

    function getTransferPermissionsThreshold() external view onlyInitialized returns (uint256) {
        return transferPermissionsState.getThreshold();
    }

    function getTransferPermissionsMultisigVersion() external view onlyInitialized returns (uint256) {
        return transferPermissionsState.getMultisigVersion();
    }

    function getTransferPermissionsAddNewMemberVotesForThisCandidate(address candidate)
        external
        view
        onlyInitialized
        returns (uint256)
    {
        return transferPermissionsState.getAddNewMemberVotesForThisCandidate(candidate);
    }

    function getTransferPermissionsRemoveMemberVotesForMember(address member)
        external
        view
        onlyInitialized
        returns (uint256)
    {
        return transferPermissionsState.getRemoveMemberVotesForMember(member);
    }

    function getTransferPermissionsAddNewMemberProposedAtVersion(address candidate)
        external
        view
        onlyInitialized
        returns (uint256)
    {
        return transferPermissionsState.getAddNewMemberProposedAtVersion(candidate);
    }

    function getTransferPermissionsRemoveMemberProposedAtVersion(address member)
        external
        view
        onlyInitialized
        returns (uint256)
    {
        return transferPermissionsState.getRemoveMemberProposedAtVersion(member);
    }

    function getTransferPermissionsVotesFor(bool requestEnabled, bool releaseEnabled)
        external
        view
        onlyInitialized
        returns (uint256 votes)
    {
        uint8 permissionsKey = _packPermissionsKey(requestEnabled, releaseEnabled);
        ValueVote storage valueVote = transferPermissionsVotesByKey[permissionsKey];
        return valueVote.votes;
    }

    /**
     * @dev Packs a `(requestEnabled, releaseEnabled)` tuple into a compact key:
     *      0b01 for requestEnabled, 0b10 for releaseEnabled. Combined via bitwise OR.
     */
    function _packPermissionsKey(bool requestEnabled, bool releaseEnabled)
        private
        pure
        returns (uint8)
    {
        uint8 key = 0;
        if (requestEnabled) {
            key |= 0x01;
        }
        if (releaseEnabled) {
            key |= 0x02;
        }
        return key;
    }

    // Storage gap for future upgrades
    uint256[44] private __gap; // reduced by 1 due to _isInitialized
}
