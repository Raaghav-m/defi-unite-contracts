use starknet::ContractAddress;
use super::i_base_escrow::Immutables;
use hello_starknet::libraries::timelocks_lib::Timelocks;

// Define Address type
type Address = ContractAddress;

#[derive(Drop, Serde, starknet::Store)]
struct ExtraDataArgs {
    hashlock_info: felt252,
    dst_chain_id: u256,
    dst_token: Address,
    deposits: u256,
    timelocks: Timelocks,
}

#[derive(Drop, Serde, starknet::Store)]
struct DstImmutablesComplement {
    maker: Address,
    amount: u256,
    token: Address,
    safety_deposit: u256,
    chain_id: u256,
}

#[starknet::interface]
pub trait IEscrowFactory<TContractState> {
    fn get_ESCROW_SRC_IMPLEMENTATION(self: @TContractState) -> ContractAddress;
    fn get_ESCROW_DST_IMPLEMENTATION(self: @TContractState) -> ContractAddress;
    
    fn create_dst_escrow(
        ref self: TContractState,
        dst_immutables: Immutables,
        src_cancellation_timestamp: u256
    );
    
    fn address_of_escrow_src(
        self: @TContractState,
        immutables: Immutables
    ) -> ContractAddress;
    
    fn address_of_escrow_dst(
        self: @TContractState,
        immutables: Immutables
    ) -> ContractAddress;
}
