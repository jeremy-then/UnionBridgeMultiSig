// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import "forge-std/console2.sol";

import {UnionBridgeMultiSig} from "../src/UnionBridgeMultiSig.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract UnionBridgeMultiSigScript is Script {
    function run() public {
        uint256 deployerPK = vm.envOr("PRIVATE_KEY", uint256(0));
        address owner = vm.envOr("OWNER", address(0x86fEa303737F5219d7b5E4f30Cb7268Bec1775Fa));

        address M1 = address(0x86fEa303737F5219d7b5E4f30Cb7268Bec1775Fa);
        address M2 = address(0xbD405055317EF6089a771008453365060BB97aC1);
        address M3 = address(0xeb1b36D046AC9d13E7547cd936D135fd9e8542Cd);

        address [] memory lockingMembers = new address[](3);
        lockingMembers[0] = M1;
        lockingMembers[1] = M2;
        lockingMembers[2] = M3;

        address [] memory transferMembers = new address[](3);
        transferMembers[0] = M1;
        transferMembers[1] = M2;
        transferMembers[2] = M3;

        if (deployerPK == 0) {
            console2.log("Warning: PRIVATE_KEY not set; running without broadcast.");
        }

        vm.startBroadcast(deployerPK);

        // Deploy implementation
        UnionBridgeMultiSig implementation = new UnionBridgeMultiSig();

        // Encode initialize(lockingMembers, transferMembers, owner)
        bytes memory initData = abi.encodeWithSelector(
            UnionBridgeMultiSig.initialize.selector,
            lockingMembers,
            transferMembers,
            owner
        );

        // Deploy ERC1967 proxy pointing to the implementation
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);

        // Cast to contract type for convenience
        UnionBridgeMultiSig u = UnionBridgeMultiSig(payable(address(proxy)));

        vm.stopBroadcast();

        console2.log("Implementation:", address(implementation));
        console2.log("Proxy:", address(u));
        console2.log("Owner:", u.owner());
        console2.log("LockingCap members:", u.getLockingCapMembersCount());
        console2.log("TransferPermissions members:", u.getTransferPermissionsMembersCount());
    }
}
