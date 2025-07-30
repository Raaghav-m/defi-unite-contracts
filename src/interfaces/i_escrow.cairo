use super::i_base_escrow::Immutables;

#[starknet::interface]
pub trait IEscrow<TContractState> {
    // Base escrow functions
    fn withdraw(ref self: TContractState, secret: felt252, immutables: Immutables);
    fn get_RESCUE_DELAY(self: @TContractState) -> felt252;
    fn get_FACTORY(self: @TContractState) -> starknet::ContractAddress;
    
    // Additional function specific to IEscrow
    fn get_PROXY_BYTECODE_HASH(self: @TContractState) -> felt252;
}
