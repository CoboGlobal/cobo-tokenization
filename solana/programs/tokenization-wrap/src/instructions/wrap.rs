use anchor_lang::prelude::*;
use anchor_spl::token_2022::{Token2022};
use anchor_spl::token_interface::{
    Mint, TokenAccount,
    TransferChecked, MintTo, transfer_checked, mint_to,
};
use anchor_spl::associated_token::AssociatedToken;
use crate::constants::*;
use crate::errors::TokenizationWrapError;
use crate::instructions::role::RoleState;
use crate::instructions::role::RoleKind;
use crate::instructions::create_mint::WrappedMintState;

pub fn wrap(ctx: Context<Wrap>, amount: u64) -> Result<()> {
    // Validate amount
    require!(amount > 0, TokenizationWrapError::InsufficientBalance);

    let user = &ctx.accounts.user;
    let user_key = user.key();
    let unwrapped_mint = &ctx.accounts.unwrapped_mint;
    let unwrapped_mint_key = unwrapped_mint.key();
    let wrapped_mint = &ctx.accounts.wrapped_mint;
    let wrapped_mint_key = wrapped_mint.key();
    let wrapped_mint_state = &ctx.accounts.wrapped_mint_state;
    let wrapped_mint_account = &ctx.accounts.wrapped_mint_account;
    let unwrapped_mint_vault = &ctx.accounts.unwrapped_mint_vault;
    let unwrapped_mint_account = &ctx.accounts.unwrapped_mint_account;
    let token_program = &ctx.accounts.token_program;
    
    // Transfer unwrapped tokens to vault
    let cpi_accounts = TransferChecked {
        from: unwrapped_mint_account.to_account_info(),
        to: unwrapped_mint_vault.to_account_info(),
        authority: user.to_account_info(),
        mint: unwrapped_mint.to_account_info(),
    };
    let cpi_ctx = CpiContext::new(token_program.to_account_info(), cpi_accounts);
    
    transfer_checked(
        cpi_ctx,
        amount,
        unwrapped_mint.decimals,
    )?;

    // Mint wrapped tokens to user
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
    
    mint_to(cpi_ctx, amount)?;

    emit!(WrapEvent {
        user: user_key,
        unwrapped_mint: unwrapped_mint_key,
        wrapped_mint: wrapped_mint_key,
        amount: amount,
    });

    msg!("User: {}", user_key);
    msg!("Wrapped amount: {}", amount);
    msg!("From mint: {}", unwrapped_mint_key);
    msg!("To mint: {}", wrapped_mint_key);
    
    Ok(())
}



#[derive(Accounts)]
#[instruction(amount: u64)]
pub struct Wrap<'info> {
    // wrap user
    #[account(mut)]
    pub user: Signer<'info>,    

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

    // wrap user role check
    #[account(
        seeds=[WRAPPED_ROLE_SEED,&wrapped_mint.key().as_ref(),&[RoleKind::Wrapper.as_u8()],user.key().as_ref()],
        bump,
        constraint = (user_role.user == user.key() && user_role.role == RoleKind::Wrapper) @ TokenizationWrapError::Unauthorized, 
    )]
    pub user_role: Account<'info, RoleState>,
    
    /// User's unwrapped account (source)
    #[account(
        mut,
        associated_token::mint = unwrapped_mint,
        associated_token::authority = user,
        associated_token::token_program = token_program,
    )]
    pub unwrapped_mint_account: InterfaceAccount<'info, TokenAccount>,
    
    /// User's wrapped account (destination)
    #[account(
        init_if_needed,
        payer = user,
        associated_token::mint = wrapped_mint,
        associated_token::authority = user,
        associated_token::token_program = token_program,
    )]
    pub wrapped_mint_account: InterfaceAccount<'info, TokenAccount>,
    
    /// The wrapped mint vault account holding unwrapped tokens
    #[account(
        init_if_needed, // if close vault, this account will be closed, so we need to init it if needed
        payer = user,
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
pub struct WrapEvent {
    pub user: Pubkey,
    pub unwrapped_mint: Pubkey,
    pub wrapped_mint: Pubkey,
    pub amount: u64,
}
