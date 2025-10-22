use crate::constants::*;
use crate::errors::TokenizationWrapError;
use crate::instructions::create_mint::WrappedMintState;
use anchor_lang::prelude::*;
use anchor_spl::associated_token::AssociatedToken;
use anchor_spl::token_2022::Token2022;
use anchor_spl::token_interface::{close_account, CloseAccount, Mint, TokenAccount};

/// Closes a stuck escrow account when its extensions don't match the mint's requirements.
/// The escrow ATA can get "stuck" when an unwrapped mint with a close authority is closed
/// and then a new mint is created at the same address but with different extensions,
/// leaving the escrow ATA (Associated Token Account) in an incompatible state.
pub fn close_unwrapped_mint_vault(ctx: Context<CloseUnwrappedMintVault>) -> Result<()> {
    let unwrapped_mint_vault = &ctx.accounts.unwrapped_mint_vault;
    let unwrapped_mint = &ctx.accounts.unwrapped_mint;
    let wrapped_mint_owner = &ctx.accounts.wrapped_mint_owner;
    let token_program = &ctx.accounts.token_program;
    let wrapped_mint = &ctx.accounts.wrapped_mint;
    let wrapped_mint_state = &ctx.accounts.wrapped_mint_state;

    let wrapped_mint_key = wrapped_mint.key();
    let unwrapped_mint_key = unwrapped_mint.key();
    let wrapped_mint_state_key = wrapped_mint_state.key();

    // wrapped mint seeds
    let wrapped_mint_bump = ctx.bumps.wrapped_mint;
    let wrapped_mint_seeds: &[&[&[u8]]] = &[&[
        WRAPPED_MINT_SEED,
        unwrapped_mint_key.as_ref(),
        &wrapped_mint_state.salt,
        &[wrapped_mint_bump],
    ]];

    close_account(CpiContext::new_with_signer(
        token_program.to_account_info(),
        CloseAccount {
            account: unwrapped_mint_vault.to_account_info(),
            destination: wrapped_mint_owner.to_account_info(),
            authority: wrapped_mint.to_account_info(),
        },
        wrapped_mint_seeds,
    ))?;

    emit!(CloseUnwrappedMintVaultEvent {
        wrapped_mint_owner: wrapped_mint_owner.key(),
        unwrapped_mint: unwrapped_mint_key,
        wrapped_mint: wrapped_mint_key,
        wrapped_mint_state: wrapped_mint_state_key,
        unwrapped_mint_vault: unwrapped_mint_vault.key(),
    });

    msg!("Closed unwrapped mint vault: {}", wrapped_mint_state_key);
    msg!("Unwrapped mint: {}", unwrapped_mint_key);
    msg!("Wrapped mint: {}", wrapped_mint_key);

    Ok(())
}

#[derive(Accounts)]
pub struct CloseUnwrappedMintVault<'info> {
    // wrapped mint owner
    #[account(
        mut,
        address = wrapped_mint_state.wrapped_mint_owner @TokenizationWrapError::NotOwner,
    )]
    pub wrapped_mint_owner: Signer<'info>,

    /// The unwrapped mint
    #[account(
        constraint = (wrapped_mint_state.unwrapped_mint == unwrapped_mint.key()) @ TokenizationWrapError::InvalidUnwrappedMint
    )]
    pub unwrapped_mint: InterfaceAccount<'info, Mint>,

    // The wrapped mint
    #[account(
        seeds=[WRAPPED_MINT_SEED,&unwrapped_mint.key().as_ref(),&wrapped_mint_state.salt],
        bump,
        constraint = (wrapped_mint_state.wrapped_mint == wrapped_mint.key()) @ TokenizationWrapError::InvalidWrappedMint,
    )]
    pub wrapped_mint: InterfaceAccount<'info, Mint>,

    // wrapped mint state
    #[account(
        seeds = [WRAPPED_MINT_STATE_SEED, &wrapped_mint.key().as_ref()],
        bump,
    )]
    pub wrapped_mint_state: Account<'info, WrappedMintState>,

    /// The wrapped mint vault account holding unwrapped tokens
    #[account(
        mut,
        associated_token::mint = unwrapped_mint,
        associated_token::authority = wrapped_mint, // wrapped mint is authority, holding unwrapped tokens
        associated_token::token_program = token_program,
        constraint = (wrapped_mint_state.unwrapped_mint_vault == unwrapped_mint_vault.key()) @ TokenizationWrapError::InvalidUnwrappedMintVault,
    )]
    pub unwrapped_mint_vault: InterfaceAccount<'info, TokenAccount>,
    pub associated_token_program: Program<'info, AssociatedToken>,
    pub token_program: Program<'info, Token2022>,
}

#[event]
pub struct CloseUnwrappedMintVaultEvent {
    pub wrapped_mint_owner: Pubkey,
    pub unwrapped_mint: Pubkey,
    pub wrapped_mint: Pubkey,
    pub wrapped_mint_state: Pubkey,
    pub unwrapped_mint_vault: Pubkey,
}