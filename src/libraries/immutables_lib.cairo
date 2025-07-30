// src/libraries/immutables_lib.cairo

use core::keccak::keccak_u256s_be_inputs;
use core::array::ArrayTrait;
use core::traits::Into;
use super::super::interfaces::i_base_escrow::Immutables;

/// Constant: size of the serialized Immutables struct (analogous to 0x100)
const ESCROW_IMMUTABLES_SIZE: usize = 256;

/// @title Library for escrow immutables.
/// @notice Mimics Solidity's keccak hashing of calldata and memory versions of Immutables.
pub mod ImmutablesLib {
    use super::*;
    
    /// Hashes an `Immutables` struct (calldata-style).
    pub fn hash(immutables: Immutables) -> felt252 {
        let serialized: Array<u256> = serialize_immutables(immutables);
        let hash = keccak_u256s_be_inputs(serialized.span());
        hash.low.into()
    }

    /// Hashes an `Immutables` struct (memory-style).
    pub fn hash_mem(immutables: Immutables) -> felt252 {
        let serialized: Array<u256> = serialize_immutables(immutables);
        let hash = keccak_u256s_be_inputs(serialized.span());
        hash.low.into()
    }
}

/// Serializes the struct fields into an array for hashing.
/// Cairo does not have native memory-like pointers or direct byte manipulation,
/// so we flatten the struct manually.
fn serialize_immutables(immutables: Immutables) -> Array<u256> {
    let mut data: Array<u256> = ArrayTrait::new();
    data.append(immutables.order_hash.into());
    data.append(immutables.hashlock.into());
    // Convert ContractAddress to felt252 then to u256
    let maker_felt: felt252 = immutables.maker.into();
    let taker_felt: felt252 = immutables.taker.into();
    let token_felt: felt252 = immutables.token.into();
    data.append(maker_felt.into());
    data.append(taker_felt.into());
    data.append(token_felt.into());
    data.append(immutables.amount);
    data.append(immutables.safety_deposit);
    
    // Serialize timelocks struct (using the packed value)
    data.append(immutables.timelocks.value.into());
    
    data
}
