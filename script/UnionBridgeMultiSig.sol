// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {UnionBridgeMultiSig} from "../src/UnionBridgeMultiSig.sol";

contract UnionBridgeMultiSigScript is Script {
    UnionBridgeMultiSig public unionBridgeMultiSig;

    function setUp() public {}

    function run() public {

        vm.startBroadcast();

        address M1 = address(0x86fEa303737F5219d7b5E4f30Cb7268Bec1775Fa); // Generated with seed 'member1'
        address M2 = address(0xbD405055317EF6089a771008453365060BB97aC1); // Generated with seed 'member2'
        address M3 = address(0xeb1b36D046AC9d13E7547cd936D135fd9e8542Cd); // Generated with seed 'member3'

        address[] memory members = new address[](3);
        members[0] = M1;
        members[1] = M2;
        members[2] = M3;

        unionBridgeMultiSig = new UnionBridgeMultiSig(members);

        vm.stopBroadcast();
        
    }
}
