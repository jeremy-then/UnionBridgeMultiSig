# UnionBridgeMultiSig

`UnionBridgeMultiSig` is a Solidity contract that uses [MultiSigLib](https://github.com/jeremy-then/MultiSigLib) to provide **membership-based majority voting** for managing Union Bridge parameters.  
It ensures only authorized members can vote on sensitive bridge operations such as increasing the locking cap or changing transfer permissions.

---

## Features

- **MultiSig governance** (via MultiSigLib):
  - Vote to **add/remove members**
  - Strict majority threshold (`floor(n/2) + 1`)
  - Prevents duplicate votes per proposal
  - Blocks removals if result would drop members < 3
- **Bridge integration**:
  - Vote to increase the **locking cap**
  - Vote to set **transfer permissions**
- **Versioning**:
  - Every membership change increments the multisig version
- **Events**:
  - Emitted for every membership or bridge governance action

---

## Installation

Clone your repo and install dependencies:

```bash
# install foundry deps
forge install jeremy-then/MultiSigLib
forge install foundry-rs/forge-std
```

---

## Usage

### Deploy

Deploy with an initial set of **≥ 3 unique addresses**:

```solidity
constructor(address[] memory initialMembers)
```

Example (Remix / Anvil):

```json
[
  "0x5B38Da6a701c568545dCfcB03FcB875f56beddC4",
  "0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2",
  "0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db"
]
```

---

### Membership Management

- **Vote to add a new member**
  ```solidity
  voteToAddNewMember(address candidate)
  ```
- **Vote to remove an existing member**
  ```solidity
  voteToRemoveMember(address member)
  ```

---

### Bridge Operations

- **Vote to increase the locking cap**
  ```solidity
  voteToIncreaseUnionBridgeLockingCap(uint256 newLockingCap)
  ```
- **Vote to change transfer permissions**
  ```solidity
  voteToSetUnionBridgeTransferPermissions(bool requestEnabled, bool releaseEnabled)
  ```

---

### Views

- `isMember(address who) → bool`  
- `getMembersCount() → uint256`  
- `getThreshold() → uint256`  
- `getMultisigVersion() → uint256`  
- `getNewMemberVotesForThisCandidate(address candidate) → uint256`  
- `getRemoveMemberVotesForThisMember(address member) → uint256`  
- `amIAMember() → bool`  
- `getLockingCapVotes() → uint256`  
- `getTransferPermissionsVotes() → uint256`  

---

## Testing

This project includes Foundry tests (`test/UnionBridgeMultiSig.t.sol`) with a `MockBridge` injected at the fixed bridge address via `vm.etch`.

Run tests:

```bash
forge test -vv
```

---

## License

MIT
