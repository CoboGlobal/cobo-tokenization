use anchor_lang::prelude::*;

#[error_code]
pub enum TokenizationWrapError {
    #[msg("Not owner")]
    NotOwner,

    #[msg("Not pending owner")]
    NotPendingOwner,

    #[msg("Un authorized")]
    Unauthorized,

    #[msg("Name too long")]
    NameTooLong,

    #[msg("Symbol too long")]
    SymbolTooLong,

    #[msg("URI too long")]
    UriTooLong,

    #[msg("Invalid unwrapped mint")]
    InvalidUnwrappedMint,

    #[msg("Invalid wrapped mint")]
    InvalidWrappedMint,

    #[msg("Insufficient balance")]
    InsufficientBalance,

    #[msg("Invalid account data")]
    InvalidAccountData,

    #[msg("Invalid unwrapped mint vault")]
    InvalidUnwrappedMintVault,

    #[msg("Invalid role")]
    InvalidRole,
}
