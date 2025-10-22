import * as anchor from "@coral-xyz/anchor";
import { Program, AnchorError } from "@coral-xyz/anchor";
import { TokenizationWrap } from "../target/types/tokenization_wrap";
import { Enum, Keypair, PublicKey } from "@solana/web3.js"
import * as borsh from "borsh";
import { createHash } from 'crypto';
import { getAssociatedTokenAddress, getAccount } from "@solana/spl-token"
import {
  createMint,
  getOrCreateAssociatedTokenAccount,
  mintTo,
  TOKEN_2022_PROGRAM_ID,
  ASSOCIATED_TOKEN_PROGRAM_ID
} from "@solana/spl-token";
import { min } from "bn.js";
import { time } from "console";
import { Uint } from "web3";

const bs58 = require("bs58");
const chai = require('chai');
const expect = chai.expect;
const assert = chai.assert;

const WRAPPED_MINT_SEED = "wrapped_mint";
const WRAPPED_MINT_STATE_SEED = "wrapped_mint_state";
const WRAPPED_ROLE_SEED = "wrapped_role";
const decimals = 8;
const wrapAmount = 10000000 * 10 ** decimals;
const wrapAmountBN = new anchor.BN(wrapAmount.toString());
const sleepTime = 500;
const salt: Uint8Array = new Uint8Array([
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01,
]);
const name = "Test Token";
const symbol = "TEST";
const uri = "https://test.com";

enum RoleKind {
  Default = 0, // default role, no special permissions
  Wrapper = 1,
}


// Configure the client to use the local cluster.
const provider = anchor.AnchorProvider.env()
anchor.setProvider(provider)
const connection = provider.connection;
// 1. solana-test-validator --reset 
// 2. anchor test --provider.cluster http://localhost:8899
// 3. spl-token create-token --decimals 18 --program-id TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb -> no more needed

const TokenizationWrapProgram = anchor.workspace.TokenizationWrap as Program<TokenizationWrap>;

// provider.wallet
console.log("owner / deployer:", provider.wallet.publicKey.toString());
// new owner
const newOwner = Keypair.generate()
console.log(" new owner:", newOwner.publicKey.toString());

async function airdrop() {
  const tx = await provider.connection.requestAirdrop(
    provider.wallet.publicKey,
    anchor.web3.LAMPORTS_PER_SOL
  );
  await provider.connection.confirmTransaction(tx, "processed");

  const tx1 = await provider.connection.requestAirdrop(
    newOwner.publicKey,
    anchor.web3.LAMPORTS_PER_SOL
  );
  await provider.connection.confirmTransaction(tx1, "processed");
}

async function createUnwrappedMint(user: Keypair) {
  const unwrappedMint = await createMint(
    connection,
    user,
    user.publicKey,
    null,
    decimals,
    undefined,
    { commitment: "confirmed" },
    TOKEN_2022_PROGRAM_ID,
  );
  console.log("Prepared unwrapped mint:", unwrappedMint);
  return unwrappedMint;
}

async function getUnwrappedMintAta(user: Keypair, unwrappedMint: PublicKey) {

  const unwrappedMintAta = await getOrCreateAssociatedTokenAccount(
    connection,
    user,
    unwrappedMint,
    user.publicKey,
    false,
    undefined,
    { commitment: "confirmed" },
    TOKEN_2022_PROGRAM_ID,
    ASSOCIATED_TOKEN_PROGRAM_ID
  );
  console.log("created owner ATA:", unwrappedMintAta.address.toBase58());

  return unwrappedMintAta;
}

async function mintUnwrappedToAta(user: Keypair, unwrappedMint: PublicKey, unwrappedMintAta: PublicKey, amount: number) {
  await mintTo(
    connection,
    user,
    unwrappedMint,
    unwrappedMintAta,
    user,
    amount,
    [],
    { commitment: "confirmed" },
    TOKEN_2022_PROGRAM_ID
  );
  console.log("Minted unwrapped tokens");
}

async function getAtaAddress(mint: PublicKey, user: PublicKey, allowOwnerOffCurve: boolean) {
  const ataAddress = await getAssociatedTokenAddress(
    mint,
    user,
    allowOwnerOffCurve, // allowOwnerOffCurve
    TOKEN_2022_PROGRAM_ID,
    ASSOCIATED_TOKEN_PROGRAM_ID
  );
  return ataAddress;
}

async function createUnwrappedMintAndAta(user: Keypair, amount: number) {
  const unwrappedMint = await createUnwrappedMint(user);
  await sleep(sleepTime);
  const unwrappedMintAta = await getUnwrappedMintAta(user, unwrappedMint);
  await sleep(sleepTime);
  await mintUnwrappedToAta(user, unwrappedMint, unwrappedMintAta.address, amount * 5);
  await sleep(sleepTime);
  return { unwrappedMint, unwrappedMintAta: unwrappedMintAta.address };
}

async function getWrappedMintPda(unwrappedMint: PublicKey, salt: Uint8Array) {
  const [wrappedMintPda] = anchor.web3.PublicKey.findProgramAddressSync(
    [Buffer.from(WRAPPED_MINT_SEED), unwrappedMint.toBuffer(), salt],
    TokenizationWrapProgram.programId
  );
  console.log("Prepared wrapped mint pda:", wrappedMintPda);
  return wrappedMintPda;
}

async function getWrappedMintStatePda(wrappedMintPda: PublicKey) {
  const [wrappedMintStatePda] = anchor.web3.PublicKey.findProgramAddressSync(
    [Buffer.from(WRAPPED_MINT_STATE_SEED), wrappedMintPda.toBuffer()],
    TokenizationWrapProgram.programId
  );
  console.log("Prepared wrapped mint state pda:", wrappedMintStatePda);
  return wrappedMintStatePda;
}

async function createTokenizationWrapMint(salt: Uint8Array, name: string, symbol: string, uri: string, unwrappedMint: PublicKey, wrappedMintPda: PublicKey, wrappedMintStatePda: PublicKey, unwrappedMintVaultAta: PublicKey) {
  console.log("createTokenizationWrapMint:");
  const tx = await TokenizationWrapProgram.methods.createMint(
    [...salt],
    name,
    symbol,
    uri
  ).accounts(
    {
      wrappedMintOwner: provider.wallet.publicKey,
      unwrappedMint: unwrappedMint,
      wrappedMint: wrappedMintPda,
      wrappedMintState: wrappedMintStatePda,
      unwrappedMintVault: unwrappedMintVaultAta,
      associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
      tokenProgram: TOKEN_2022_PROGRAM_ID,
      rent: anchor.web3.SYSVAR_RENT_PUBKEY,
      systemProgram: anchor.web3.SystemProgram.programId,
    }
  ).rpc();
  console.log("Create mint transaction signature:", tx);
  await sleep(sleepTime);
}

async function getUserRolePda(wrappedMintPda: PublicKey, user: PublicKey, role: Uint8Array) {
  const [userRolePda] = anchor.web3.PublicKey.findProgramAddressSync(
    [Buffer.from(WRAPPED_ROLE_SEED), wrappedMintPda.toBuffer(), role, user.toBuffer()],
    TokenizationWrapProgram.programId
  );
  console.log("Prepared user role pda:", userRolePda);
  return userRolePda;
}

async function addRole(user: PublicKey,role: RoleKind, wrappedMintPda: PublicKey, wrappedMintStatePda: PublicKey, userRolePda: PublicKey) {
  await TokenizationWrapProgram.methods.addRole(user,role).accounts
    (
      {
        wrappedMintOwner: provider.wallet.publicKey,
        wrappedMint: wrappedMintPda,
        wrappedMintState: wrappedMintStatePda,
        userRole: userRolePda,
      }
    ).rpc();
  await sleep(sleepTime);
}

async function removeRole(user: PublicKey, role: RoleKind, wrappedMintPda: PublicKey, wrappedMintStatePda: PublicKey, userRolePda: PublicKey) {
  await TokenizationWrapProgram.methods.removeRole(user,role).accounts
    (
      {
        wrappedMintOwner: provider.wallet.publicKey,
        wrappedMint: wrappedMintPda,
        wrappedMintState: wrappedMintStatePda,
        userRole: userRolePda,
      }
    ).rpc();
  await sleep(sleepTime);
}

async function tokenizationWrap(user: Keypair, unwrappedMint: PublicKey, wrappedMintPda: PublicKey, wrappedMintStatePda: PublicKey, userRolePda: PublicKey, unwrappedMintAta: PublicKey, wrappedMintAta: PublicKey, unwrappedMintVault: PublicKey) {
  console.log("tokenizationWrap:");
  const tx = await TokenizationWrapProgram.methods.wrap(wrapAmountBN).accounts
    (
      {
        user: user.publicKey,
        unwrappedMint: unwrappedMint,
        wrappedMint: wrappedMintPda,
        wrappedMintState: wrappedMintStatePda,
        userRole: userRolePda,
        unwrappedMintAccount: unwrappedMintAta,
        wrappedMintAccount: wrappedMintAta,
        unwrappedMintVault: unwrappedMintVault,
        tokenProgram: TOKEN_2022_PROGRAM_ID,
        associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
        systemProgram: anchor.web3.SystemProgram.programId,
      }
    ).signers([user]).rpc();
  console.log("Wrap transaction signature:", tx);
  await sleep(sleepTime);
}

async function tokenizationUnwrap(user: Keypair, unwrappedMint: PublicKey, wrappedMintPda: PublicKey, wrappedMintStatePda: PublicKey, userRolePda: PublicKey, unwrappedMintAta: PublicKey, wrappedMintAta: PublicKey, unwrappedMintVault: PublicKey) {
  console.log("tokenizationUnwrap:");
  const tx = await TokenizationWrapProgram.methods.unwrap(wrapAmountBN).accounts
    (
      {
        user: user.publicKey,
        unwrappedMint: unwrappedMint,
        wrappedMint: wrappedMintPda,
        wrappedMintState: wrappedMintStatePda,
        userRole: userRolePda,
        unwrappedMintAccount: unwrappedMintAta,
        wrappedMintAccount: wrappedMintAta,
        unwrappedMintVault: unwrappedMintVault,
        tokenProgram: TOKEN_2022_PROGRAM_ID,
        associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
        systemProgram: anchor.web3.SystemProgram.programId,
      }
    ).signers([user]).rpc();
  console.log("Unwrap transaction signature:", tx);
  await sleep(sleepTime);
}

async function closeUnwrappedMintVault(unwrappedMint: PublicKey, wrappedMintPda: PublicKey, wrappedMintStatePda: PublicKey, unwrappedMintVault: PublicKey) {
  console.log("closeUnwrappedMintVault:");
  const tx = await TokenizationWrapProgram.methods.closeVault().accounts
    (
      {
        wrappedMintOwner: provider.wallet.publicKey,
        unwrappedMint: unwrappedMint,
        wrappedMint: wrappedMintPda,
        wrappedMintState: wrappedMintStatePda,
        unwrappedMintVault: unwrappedMintVault,
        tokenProgram: TOKEN_2022_PROGRAM_ID,
        associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
      }
    ).rpc();
  console.log("Close unwrapped mint vault transaction signature:", tx);
  await sleep(sleepTime);
}

async function transferOwnership(wrappedMintPda: PublicKey, wrappedMintStatePda: PublicKey) {

  //if not deployer, should throw UnauthorizedInitializer
  try {
    await TokenizationWrapProgram.methods.transferOwnership(newOwner.publicKey).accounts
      (
        {
          wrappedMintOwner: newOwner.publicKey,
          wrappedMint: wrappedMintPda,
          wrappedMintState: wrappedMintStatePda,
        }
      ).signers([newOwner]).rpc();
  } catch (_err) {
    assert.isTrue(_err instanceof AnchorError);
    const err: AnchorError = _err;
    assert.strictEqual(err.error.errorCode.code, "NotOwner");
    assert.strictEqual(
      err.error.errorMessage,
      "Not owner"
    );
  }
  console.log("transferOwnership:");
  const tx = await TokenizationWrapProgram.methods.transferOwnership(newOwner.publicKey).accounts
    (
      {
        wrappedMintOwner: provider.wallet.publicKey,
        wrappedMint: wrappedMintPda,
        wrappedMintState: wrappedMintStatePda,
      }
    ).rpc();
  console.log("Transfer ownership transaction signature:", tx);
  await sleep(sleepTime);
}

async function acceptOwnership(user: Keypair, wrappedMintPda: PublicKey, wrappedMintStatePda: PublicKey) {

  //if not deployer, should throw UnauthorizedInitializer
  try {
    await TokenizationWrapProgram.methods.acceptOwnership().accounts
      (
        {
          wrappedMintPendingOwner: provider.wallet.publicKey,
          wrappedMint: wrappedMintPda,
          wrappedMintState: wrappedMintStatePda,
        }
      ).rpc();
  } catch (_err) {
    assert.isTrue(_err instanceof AnchorError);
    const err: AnchorError = _err;
    assert.strictEqual(err.error.errorCode.code, "NotPendingOwner");
    assert.strictEqual(
      err.error.errorMessage,
      "Not pending owner"
    );
  }
  await sleep(sleepTime);

  console.log("acceptOwnership:");
  const tx = await TokenizationWrapProgram.methods.acceptOwnership().accounts
    (
      {
        wrappedMintPendingOwner: user.publicKey,
        wrappedMint: wrappedMintPda,
        wrappedMintState: wrappedMintStatePda,
      }
    ).signers([user]).rpc();
  console.log("Accept ownership transaction signature:", tx);
  await sleep(sleepTime);
}

async function recoverMint(user: Keypair, unwrappedMint: PublicKey, wrappedMintPda: PublicKey, wrappedMintStatePda: PublicKey, wrappedMintAta: PublicKey, unwrappedMintVault: PublicKey) {
  console.log("recoverMint:");
  const tx = await TokenizationWrapProgram.methods.recoverMint().accounts
    (
      {
        wrappedMintOwner: user.publicKey,
        unwrappedMint: unwrappedMint,
        wrappedMint: wrappedMintPda,
        wrappedMintState: wrappedMintStatePda,
        wrappedMintAccount: wrappedMintAta,
        unwrappedMintVault: unwrappedMintVault,
        tokenProgram: TOKEN_2022_PROGRAM_ID,
        associatedTokenProgram: ASSOCIATED_TOKEN_PROGRAM_ID,
        systemProgram: anchor.web3.SystemProgram.programId,
      }
    ).signers([user]).rpc();
  console.log("Recover mint transaction signature:", tx);
  await sleep(sleepTime);
}

function sleep(ms: number) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function main() {
  await airdrop();
  await sleep(sleepTime);
  const { unwrappedMint, unwrappedMintAta } = await createUnwrappedMintAndAta(newOwner, wrapAmount);
  await sleep(sleepTime);
  const wrappedMintPda = await getWrappedMintPda(unwrappedMint, salt);
  const wrappedMintStatePda = await getWrappedMintStatePda(wrappedMintPda);
  await sleep(sleepTime);

  const wrappedMintAta = await getAtaAddress(wrappedMintPda, newOwner.publicKey, false);
  console.log("wrappedMintAta:", wrappedMintAta);
  const unwrappedMintVaultAta = await getAtaAddress(unwrappedMint, wrappedMintPda, true);
  console.log("unwrappedMintVaultAta:", unwrappedMintVaultAta);

  // createTokenizationWrapMint
  await createTokenizationWrapMint(salt, name, symbol, uri, unwrappedMint, wrappedMintPda, wrappedMintStatePda, unwrappedMintVaultAta);
  await sleep(sleepTime);

  // addRole
  // or Uint8Array.of(id) -> [id] , or &[0 as u8] , or new anchor.BN(0).toArrayLike(Buffer)
  const userWrapperRolePda = await getUserRolePda(wrappedMintPda, newOwner.publicKey, Uint8Array.of(RoleKind.Wrapper));
  await addRole(newOwner.publicKey,RoleKind.Wrapper, wrappedMintPda, wrappedMintStatePda, userWrapperRolePda);
  await sleep(sleepTime);
  const userWrapperRoleData = await TokenizationWrapProgram.account.roleState.fetch(userWrapperRolePda);
  console.log("userWrapperRoleData:", userWrapperRoleData);
  assert.strictEqual(userWrapperRoleData.user.toString(), newOwner.publicKey.toString());
  assert.strictEqual(userWrapperRoleData.wrappedMint.toString(), wrappedMintPda.toString());

  // tokenizationWrap
  await sleep(sleepTime);
  await tokenizationWrap(newOwner, unwrappedMint, wrappedMintPda, wrappedMintStatePda, userWrapperRolePda, unwrappedMintAta, wrappedMintAta, unwrappedMintVaultAta);
  await sleep(sleepTime);

  // tokenizationUnwrap
  await tokenizationUnwrap(newOwner, unwrappedMint, wrappedMintPda, wrappedMintStatePda, userWrapperRolePda, unwrappedMintAta, wrappedMintAta, unwrappedMintVaultAta);
  await sleep(sleepTime);

  // closeUnwrappedMintVault
  await closeUnwrappedMintVault(unwrappedMint, wrappedMintPda, wrappedMintStatePda, unwrappedMintVaultAta);
  await sleep(sleepTime);

  // tokenizationWrap
  await sleep(sleepTime);
  await tokenizationWrap(newOwner, unwrappedMint, wrappedMintPda, wrappedMintStatePda, userWrapperRolePda, unwrappedMintAta, wrappedMintAta, unwrappedMintVaultAta);
  await sleep(sleepTime);

  // tokenizationUnwrap
  await tokenizationUnwrap(newOwner, unwrappedMint, wrappedMintPda, wrappedMintStatePda, userWrapperRolePda, unwrappedMintAta, wrappedMintAta, unwrappedMintVaultAta);
  await sleep(sleepTime);

  // removeRole
  await removeRole(newOwner.publicKey,RoleKind.Wrapper, wrappedMintPda, wrappedMintStatePda, userWrapperRolePda);
  await sleep(sleepTime);
  try {
    await TokenizationWrapProgram.account.roleState.fetch(userWrapperRolePda);
  } catch (error) {
    console.log("Remove wrapper:", error);
  }

  // transferOwnership
  await transferOwnership(wrappedMintPda, wrappedMintStatePda);
  await sleep(sleepTime);
  const tokenizationWrapTransferredData = await TokenizationWrapProgram.account.wrappedMintState.fetch(wrappedMintStatePda);
  console.log("tokenizationWrapTransferredData:", tokenizationWrapTransferredData);
  assert.strictEqual(tokenizationWrapTransferredData.wrappedMintOwner.toString(), provider.wallet.publicKey.toString());
  assert.strictEqual(tokenizationWrapTransferredData.wrappedMintPendingOwner.toString(), newOwner.publicKey.toString());

  // acceptOwnership
  await acceptOwnership(newOwner, wrappedMintPda, wrappedMintStatePda);
  await sleep(sleepTime);
  const tokenizationWrapAcceptedData = await TokenizationWrapProgram.account.wrappedMintState.fetch(wrappedMintStatePda);
  console.log("tokenizationWrapAcceptedData:", tokenizationWrapAcceptedData);
  assert.strictEqual(tokenizationWrapAcceptedData.wrappedMintOwner.toString(), newOwner.publicKey.toString());
  assert.strictEqual(tokenizationWrapAcceptedData.wrappedMintPendingOwner.toString(), "11111111111111111111111111111111");

  // mint unwrapped to 
  await mintUnwrappedToAta(newOwner, unwrappedMint, unwrappedMintVaultAta,  wrapAmount);
  await sleep(sleepTime);

  // recoverMint
  await recoverMint(newOwner, unwrappedMint, wrappedMintPda, wrappedMintStatePda, wrappedMintAta, unwrappedMintVaultAta);
  await sleep(sleepTime);
}

it("test tokenization wrap", async () => {
  await main();
});
