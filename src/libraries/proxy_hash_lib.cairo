// src/libraries/proxy_hash_lib.cairo

use core::keccak::keccak_u256s_be_inputs;
use core::array::ArrayTrait;
use core::traits::Into;

/// @title Library to compute the hash of proxy bytecode.
/// @notice Mimics the hashing logic used in Solidity via assembly.
pub mod ProxyHashLib {
    use super::*;
    
    /// Computes the hash of the proxy bytecode concatenated with the implementation address.
    pub fn compute_proxy_bytecode_hash(implementation: felt252) -> felt252 {
        let mut data: Array<u256> = ArrayTrait::new();

        // This mimics the Solidity "proxy pattern" bytecode
        // First part of the proxy bytecode (prefix before the address)
        data.append(0x3d602d80600a3d3981f3_u256); // Bytecode preamble
        // Middle part: implementation address
        data.append(implementation.into());
        // Last part of the bytecode (suffix after the address)
        data.append(0x5af43d82803e903d91602b57fd5bf3_u256); // Bytecode suffix

        // Compute keccak over the full bytecode array
        let hash = keccak_u256s_be_inputs(data.span());
        hash.low.into()
    }
}
