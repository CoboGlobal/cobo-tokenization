#![allow(unexpected_cfgs)]
#![allow(deprecated)]
use anchor_lang::prelude::*;

pub mod constants;
pub mod errors;
pub mod instructions;

use crate::instructions::close_vault;
use crate::instructions::close_vault::*;
use crate::instructions::create_mint;
use crate::instructions::create_mint::*;
use crate::instructions::manage;
use crate::instructions::manage::*;
use crate::instructions::recover_mint;
use crate::instructions::recover_mint::*;
use crate::instructions::role;
use crate::instructions::role::*;
use crate::instructions::unwrap;
use crate::instructions::unwrap::*;
use crate::instructions::wrap;
use crate::instructions::wrap::*;

declare_id!("2LbadSfQEGMooXUB3tmkXufVGKrQBkjR7UybxnvmwH4L");

#[program]
pub mod tokenization_wrap {
    use super::*;

    // manage

    // owner set
    pub fn transfer_ownership(ctx: Context<TransferOwnerShip>, new_owner: Pubkey) -> Result<()> {
        return manage::transfer_ownership(ctx, new_owner);
    }

    pub fn accept_ownership(ctx: Context<AcceptOwnerShip>) -> Result<()> {
        return manage::accept_ownership(ctx);
    }

    // role
    pub fn add_role(ctx: Context<AddRole>, user: Pubkey, role: u8) -> Result<()> {
        return role::add_role(ctx, user, role);
    }

    pub fn remove_role(ctx: Context<RemoveRole>, user: Pubkey, role: u8) -> Result<()> {
        return role::remove_role(ctx, user, role);
    }

    // tokenization
    pub fn create_mint(
        ctx: Context<CreateMint>,
        salt: [u8; 32],
        name: String,
        symbol: String,
        uri: String,
    ) -> Result<()> {
        return create_mint::create_mint(ctx, salt, name, symbol, uri);
    }

    pub fn wrap(ctx: Context<Wrap>, amount: u64) -> Result<()> {
        return wrap::wrap(ctx, amount);
    }

    pub fn unwrap(ctx: Context<Unwrap>, amount: u64) -> Result<()> {
        return unwrap::unwrap(ctx, amount);
    }

    pub fn close_vault(ctx: Context<CloseUnwrappedMintVault>) -> Result<()> {
        return close_vault::close_unwrapped_mint_vault(ctx);
    }

    pub fn recover_mint(ctx: Context<RecoverMint>) -> Result<()> {
        return recover_mint::recover_mint(ctx);
    }
}
