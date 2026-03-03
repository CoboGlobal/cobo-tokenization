// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

import {Script, console2 as console} from "forge-std/Script.sol";
import {MockERC20} from "../test/Fund/mocks/MockERC20.sol";

/// @title DeployMockERC20 - Deploy MockERC20 token for testing
/// @dev Run: forge script script/DeployMockERC20.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
contract DeployMockERC20 is Script {
    function run() public {
        vm.startBroadcast();

        // Deploy Tether Gold (XAUT) mock token
        MockERC20 xaut = new MockERC20("Tether Gold", "XAUT", 6);
        console.log("XAUT deployed at:", address(xaut));

        vm.stopBroadcast();
    }
}
