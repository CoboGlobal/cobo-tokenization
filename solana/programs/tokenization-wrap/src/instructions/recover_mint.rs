use crate::constants::*;
use crate::errors::TokenizationWrapError;
use crate::instructions::create_mint::WrappedMintState;
use anchor_lang::prelude::*;
use anchor_spl::associated_token::AssociatedToken;
use anchor_spl::token_2022::Token2022;
use anchor_spl::token_interface::{Mint, TokenAccount, MintTo, mint_to};


pub fn recover_mint(ctx: Context<RecoverMint>) -> Result<()> {

    let unwrapped_mint_vault = &ctx.accounts.unwrapped_mint_vault;
    let unwrapped_mint_vault_key = unwrapped_mint_vault.key();
    let unwrapped_mint = &ctx.accounts.unwrapped_mint;
    let wrapped_mint = &ctx.accounts.wrapped_mint;
    let wrapped_mint_total_supply = wrapped_mint.supply;
    let unwrapped_mint_vault_balance = unwrapped_mint_vault.amount;

    require!(unwrapped_mint_vault_balance > wrapped_mint_total_supply, TokenizationWrapError::InsufficientBalance);
    
    let wrapped_mint_state = &ctx.accounts.wrapped_mint_state;
    let wrapped_mint_account = &ctx.accounts.wrapped_mint_account;
    let wrapped_mint_account_key = wrapped_mint_account.key();
    let wrapped_mint_key = wrapped_mint.key();
    let unwrapped_mint_key = unwrapped_mint.key();
    let token_program = &ctx.accounts.token_program;
    let wrapped_mint_owner = &ctx.accounts.wrapped_mint_owner;
    let wrapped_mint_owner_key = wrapped_mint_owner.key();


    // wrapped mint seeds
    let wrapped_mint_bump = ctx.bumps.wrapped_mint;
    let wrapped_mint_seeds: &[&[&[u8]]] = &[&[
        WRAPPED_MINT_SEED,
        unwrapped_mint_key.as_ref(),
        &wrapped_mint_state.salt,
        &[wrapped_mint_bump],
    ]];

    let cpi_accounts = MintTo {
        mint: wrapped_mint.to_account_info(),
        to: wrapped_mint_account.to_account_info(),
        authority: wrapped_mint.to_account_info(),
    };
    
    let cpi_ctx = CpiContext::new_with_signer(token_program.to_account_info(), cpi_accounts, wrapped_mint_seeds);
    
    mint_to(cpi_ctx, unwrapped_mint_vault_balance - wrapped_mint_total_supply)?;

    emit!(RecoverMintEvent {
        wrapped_mint_owner: wrapped_mint_owner_key,
        unwrapped_mint: unwrapped_mint_key,
        wrapped_mint: wrapped_mint_key,
        unwrapped_mint_vault: unwrapped_mint_vault_key,
        wrapped_mint_account: wrapped_mint_account_key,
        unwrapped_mint_vault_balance: unwrapped_mint_vault_balance,
        wrapped_mint_total_supply: wrapped_mint_total_supply,
        recovered_amount: unwrapped_mint_vault_balance - wrapped_mint_total_supply,
    });

    msg!("Unwrapped mint: {}", unwrapped_mint_key);
    msg!("Wrapped mint: {}", wrapped_mint_key);
    msg!("Unwrapped mint vault: {}", unwrapped_mint_vault_key);
    msg!("Wrapped mint account: {}", wrapped_mint_account_key);
    msg!("Unwrapped mint vault balance: {}", unwrapped_mint_vault_balance);
    msg!("Wrapped mint total supply: {}", wrapped_mint_total_supply);
    msg!("Recovered amount: {}", (unwrapped_mint_vault_balance - wrapped_mint_total_supply));

    Ok(())
}


#[derive(Accounts)]
pub struct RecoverMint<'info> {
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
        mut,
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

    /// Owner's wrapped account (destination)
    #[account(
        init_if_needed,
        payer = wrapped_mint_owner,
        associated_token::mint = wrapped_mint,
        associated_token::authority = wrapped_mint_owner,
        associated_token::token_program = token_program,
    )]
    pub wrapped_mint_account: InterfaceAccount<'info, TokenAccount>,

    /// The wrapped mint vault account holding unwrapped tokens
    #[account(
        mut,
        associated_token::mint = unwrapped_mint,
        associated_token::authority = wrapped_mint, // wrapped mint is authority, holding unwrapped tokens
        associated_token::token_program = token_program,
        constraint = (wrapped_mint_state.unwrapped_mint_vault == unwrapped_mint_vault.key()) @ TokenizationWrapError::InvalidUnwrappedMintVault,
    )]
    pub unwrapped_mint_vault: InterfaceAccount<'info, TokenAccount>,

    pub token_program: Program<'info, Token2022>,
    pub associated_token_program: Program<'info, AssociatedToken>,
    pub system_program: Program<'info, System>,
}

#[event]
pub struct RecoverMintEvent {
    pub wrapped_mint_owner: Pubkey,
    pub unwrapped_mint: Pubkey,
    pub wrapped_mint: Pubkey,
    pub unwrapped_mint_vault: Pubkey,
    pub wrapped_mint_account: Pubkey,
    pub unwrapped_mint_vault_balance: u64,
    pub wrapped_mint_total_supply: u64,
    pub recovered_amount: u64,
}