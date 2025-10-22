// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2 as console} from "forge-std/Script.sol";
import {CoboERC20Wrapper} from "../src/CoboERC20/CoboERC20Wrapper.sol";

interface IFactory {
    function deploy(uint8 typ, bytes32 salt, bytes memory initCode) external returns (address);

    function getAddress(
        uint8 typ,
        bytes32 salt,
        address sender,
        bytes calldata initCode
    ) external view returns (address _contract);
}

library FactoryLib {
    function doDeploy(IFactory factory, uint256 salt, bytes memory code) internal returns (address) {
        return factory.deploy(6, bytes32(salt), code);  // Create2WithSenderAndEmit
    }
}

contract DeployCoboERC20WrapperLogic is Script {
    using FactoryLib for IFactory;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        IFactory factory = IFactory(0xC0B000003148E9c3E0D314f3dB327Ef03ADF8Ba7);
        address coboERC20Wrapper = factory.doDeploy(
            // uint256(bytes32("CoboERC20WrapperLogic")),  // mainnet
            uint256(bytes32("CoboERC20WrapperLogicTestnet")), // TODO: remove , sepolia testnet
            type(CoboERC20Wrapper).creationCode
        );
        console.log("CoboERC20WrapperLogic deployed at", coboERC20Wrapper);
        vm.stopBroadcast();
    }
}
