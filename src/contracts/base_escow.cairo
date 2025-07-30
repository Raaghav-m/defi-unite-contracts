// src/contracts/base_escrow.cairo

#[contract]
mod base_escrow {
    use starknet::contract::contract;
    use starknet::context::{get_caller_address, get_block_timestamp};
    use starknet::traits::Into;
    use starknet::keccak::keccak;
    use core::traits::TryInto;

    use interfaces::base_escrow::{Immutables, IBaseEscrow, InvalidCaller, InvalidSecret, InvalidTime, NativeTokenSendingFailure, FundsRescued};
    use libraries::immutables_lib::ImmutablesLib;
    use libraries::timelocks_lib::{Timelocks, TimelocksLib};
    use traits::IERC20;

    #[storage]
    struct Storage {
        rescue_delay: u32,
        access_token: ContractAddress,
        factory: ContractAddress,
    }

    #[event]
    fn FundsRescued(token: ContractAddress, amount: u256);

    #[constructor]
    fn constructor(rescue_delay: u32, access_token: ContractAddress) {
        self.rescue_delay.write(rescue_delay);
        self.access_token.write(access_token);
        self.factory.write(get_caller_address());
    }

    #[external]
    fn rescue_funds(token: ContractAddress, amount: u256, immutables: Immutables) {
        self.only_taker(immutables);
        self.only_valid_immutables(immutables);
        let delay = self.rescue_delay.read().into();
        let start = TimelocksLib::rescue_start(immutables.timelocks, delay);
        self.only_after(start);
        self.uni_transfer(token, get_caller_address(), amount);
        FundsRescued(token, amount);
    }

    // ---------------- MODIFIERS ----------------

    fn only_taker(immutables: Immutables) {
        if get_caller_address() != immutables.taker.get() {
            panic_with(InvalidCaller {});
        }
    }

    fn only_valid_immutables(immutables: Immutables) {
        self.validate_immutables(immutables);
    }

    fn only_valid_secret(secret: felt252, immutables: Immutables) {
        let hash = self.keccak_bytes32(secret);
        if hash != immutables.hashlock {
            panic_with(InvalidSecret {});
        }
    }

    fn only_after(start: u64) {
        if get_block_timestamp() < start {
            panic_with(InvalidTime {});
        }
    }

    fn only_before(stop: u64) {
        if get_block_timestamp() >= stop {
            panic_with(InvalidTime {});
        }
    }

    fn only_access_token_holder() {
        let token = self.access_token.read();
        let balance = IERC20::balance_of(token, get_caller_address());
        if balance == 0 {
            panic_with(InvalidCaller {});
        }
    }

    // ------------- INTERNAL LOGIC -------------

    fn uni_transfer(token: ContractAddress, to: ContractAddress, amount: u256) {
        if token == 0.into() {
            self.eth_transfer(to, amount);
        } else {
            let success = IERC20::transfer(token, to, amount);
            if !success {
                panic_with(NativeTokenSendingFailure {});
            }
        }
    }

    fn eth_transfer(to: ContractAddress, amount: u256) {
        // In Starknet this is typically disabled unless implementing L2 ETH (e.g., via a custom ETH contract)
        panic_with(NativeTokenSendingFailure {});
    }

    // Abstract: to be implemented by inheriting contracts
    fn validate_immutables(immutables: Immutables) {
        // virtual
        panic("Must override validate_immutables");
    }

    fn keccak_bytes32(secret: felt252) -> felt252 {
        // Hash 32 bytes (assume packed secret)
        let mut data = ArrayTrait::new();
        data.append(secret);
        return keccak(data);
    }
}
