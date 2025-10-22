use anchor_lang::prelude::*;

use crate::constants::*;
use crate::errors::TokenizationWrapError;
use crate::instructions::create_mint::WrappedMintState;
use anchor_spl::token_interface::Mint;

pub fn transfer_ownership(ctx: Context<TransferOwnerShip>, new_owner: Pubkey) -> Result<()> {
    let wrapped_mint_state = &mut ctx.accounts.wrapped_mint_state;
    wrapped_mint_state.wrapped_mint_pending_owner = new_owner;

    msg!(
        "Pending owner: {}",
        wrapped_mint_state.wrapped_mint_pending_owner
    );

    return Ok(());
}

pub fn accept_ownership(ctx: Context<AcceptOwnerShip>) -> Result<()> {
    let wrapped_mint_state = &mut ctx.accounts.wrapped_mint_state;
    let wrapped_mint_pending_owner_key = ctx.accounts.wrapped_mint_pending_owner.key();
    wrapped_mint_state.wrapped_mint_owner = wrapped_mint_pending_owner_key;
    wrapped_mint_state.wrapped_mint_pending_owner = pubkey!("11111111111111111111111111111111");

    msg!("New owner: {}", wrapped_mint_state.wrapped_mint_owner);

    return Ok(());
}

#[derive(Accounts)]
#[instruction(new_owner: Pubkey)]
pub struct TransferOwnerShip<'info> {
    #[account(
        mut,
        address = wrapped_mint_state.wrapped_mint_owner @TokenizationWrapError::NotOwner,
    )]
    pub wrapped_mint_owner: Signer<'info>,

    // unwrapped mint to be wrapped
    #[account(
        constraint = (wrapped_mint_state.wrapped_mint == wrapped_mint.key()) @ TokenizationWrapError::InvalidWrappedMint,
    )]
    pub wrapped_mint: InterfaceAccount<'info, Mint>,

    // wrapped mint state
    #[account(
        mut,
        seeds = [WRAPPED_MINT_STATE_SEED, &wrapped_mint.key().as_ref()],
        bump,
    )]
    pub wrapped_mint_state: Account<'info, WrappedMintState>,
}

#[derive(Accounts)]
pub struct AcceptOwnerShip<'info> {
    #[account(
        mut,
        address = wrapped_mint_state.wrapped_mint_pending_owner @TokenizationWrapError::NotPendingOwner,
    )]
    pub wrapped_mint_pending_owner: Signer<'info>,

    // unwrapped mint to be wrapped
    #[account(
        constraint = (wrapped_mint_state.wrapped_mint == wrapped_mint.key()) @ TokenizationWrapError::InvalidWrappedMint,
    )]
    pub wrapped_mint: InterfaceAccount<'info, Mint>,

    // wrapped mint state
    #[account(
        mut,
        seeds = [WRAPPED_MINT_STATE_SEED, &wrapped_mint.key().as_ref()],
        bump,
    )]
    pub wrapped_mint_state: Account<'info, WrappedMintState>,
}
