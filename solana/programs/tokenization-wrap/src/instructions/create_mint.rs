use crate::constants::*;
use crate::errors::TokenizationWrapError;
use anchor_lang::prelude::*;
use anchor_lang::solana_program;
use anchor_lang::solana_program::program::{invoke, invoke_signed};
use anchor_spl::associated_token::AssociatedToken;
use anchor_spl::token_interface::{token_metadata_initialize, TokenMetadataInitialize};
use anchor_spl::token_interface::{Mint, Token2022, TokenAccount};
use spl_token_2022_v9::{
    extension::{
        confidential_transfer, default_account_state, metadata_pointer, pausable, scaled_ui_amount,
        transfer_hook, ExtensionType,
    },
    instruction::{
        initialize_mint2, initialize_mint_close_authority, initialize_permanent_delegate,
    },
    pod::PodMint,
    state::AccountState,
};

pub fn create_mint(
    ctx: Context<CreateMint>,
    salt: [u8; 32],
    name: String,
    symbol: String,
    uri: String,
) -> Result<()> {
    // Validate inputs
    require!(name.len() <= 64, TokenizationWrapError::NameTooLong);
    require!(symbol.len() <= 32, TokenizationWrapError::SymbolTooLong);
    require!(uri.len() <= 512, TokenizationWrapError::UriTooLong);

    let wrapped_mint_state = &mut ctx.accounts.wrapped_mint_state;
    let wrapped_mint_state_key = wrapped_mint_state.key();
    let unwrapped_mint = &ctx.accounts.unwrapped_mint;
    let unwrapped_mint_key = unwrapped_mint.key();
    let unwrapped_mint_vault = &ctx.accounts.unwrapped_mint_vault;
    let unwrapped_mint_vault_key = unwrapped_mint_vault.key();

    let wrapped_mint_owner = &ctx.accounts.wrapped_mint_owner;
    let wrapped_mint_owner_key = wrapped_mint_owner.key();
    let rent = &ctx.accounts.rent;
    let wrapped_mint = &ctx.accounts.wrapped_mint;
    let wrapped_mint_key = wrapped_mint.key();
    let token_program = &ctx.accounts.token_program;
    let system_program = &ctx.accounts.system_program;

    // wrapped mint seeds
    let wrapped_mint_bump = ctx.bumps.wrapped_mint;
    let wrapped_mint_seeds: &[&[&[u8]]] = &[&[
        WRAPPED_MINT_SEED,
        unwrapped_mint_key.as_ref(),
        &salt,
        &[wrapped_mint_bump],
    ]];

    // Initialize Token-2022 mint with extensions
    // Calculate required extensions
    let mut extension_types = Vec::new();
    extension_types.push(ExtensionType::MetadataPointer);
    extension_types.push(ExtensionType::PermanentDelegate);
    extension_types.push(ExtensionType::TransferHook);
    extension_types.push(ExtensionType::DefaultAccountState);
    extension_types.push(ExtensionType::Pausable);
    extension_types.push(ExtensionType::MintCloseAuthority);
    extension_types.push(ExtensionType::ScaledUiAmount);
    extension_types.push(ExtensionType::ConfidentialTransferMint);
    // extension_types.push(ExtensionType::TokenMetadata); // ExtensionType::TokenMetadata => unreachable!(),

    let space = ExtensionType::try_calculate_account_len::<PodMint>(&extension_types)
        .map_err(|_| TokenizationWrapError::InvalidAccountData)?;

    // Create account with required space
    invoke_signed(
        &solana_program::system_instruction::create_account(
            &wrapped_mint_owner_key,
            &wrapped_mint_key,
            rent.minimum_balance(space),
            space as u64,
            &spl_token_2022_v9::ID,
        ),
        &[
            wrapped_mint_owner.to_account_info(),
            wrapped_mint.to_account_info(),
        ],
        wrapped_mint_seeds,
    )?;

    // Initialize extensions before mint initialization

    // 1. Metadata Pointer Extension
    invoke(
        &metadata_pointer::instruction::initialize(
            &spl_token_2022_v9::ID,
            &wrapped_mint_key,
            Some(wrapped_mint_owner_key),
            Some(wrapped_mint_key), // Metadata stored in mint account itself
        )?,
        &[wrapped_mint.to_account_info()],
    )?;

    // 2. Permanent Delegate Extension
    invoke(
        &initialize_permanent_delegate(
            &spl_token_2022_v9::ID,
            &wrapped_mint_key,
            &wrapped_mint_owner_key,
        )?,
        &[wrapped_mint.to_account_info()],
    )?;

    // 3. Transfer Hook Extension
    invoke(
        &transfer_hook::instruction::initialize(
            &spl_token_2022_v9::ID,
            &wrapped_mint_key,
            Some(wrapped_mint_owner_key),
            None,
        )?,
        &[wrapped_mint.to_account_info()],
    )?;

    // 4. Default Account State Extension
    invoke(
        &default_account_state::instruction::initialize_default_account_state(
            &spl_token_2022_v9::ID,
            &wrapped_mint_key,
            &AccountState::Initialized, // default is initialized
        )?,
        &[wrapped_mint.to_account_info()],
    )?;

    // 5. Pausable Extension
    invoke(
        &pausable::instruction::initialize(
            &spl_token_2022_v9::ID,
            &wrapped_mint_key,
            &wrapped_mint_owner_key,
        )?,
        &[wrapped_mint.to_account_info()],
    )?;

    // 6 Mint Close Authority
    invoke(
        &initialize_mint_close_authority(
            &spl_token_2022_v9::ID,
            &wrapped_mint_key,
            Some(&wrapped_mint_owner_key),
        )?,
        &[wrapped_mint.to_account_info()],
    )?;

    // 7. Scaled UI Amount Config Extension
    invoke(
        &scaled_ui_amount::instruction::initialize(
            &spl_token_2022_v9::ID,
            &wrapped_mint_key,
            Some(wrapped_mint_owner_key),
            1.0, // default is 1
        )?,
        &[wrapped_mint.to_account_info()],
    )?;

    // 8. Confidential Transfer Extension
    // Enables private transactions and specifies an auditor that can decrypt transaction amounts for compliance
    invoke(
        &confidential_transfer::instruction::initialize_mint(
            &spl_token_2022_v9::ID,
            &wrapped_mint_key,
            Some(wrapped_mint_owner_key),
            false, // false , same as xStock's implementation
            None,  // None, same as xStock's implementation
        )?,
        &[wrapped_mint.to_account_info()],
    )?;

    // 9. Initialize the mint itself
    invoke(
        &initialize_mint2(
            &spl_token_2022_v9::ID,
            &wrapped_mint_key,
            &wrapped_mint_key,
            Some(&wrapped_mint_owner_key), // freeze authority
            unwrapped_mint.decimals,
        )?,
        &[wrapped_mint.to_account_info(), rent.to_account_info()],
    )?;

    // 10. Initialize Token Metadata (always included)
    let cpi_accounts = TokenMetadataInitialize {
        program_id: token_program.to_account_info(),
        mint: wrapped_mint.to_account_info(),
        metadata: wrapped_mint.to_account_info(), // metadata stored in mint account itself
        mint_authority: wrapped_mint.to_account_info(),
        update_authority: wrapped_mint_owner.to_account_info(),
    };
    let cpi_ctx = CpiContext::new_with_signer(
        token_program.to_account_info(),
        cpi_accounts,
        wrapped_mint_seeds,
    );

    token_metadata_initialize(cpi_ctx, name.clone(), symbol.clone(), uri.clone())?;

    // wrapped mint lamports truly need
    let wrapped_mint_lamports_needed = Rent::get()?.minimum_balance(wrapped_mint.data_len());
    let wrapped_mint_lamports_truly = wrapped_mint.lamports();
    if wrapped_mint_lamports_needed > wrapped_mint_lamports_truly {
        let extra_lamports = wrapped_mint_lamports_needed - wrapped_mint_lamports_truly;
        invoke(
            &solana_program::system_instruction::transfer(
                &wrapped_mint_owner_key,
                &wrapped_mint_key,
                extra_lamports,
            ),
            &[
                wrapped_mint_owner.to_account_info(),
                wrapped_mint.to_account_info(),
                system_program.to_account_info(),
            ],
        )?;
    }

    // Store backpointer data
    wrapped_mint_state.unwrapped_mint = unwrapped_mint_key;
    wrapped_mint_state.unwrapped_mint_vault = unwrapped_mint_vault_key;
    wrapped_mint_state.wrapped_mint = wrapped_mint_key;
    wrapped_mint_state.salt = salt;
    wrapped_mint_state.wrapped_mint_owner = wrapped_mint_owner_key;
    wrapped_mint_state.wrapped_mint_pending_owner = pubkey!("11111111111111111111111111111111");

    emit!(CreateMintEvent {
        wrapped_mint_owner: wrapped_mint_owner_key,
        unwrapped_mint: unwrapped_mint_key,
        wrapped_mint: wrapped_mint_key,
        unwrapped_mint_vault: unwrapped_mint_vault_key,
        wrapped_mint_state: wrapped_mint_state_key,
    });

    msg!("warp mint owner : {}", wrapped_mint_owner_key);
    msg!("warp mint state : {}", wrapped_mint_state_key);
    msg!("wrapped mint : {}", wrapped_mint_key);
    msg!("unwrapped mint : {}", unwrapped_mint_key);
    msg!("unwrapped mint vault : {}", unwrapped_mint_vault_key);

    Ok(())
}

#[derive(Accounts)]
#[instruction(salt:[u8; 32], name: String, symbol: String, uri: String)]
pub struct CreateMint<'info> {
    // create mint user
    #[account(mut)]
    pub wrapped_mint_owner: Signer<'info>,

    // unwrapped mint to be wrapped
    #[account(
        constraint = (unwrapped_mint.to_account_info().owner == &spl_token_2022_v9::ID) @ TokenizationWrapError::InvalidUnwrappedMint
    )]
    pub unwrapped_mint: InterfaceAccount<'info, Mint>,

    // new wrapped mint, account not created now ,onwer is 11111111111111111111111111111111
    /// CHECK: PDA that will be the wrapped_mint
    #[account(
        mut,
        seeds=[WRAPPED_MINT_SEED,&unwrapped_mint.key().as_ref(),&salt],
        bump,
    )]
    pub wrapped_mint: UncheckedAccount<'info>,

    // wrapped mint state
    #[account(
        init,
        seeds = [WRAPPED_MINT_STATE_SEED, &wrapped_mint.key().as_ref()],
        bump,
        payer = wrapped_mint_owner,
        space = ANCHOR_DISCRIMINATOR_SIZE + WrappedMintState::INIT_SPACE,
    )]
    pub wrapped_mint_state: Account<'info, WrappedMintState>,

    /// The wrapped mint vault account holding unwrapped tokens
    #[account(
        init_if_needed,
        payer = wrapped_mint_owner,
        associated_token::mint = unwrapped_mint,
        associated_token::authority = wrapped_mint, // wrapped mint is authority, holding unwrapped tokens
        associated_token::token_program = token_program,
    )]
    pub unwrapped_mint_vault: InterfaceAccount<'info, TokenAccount>,

    pub token_program: Program<'info, Token2022>,
    pub associated_token_program: Program<'info, AssociatedToken>,
    pub rent: Sysvar<'info, Rent>,
    pub system_program: Program<'info, System>,
}

#[account]
#[derive(InitSpace)]
pub struct WrappedMintState {
    #[max_len(32)]
    pub salt: [u8; 32],
    pub wrapped_mint: Pubkey,
    pub wrapped_mint_owner: Pubkey,
    pub wrapped_mint_pending_owner: Pubkey,
    pub unwrapped_mint: Pubkey,
    pub unwrapped_mint_vault: Pubkey,
}

#[event]
pub struct CreateMintEvent {
    pub wrapped_mint_owner: Pubkey,
    pub unwrapped_mint: Pubkey,
    pub wrapped_mint: Pubkey,
    pub unwrapped_mint_vault: Pubkey,
    pub wrapped_mint_state: Pubkey,
}
