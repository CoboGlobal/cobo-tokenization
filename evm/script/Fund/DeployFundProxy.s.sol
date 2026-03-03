// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.20;

import {Script, console2 as console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CoboFundOracle} from "../src/Fund/CoboFundOracle.sol";
import {CoboFundToken} from "../src/Fund/CoboFundToken.sol";
import {CoboFundVault} from "../src/Fund/CoboFundVault.sol";

interface IFactory {
    function deploy(uint8 typ, bytes32 salt, bytes memory initCode) external returns (address);

    function deployAndInit(uint8 typ, bytes32 salt, bytes calldata initCode, bytes calldata callData)
        external
        returns (address);

    function getAddress(uint8 typ, bytes32 salt, address sender, bytes calldata initCode)
        external
        view
        returns (address);
}

/// @title DeployFundProxy - Deploy all 3 Nav proxies with multicall init via CREATE3.
/// @dev Deployment order: Oracle → FundToken → Vault (FundToken needs vault address, Vault needs fundToken address).
///      Uses CREATE3 getAddress to predict addresses before deployment.
///
///      Before running, set these environment variables:
///        ORACLE_LOGIC  - Address of deployed CoboFundOracle logic contract
///        NAV4626_LOGIC - Address of deployed CoboFundToken logic contract
///        VAULT_LOGIC   - Address of deployed CoboFundVault logic contract
///        ADMIN         - Safe multisig address (receives DEFAULT_ADMIN_ROLE)
///        XAUT          - XAUT token address on target chain
///
///      Run: forge script script/DeployFundProxy.s.sol --rpc-url $RPC_URL --broadcast
contract DeployFundProxy is Script {
    address public constant FACTORY = 0xC0B000003148E9c3E0D314f3dB327Ef03ADF8Ba7;

    // ─── Configurable Parameters ─────────────────────────────────────
    // Override these for your deployment or set via environment variables.

    // Oracle config
    // See: src/Fund/docs/xaue/XAUE-Transaction-Checklist.md — default initial APR is 0%.
    // The NAV updater can later call updateRate() to set a non-zero APR.
    uint256 public constant INITIAL_NAV = 1e18; // 1.0 (1e18 precision)
    uint256 public constant INITIAL_APR = 0; // 0% (per XAUE-Transaction-Checklist default)
    uint256 public constant MAX_APR = 2e17; // 20% (per XAUE-Transaction-Checklist default)
    uint256 public constant MAX_APR_DELTA = 5e16; // 5% max change per update
    uint256 public constant MIN_UPDATE_INTERVAL = 1 days;

    // FundToken config
    string public constant TOKEN_NAME = "XAUE Gold Fund";
    string public constant TOKEN_SYMBOL = "XAUE";
    uint8 public constant TOKEN_DECIMALS = 18;
    uint256 public constant MIN_DEPOSIT_AMOUNT = 1e6; // 1 XAUT
    uint256 public constant MIN_REDEEM_SHARES = 1e18; // 1 XAUE

    function run() public {
        // Read addresses from environment
        address oracleLogic = vm.envAddress("ORACLE_LOGIC");
        address fundTokenLogic = vm.envAddress("NAV4626_LOGIC");
        address vaultLogic = vm.envAddress("VAULT_LOGIC");
        address adminAddr = vm.envAddress("ADMIN");
        address xautAddr = vm.envAddress("XAUT");

        IFactory factory = IFactory(FACTORY);

        // ─── Predict proxy addresses via CREATE3 ─────────────────────
        // This lets us pass vault address to FundToken and vice versa.
        bytes32 oracleSalt = bytes32("CoboFundOracleProxy");
        bytes32 fundTokenSalt = bytes32("CoboFundTokenProxy");
        bytes32 vaultSalt = bytes32("CoboFundVaultProxy");

        // Empty proxy init code (no constructor args for prediction)
        bytes memory oracleInitCode =
            abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(oracleLogic, bytes("")));
        bytes memory fundTokenInitCode =
            abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(fundTokenLogic, bytes("")));
        bytes memory vaultInitCode =
            abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(vaultLogic, bytes("")));

        vm.startBroadcast();

        // ─── 1. Deploy Oracle Proxy ──────────────────────────────────
        bytes[] memory oracleData = new bytes[](1);
        oracleData[0] = abi.encodeCall(
            CoboFundOracle.initialize,
            (adminAddr, INITIAL_NAV, INITIAL_APR, MAX_APR, MAX_APR_DELTA, MIN_UPDATE_INTERVAL)
        );
        // Factory calls multicall, which calls initialize — factory becomes admin temporarily.
        // We grant admin to the Safe and renounce factory's admin in the same multicall.
        // But since initialize already grants admin to adminAddr, we just need the single call.
        bytes memory oracleCallData = abi.encodeWithSignature("multicall(bytes[])", oracleData);
        address oracleProxy = factory.deployAndInit(7, oracleSalt, oracleInitCode, oracleCallData);
        console.log("CoboFundOracle proxy:", oracleProxy);

        // ─── 2. Deploy FundToken Proxy ─────────────────────────────────
        // Need vault address — predict it
        address predictedVault = factory.getAddress(7, vaultSalt, msg.sender, vaultInitCode);
        console.log("Predicted Vault address:", predictedVault);

        bytes[] memory fundTokenData = new bytes[](1);
        fundTokenData[0] = abi.encodeCall(
            CoboFundToken.initialize,
            (
                TOKEN_NAME,
                TOKEN_SYMBOL,
                TOKEN_DECIMALS,
                xautAddr,
                oracleProxy,
                predictedVault,
                adminAddr,
                MIN_DEPOSIT_AMOUNT,
                MIN_REDEEM_SHARES
            )
        );
        bytes memory fundTokenCallData = abi.encodeWithSignature("multicall(bytes[])", fundTokenData);
        address fundTokenProxy = factory.deployAndInit(7, fundTokenSalt, fundTokenInitCode, fundTokenCallData);
        console.log("CoboFundToken proxy:", fundTokenProxy);

        // ─── 3. Deploy Vault Proxy ───────────────────────────────────
        bytes[] memory vaultData = new bytes[](1);
        vaultData[0] = abi.encodeCall(CoboFundVault.initialize, (xautAddr, fundTokenProxy, adminAddr));
        bytes memory vaultCallData = abi.encodeWithSignature("multicall(bytes[])", vaultData);
        address vaultProxy = factory.deployAndInit(7, vaultSalt, vaultInitCode, vaultCallData);
        console.log("CoboFundVault proxy:", vaultProxy);

        // Verify predicted vault address matches
        require(vaultProxy == predictedVault, "Vault address prediction mismatch!");

        vm.stopBroadcast();

        // ─── Summary ─────────────────────────────────────────────────
        console.log("========================================");
        console.log("Deployment complete!");
        console.log("Oracle:", oracleProxy);
        console.log("FundToken:", fundTokenProxy);
        console.log("Vault:", vaultProxy);
        console.log("Admin:", adminAddr);
        console.log("========================================");
        console.log("");
        console.log("Post-deployment role grants (via Safe multisig):");
        console.log("  Oracle:  grantRole(NAV_UPDATER_ROLE, <navUpdater>)");
        console.log("  Oracle:  grantRole(UPGRADER_ROLE, <upgrader>)");
        console.log("  FundToken: grantRole(MANAGER_ROLE, <manager>)");
        console.log("  FundToken: grantRole(REDEMPTION_APPROVER_ROLE, <approver>)");
        console.log("  FundToken: grantRole(EMERGENCY_GUARDIAN_ROLE, <guardian>)");
        console.log("  FundToken: grantRole(UPGRADER_ROLE, <upgrader>)");
        console.log("  Vault:   grantRole(SETTLEMENT_OPERATOR_ROLE, <operator>)");
        console.log("  Vault:   grantRole(UPGRADER_ROLE, <upgrader>)");
        console.log("  Vault:   setWhitelist(<custodyAddress>, true)");
    }
}
