use starknet::ContractAddress;
use super::i_base_escrow::Immutables;

/// Interface for the source escrow contract in cross-chain atomic swaps
#[starknet::interface]
pub trait IEscrowSrc<TContractState> {
    /// Withdraws funds from escrow to the caller (taker) using the secret.
    /// Can only be called by the taker during the private withdrawal period.
    /// @param secret The secret that unlocks the escrow
    /// @param immutables The immutable values used to deploy the escrow contract
    fn withdraw(ref self: TContractState, secret: felt252, immutables: Immutables);

    /// Withdraws funds from escrow to a specified target address using the secret.
    /// Can only be called by the taker during the private withdrawal period.
    /// @param secret The secret that unlocks the escrow
    /// @param target The address to transfer ERC20 tokens to
    /// @param immutables The immutable values used to deploy the escrow contract
    fn withdraw_to(
        ref self: TContractState, 
        secret: felt252, 
        target: ContractAddress, 
        immutables: Immutables
    );

    /// Public withdrawal function that can be called by access token holders.
    /// Can only be called during the public withdrawal period.
    /// Transfers funds to the taker address specified in immutables.
    /// @param secret The secret that unlocks the escrow
    /// @param immutables The immutable values used to deploy the escrow contract
    fn public_withdraw(ref self: TContractState, secret: felt252, immutables: Immutables);

    /// Public cancellation function that can be called by access token holders.
    /// Can only be called during the public cancellation period.
    /// Returns funds to the maker.
    /// @param immutables The immutable values used to deploy the escrow contract
    fn public_cancel(ref self: TContractState, immutables: Immutables);
}
