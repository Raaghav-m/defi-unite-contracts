use super::i_base_escrow::Immutables;

#[starknet::interface]
pub trait IEscrowDst<TContractState> {
    fn public_withdraw(ref self: TContractState, order: Immutables, preimage: Array<felt252>);
}
