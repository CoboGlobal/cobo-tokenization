// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CoboERC20} from "../CoboERC20/CoboERC20.sol";

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
        return factory.deploy(7, bytes32(salt), code);  // Create3WithSenderAndEmit
    }
}

contract ProxyFactory {

    error InvalidAddress();

    using FactoryLib for IFactory;

    function deployAndInit(
        uint256 salt,   // salt for proxy deployment, eg: uint256(bytes32("CoboERC20Proxy"))
        address coboERC20Logic,  // coboERC20 logic address
        string memory name,  // name
        string memory symbol,  // symbol
        string memory uri,  // uri
        uint8 decimal,  // decimal
        address[] memory admins,  // admin address
        address[] memory managers,  // managers address
        address[] memory minters,  // minters address
        address[] memory burners,  // burners address
        address[] memory pausers,  // pausers address
        address[] memory salvagers,  // salvagers address
        address[] memory upgraders  // upgraders address
    ) public returns (address) {
        // check if admins is empty
        if (admins.length == 0) revert InvalidAddress();

        address _this = address(this);
        IFactory factory = IFactory(0xC0B000003148E9c3E0D314f3dB327Ef03ADF8Ba7);
        
        uint256 finalSalt = uint256(keccak256(abi.encode(msg.sender, salt)));
        // TODO: add init code
        address proxy = factory.doDeploy(
            finalSalt,
            abi.encodePacked(
                type(ERC1967Proxy).creationCode,
                abi.encode(coboERC20Logic,bytes(""))
            )
        );
        CoboERC20 coboERC20Proxy = CoboERC20(proxy);
        // TODO: initialize
        coboERC20Proxy.initialize(name, symbol, uri, decimal, _this);
        // TODO: add admin, manager, minter, burner, pauser, salvager, upgrader
        for (uint256 i = 0; i < admins.length; i++) {
            // check if admin is empty
            if (admins[i] == address(0)) revert InvalidAddress();
            coboERC20Proxy.grantRole(coboERC20Proxy.DEFAULT_ADMIN_ROLE(), admins[i]);
        }
        for (uint256 i = 0; i < managers.length; i++) {
            coboERC20Proxy.grantRole(coboERC20Proxy.MANAGER_ROLE(), managers[i]);
        }
        for (uint256 i = 0; i < minters.length; i++) {
            coboERC20Proxy.grantRole(coboERC20Proxy.MINTER_ROLE(), minters[i]);
        }
        for (uint256 i = 0; i < burners.length; i++) {
            coboERC20Proxy.grantRole(coboERC20Proxy.BURNER_ROLE(), burners[i]);
        }
        for (uint256 i = 0; i < pausers.length; i++) {
            coboERC20Proxy.grantRole(coboERC20Proxy.PAUSER_ROLE(), pausers[i]);
        }
        for (uint256 i = 0; i < salvagers.length; i++) {
            coboERC20Proxy.grantRole(coboERC20Proxy.SALVAGER_ROLE(), salvagers[i]);
        }
        for (uint256 i = 0; i < upgraders.length; i++) {
            coboERC20Proxy.grantRole(coboERC20Proxy.UPGRADER_ROLE(), upgraders[i]);
        }
        coboERC20Proxy.renounceRole(coboERC20Proxy.DEFAULT_ADMIN_ROLE(), _this);

        return proxy;
    }
}
