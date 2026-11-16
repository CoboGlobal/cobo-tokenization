# Fund Logic Deployment

The shared `CoboFundOracle`, `CoboFundToken`, and `CoboFundVault` addresses refer to a pinned implementation release. They are not automatically reproduced by building the latest checkout.

Logic deployment creates three implementations only. It does **not** create product proxies, configure NAV/APR or underlying assets, assign product roles, or initialize implementations. Product deployment is documented in [Fund README](../src/Fund/README.md#deployment).

## Shared Release

| Input | Value |
|-------|-------|
| Source repository | `cobo-tokenization` |
| Source commit | `f86ea7a582fb60592fd992c1f5101bef1d496c58` |
| Deployment script | `evm/script/Fund/DeployFundLogic.s.sol:DeployFundLogic` |
| Deployer | `0x36ca10C475D6Fe1FA45E972bf4EEdaa53C921176` |
| Factory | `0xC0B000003148E9c3E0D314f3dB327Ef03ADF8Ba7` |
| Deployment type | `6` (`Create2WithSenderAndEmit`) |
| Solidity | `0.8.23+commit.f704f362` |
| EVM target | `london` |
| Optimizer | Enabled, `20000` runs |
| IR pipeline | `via_ir = true` |
| Metadata | IPFS bytecode hash, CBOR enabled |
| OpenZeppelin Contracts | `v5.0.2`, `dbb6104ce834628e473d2173bbc9d47f81a9eec3` |
| OpenZeppelin Contracts Upgradeable | `v5.0.2`, `723f8cab09cdae1aca9ec9cc1cfa040c2d4b06c1` |
| forge-std | `v1.15.0`, `0844d7e1fc5e60d77b68e469bff60265f236c398` |

The dependency revisions are recorded in `evm/foundry.lock` at the pinned commit. Restore dependencies to those revisions before building; do not use another project's `lib` directory or assume current dependencies are equivalent.

| Implementation | Salt passed to factory | Address |
|----------------|------------------------|---------|
| Oracle | `bytes32("CoboFundOracleLogic")` | `0xc0601667705F8C96c2e2F452E494bd5CC3b262BA` |
| FundToken | `bytes32("CoboFundTokenLogic")` | `0xAc5021d88e8003D30CCE6b089A3982060907a917` |
| Vault | `bytes32("CoboFundVaultLogic")` | `0x7D89fD39EE0d40b3024814B8874df710f1edeA00` |

For type `6`, the factory derives its effective salt with `keccak256(abi.encode(deployer, salt, uint256(2)))`, then uses `CREATE2`. The final address depends on the factory address, effective salt, and creation-bytecode hash. Chain ID, gas price, and the deployment account's transaction nonce are not address inputs. The factory must also exist and have the expected deployment behavior on the target chain.

Changing source code, import paths, dependencies, or compiler metadata can change the creation bytecode. Matching the compiler version and optimizer settings alone is insufficient. A newer implementation release may legitimately have different addresses; do not change salts or revert current production code merely to force address equality.

## BSC Mainnet

Chain ID: `56`. Transaction fees are paid in BNB. The three shared implementations are already deployed; **do not broadcast this release again on BSC**.

| Implementation | Deployment transaction |
|----------------|------------------------|
| Oracle | [`0x0ed714232e85515b49bc1aded0c5f6974b6e73093d1c1a9e01db406e8dd790b9`](https://bscscan.com/tx/0x0ed714232e85515b49bc1aded0c5f6974b6e73093d1c1a9e01db406e8dd790b9) |
| FundToken | [`0xacce1aef3832669e539c9da776476122a5f50c35efc0388d9e0e490fd92ae5f7`](https://bscscan.com/tx/0xacce1aef3832669e539c9da776476122a5f50c35efc0388d9e0e490fd92ae5f7) |
| Vault | [`0xaeb20a943b1566464cfbff65c9117dd93145c04771e0a2e5d6e4ab503b594359`](https://bscscan.com/tx/0xaeb20a943b1566464cfbff65c9117dd93145c04771e0a2e5d6e4ab503b594359) |

Use the addresses in the release table for product deployment. An address in this document does not replace checking its code and intended implementation release before use.

## Build and Bytecode Checks

Use a separate checkout of the pinned commit so the current working tree and dependencies are not changed. Run the following from its `evm/` directory, after restoring the locked dependencies. Keep simulation, deployment, and verification in this same checkout and build configuration.

Extract and hash each implementation's complete creation bytecode, including compiler metadata. The `&&` prevents hashing failed command output. Run each command separately and require the corresponding exact hash below before proceeding:

```bash
BYTECODE=$(forge inspect src/Fund/CoboFundOracle.sol:CoboFundOracle bytecode) && cast keccak "$BYTECODE"
```

```bash
BYTECODE=$(forge inspect src/Fund/CoboFundToken.sol:CoboFundToken bytecode) && cast keccak "$BYTECODE"
```

```bash
BYTECODE=$(forge inspect src/Fund/CoboFundVault.sol:CoboFundVault bytecode) && cast keccak "$BYTECODE"
```

Expected creation-bytecode hashes:

| Implementation | Creation bytes | Creation-bytecode Keccak-256 |
|----------------|---------------:|-----------------------------|
| Oracle | 9876 | `0x7a902aa26efc0e95264bcd1d5dc6a6e3cd519f53c18df8256b6d37fd4ee8d55a` |
| FundToken | 19445 | `0xb04136836ce7067412be2e6089e1b5ebb9dae6b72d48fb66e7f8312f70e3e95c` |
| Vault | 9610 | `0x1633c4c8be93858efbf82750621073407273d39ed836a1d52de8490abefab268` |

The pinned commit contains unrelated CoboERC20 deployment scripts with outdated relative imports. Fund tests can exclude scripts without changing the historical sources:

```bash
forge test --match-path 'test/Fund/*' --skip script
```

Compile and simulate the Fund deployment script separately as shown below. Do not replace its implementation source with the current checkout to work around unrelated script imports.

## Simulation and Deployment on an Additional Chain

This section applies only when the release is **not already deployed** on the target chain. Set the intended RPC URL and chain ID explicitly; export `PRIVATE_KEY` in the current terminal. Do not print it or enable shell command tracing.

```bash
DEPLOYER=$(cast wallet address --private-key "$PRIVATE_KEY")
```

Require the deployer to equal the release's original account. Confirm the target RPC chain ID, factory code, all three creation hashes, and that the expected addresses are unused. Then simulate without signing or broadcasting:

```bash
forge script script/Fund/DeployFundLogic.s.sol:DeployFundLogic \
  --rpc-url "$RPC_URL" --chain "$CHAIN_ID" --sender "$DEPLOYER"
```

All three predicted addresses must match the release table, and the command must finish successfully. Check the fee estimate against the deployer's native-token balance with a suitable margin for gas-price changes. Review and approve the target network and fee before adding `--private-key "$PRIVATE_KEY" --broadcast --slow` to the same command. Use legacy transactions if required by the target chain.

The three factory calls are separate transactions, not an atomic batch. After broadcasting, inspect all three receipts, deployed code, and output addresses. If broadcasting fails or times out, reconcile transaction hashes, receipts, and account nonces before considering a resume; do not blindly rerun deployment. Preserve the Foundry broadcast records without publishing private cache data.

## Source Verification on BSC

Verification publishes source and compiler input to the explorer; it does not send deployment transactions or consume BNB. Use the **pinned checkout and exact build configuration**, not the latest source tree. Export an `ETHERSCAN_API_KEY` with Etherscan API V2 access to chain `56`.

Run each command separately and require final success or an already-verified result before proceeding:

```bash
forge verify-contract 0xc0601667705F8C96c2e2F452E494bd5CC3b262BA \
  src/Fund/CoboFundOracle.sol:CoboFundOracle \
  --chain 56 --verifier etherscan \
  --verifier-url 'https://api.etherscan.io/v2/api?chainid=56' --watch
```

```bash
forge verify-contract 0xAc5021d88e8003D30CCE6b089A3982060907a917 \
  src/Fund/CoboFundToken.sol:CoboFundToken \
  --chain 56 --verifier etherscan \
  --verifier-url 'https://api.etherscan.io/v2/api?chainid=56' --watch
```

```bash
forge verify-contract 0x7D89fD39EE0d40b3024814B8874df710f1edeA00 \
  src/Fund/CoboFundVault.sol:CoboFundVault \
  --chain 56 --verifier etherscan \
  --verifier-url 'https://api.etherscan.io/v2/api?chainid=56' --watch
```

All three implementations have parameterless constructors. Do not supply proxy constructor arguments or call `initialize` on the implementations. If verification fails, correct the verification inputs or service access and retry verification only; do not redeploy.
