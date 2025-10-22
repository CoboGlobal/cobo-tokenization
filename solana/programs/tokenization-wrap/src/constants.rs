pub const ANCHOR_DISCRIMINATOR_SIZE: usize = 8;
pub const PUBKEY_SIZE: usize = 32;
pub const U8_SIZE: usize = 1;
pub const U16_SIZE: usize = 2;
pub const U32_SIZE: usize = 4;
pub const U64_SIZE: usize = 8;
pub const U128_SIZE: usize = 16;
pub const STRING_LENGTH_PREFIX: usize = 4;
pub const MAX_LENGTH: usize = 50;
pub const WRAPPED_MINT_SIZE: usize = 400;

// seeds
// create mint
pub const UNWRAPPED_MINT_VAULT_SEED: &[u8] = b"unwrapped_mint_vault";
pub const WRAPPED_MINT_SEED: &[u8] = b"wrapped_mint";
pub const WRAPPED_MINT_STATE_SEED: &[u8] = b"wrapped_mint_state";

// role
pub const WRAPPED_ROLE_SEED: &[u8] = b"wrapped_role";
