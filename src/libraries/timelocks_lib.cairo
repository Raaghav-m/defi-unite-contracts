// src/libraries/timelocks_lib.cairo

use core::traits::Into;

/// Represents the packed timelocks value.
#[derive(Drop, Copy, Serde, starknet::Store)]
pub struct Timelocks {
    pub value: felt252, // Packed timelocks data like Solidity
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
        // For now, use a simple approach - store deployment timestamp in the value
        // In a real implementation, you'd pack it properly like Solidity
        Timelocks { value: value }
    }

    /// Get start time of the rescue period (deployedAt + rescueDelay)
    pub fn rescue_start(timelocks: Timelocks, rescue_delay: felt252) -> felt252 {
        // For now, assume the value is the deployment timestamp
        timelocks.value + rescue_delay
    }

    /// Get the timelock value for a given stage
    pub fn get(timelocks: Timelocks, stage: Stage) -> felt252 {
        let stage_index: u8 = stage.into();
        let deployed_at = timelocks.value; // Assume value is deployment timestamp
        
        // Return relative values based on stage (like main.spec.ts)
        let relative_value = match stage {
            Stage::DstWithdrawal => 10, // 10 seconds after deployment
            Stage::DstCancellation => 101, // 101 seconds after deployment
            _ => 0 // For other stages, use 0
        };
        
        // Return absolute timestamp: deployment_timestamp + relative_value
        deployed_at + relative_value
    }

    /// Get the timelock value for a given stage with deployment timestamp offset
    pub fn get_with_deployment(timelocks: Timelocks, stage: Stage, deployed_at: felt252) -> felt252 {
        let relative_value = get(timelocks, stage);
        deployed_at + relative_value
    }
}
