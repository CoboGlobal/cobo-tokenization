use anchor_lang::prelude::*;

use crate::constants::*;
use crate::errors::TokenizationWrapError;
use crate::instructions::create_mint::WrappedMintState;
use anchor_spl::token_interface::Mint;

pub fn add_role(ctx: Context<AddRole>, user: Pubkey, role: u8) -> Result<()> {
    let user_role = &mut ctx.accounts.user_role;
    let wrapped_mint = &ctx.accounts.wrapped_mint;
    user_role.wrapped_mint = wrapped_mint.key();
    user_role.user = user;
    user_role.role = RoleKind::from_u8(role)?;

    msg!("wrapped mint: {:?}", wrapped_mint.key());
    msg!("role account: {:?}", user_role.key());
    msg!("user: {:?}", user_role.user);
    msg!("user role: {:?}", user_role.role);

    return Ok(());
}

pub fn remove_role(ctx: Context<RemoveRole>, user: Pubkey, role: u8) -> Result<()> {
    let user_role = &ctx.accounts.user_role;
    let wrapped_mint = &ctx.accounts.wrapped_mint;

    msg!("wrapped mint: {:?}", wrapped_mint.key());
    msg!("role account: {:?}", user_role.key());
    msg!("user: {:?}", user);
    msg!("user role: {:?}", role);

    return Ok(());
}

#[derive(Accounts)]
#[instruction(user: Pubkey,role: u8)]
pub struct AddRole<'info> {
    // wrapped mint owner
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

    // user role
    #[account(
        init,
        seeds=[WRAPPED_ROLE_SEED,&wrapped_mint.key().as_ref(),&[role],&user.as_ref()],
        bump,
        payer = wrapped_mint_owner,
        space = ANCHOR_DISCRIMINATOR_SIZE + RoleState::INIT_SPACE,
    )]
    pub user_role: Account<'info, RoleState>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
#[instruction(user: Pubkey,role: u8)]
pub struct RemoveRole<'info> {
    // wrapped mint owner
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

    // user role
    #[account(
        mut,
        seeds=[WRAPPED_ROLE_SEED,&wrapped_mint.key().as_ref(),&[role],&user.as_ref()],
        bump,
        close = wrapped_mint_owner,
    )]
    pub user_role: Account<'info, RoleState>,
}

#[account]
#[derive(InitSpace)]
pub struct RoleState {
    pub wrapped_mint: Pubkey,
    pub user: Pubkey,
    #[max_len(32)]
    pub role: RoleKind,
}

#[derive(AnchorSerialize, AnchorDeserialize, Clone, Copy, PartialEq, Eq, Debug, InitSpace)]
#[repr(u8)]
pub enum RoleKind {
    Default = 0, // default role, no special permissions
    Wrapper = 1,
}

impl RoleKind {
    pub fn as_u8(self) -> u8 {
        self as u8
    }

    pub fn from_u8(value: u8) -> Result<Self> {
        match value {
            // 0 => Ok(RoleKind::Default),
            1 => Ok(RoleKind::Wrapper),
            _ => err!(TokenizationWrapError::InvalidRole),
        }
    }
}