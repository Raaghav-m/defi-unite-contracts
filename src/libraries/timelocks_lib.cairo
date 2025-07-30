// src/libraries/timelocks_lib.cairo

use core::traits::Into;

/// Represents the packed timelocks value.
#[derive(Drop, Copy, Serde, starknet::Store)]
pub struct Timelocks {
    pub value: felt252,
}

/// Enum representing timelock stages.
/// Each stage occupies 32 bits in the `Timelocks.value`.
#[derive(Drop, Copy)]
pub enum Stage {
    SrcWithdrawal,
    SrcPublicWithdrawal,
    SrcCancellation,
    SrcPublicCancellation,
    DstWithdrawal,
    DstPublicWithdrawal,
    DstCancellation,
}

impl StageIntoU8 of Into<Stage, u8> {
    fn into(self: Stage) -> u8 {
        match self {
            Stage::SrcWithdrawal => 0,
            Stage::SrcPublicWithdrawal => 1,
            Stage::SrcCancellation => 2,
            Stage::SrcPublicCancellation => 3,
            Stage::DstWithdrawal => 4,
            Stage::DstPublicWithdrawal => 5,
            Stage::DstCancellation => 6,
        }
    }
}

/// Constants for bit manipulation.
/// Using smaller mask that fits in felt252
const DEPLOYED_AT_MASK: felt252 = 0xffffffff000000000000000000000000000000000000000000000000;
const DEPLOYED_AT_OFFSET: u8 = 224;

pub mod TimelocksLib {
    use super::*;

    /// Set deployment timestamp (stored in top 32 bits)
    pub fn set_deployed_at(timelocks: Timelocks, value: felt252) -> Timelocks {
        // Simple implementation without bitwise operations for now
        Timelocks { value: value }
    }

    /// Get start time of the rescue period (deployedAt + rescueDelay)
    pub fn rescue_start(timelocks: Timelocks, rescue_delay: felt252) -> felt252 {
        // Simple implementation - in real scenario you'd extract from packed value
        timelocks.value + rescue_delay
    }

    /// Get the timelock value for a given stage
    pub fn get(timelocks: Timelocks, stage: Stage) -> felt252 {
        let _stage_index: u8 = stage.into();
        // Simple implementation - in real scenario you'd extract from packed value
        timelocks.value
    }
}
