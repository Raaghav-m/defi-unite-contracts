use starknet::ContractAddress;
use hello_starknet::libraries::timelocks_lib::Timelocks;

// Define Address type
type Address = ContractAddress;

#[derive(Drop, Copy, Serde, starknet::Store)]
pub struct Immutables {
    pub order_hash: felt252,
    pub hashlock: felt252,
    pub maker: Address,
    pub taker: Address,
    pub token: Address,
    pub amount: u256,
    pub safety_deposit: u256,
    pub timelocks: Timelocks,
}

#[starknet::interface]
pub trait IBaseEscrow<TContractState> {
    fn withdraw(ref self: TContractState, secret: felt252, immutables: Immutables);
    fn get_RESCUE_DELAY(self: @TContractState) -> felt252;
    fn get_FACTORY(self: @TContractState) -> ContractAddress;
}
