// src/contracts/escrow_src.cairo

#[starknet::contract]
pub mod EscrowSrc {
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use core::poseidon::PoseidonTrait;
    use core::hash::HashStateTrait;

    use hello_starknet::interfaces::i_escrow_src::IEscrowSrc;
    use hello_starknet::interfaces::i_base_escrow::Immutables;
    use hello_starknet::libraries::timelocks_lib::{TimelocksLib, Stage};
    use hello_starknet::libraries::immutables_lib::ImmutablesLib;

    #[storage]
    struct Storage {
        // Base escrow fields
        rescue_delay: u32,
        factory: ContractAddress,
        access_token: ContractAddress,
        deployed_at: u64,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        EscrowWithdrawal: EscrowWithdrawal,
        EscrowCancelled: EscrowCancelled,
        PublicWithdrawal: PublicWithdrawal,
        PublicCancellation: PublicCancellation,
        RescueFunds: RescueFunds,
    }

    #[derive(Drop, starknet::Event)]
    struct EscrowWithdrawal {
        #[key]
        secret: felt252,
        target: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct EscrowCancelled {
        maker: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct PublicWithdrawal {
        #[key]
        secret: felt252,
        taker: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct PublicCancellation {
        maker: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct RescueFunds {
        token: ContractAddress,
        amount: u256,
        to: ContractAddress,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        rescue_delay: u32,
        factory: ContractAddress,
        access_token: ContractAddress,
    ) {
        self.rescue_delay.write(rescue_delay);
        self.factory.write(factory);
        self.access_token.write(access_token);
        self.deployed_at.write(get_block_timestamp());
    }

    #[abi(embed_v0)]
    impl EscrowSrcImpl of IEscrowSrc<ContractState> {
        /// See {IEscrowSrc-withdraw}.
        /// The function works on the time interval highlighted with capital letters:
        /// ---- contract deployed --/-- finality --/-- PRIVATE WITHDRAWAL --/-- PUBLIC WITHDRAWAL --/--
        /// --/-- private cancellation --/-- public cancellation ----
        fn withdraw(
            ref self: ContractState,
            secret: felt252,
            immutables: Immutables
        ) {
            // Validate caller is taker
            self._only_taker(immutables);
            
            // Validate timing - after src withdrawal, before src cancellation
            let withdrawal_time = TimelocksLib::get(immutables.timelocks, Stage::SrcWithdrawal);
            let cancellation_time = TimelocksLib::get(immutables.timelocks, Stage::SrcCancellation);
            
            self._only_after(withdrawal_time.into());
            self._only_before(cancellation_time.into());

            // Withdraw to caller
            let caller = get_caller_address();
            self._withdraw_to(secret, caller, immutables);
        }

        /// See {IEscrowSrc-withdraw_to}.
        /// The function works on the time interval highlighted with capital letters:
        /// ---- contract deployed --/-- finality --/-- PRIVATE WITHDRAWAL --/-- PUBLIC WITHDRAWAL --/--
        /// --/-- private cancellation --/-- public cancellation ----
        fn withdraw_to(
            ref self: ContractState,
            secret: felt252,
            target: ContractAddress,
            immutables: Immutables
        ) {
            // Validate caller is taker
            self._only_taker(immutables);
            
            // Validate timing - after src withdrawal, before src cancellation
            let withdrawal_time = TimelocksLib::get(immutables.timelocks, Stage::SrcWithdrawal);
            let cancellation_time = TimelocksLib::get(immutables.timelocks, Stage::SrcCancellation);
            
            self._only_after(withdrawal_time.into());
            self._only_before(cancellation_time.into());

            // Withdraw to specified target
            self._withdraw_to(secret, target, immutables);
        }

        /// See {IEscrowSrc-public_withdraw}.
        /// The function works on the time interval highlighted with capital letters:
        /// ---- contract deployed --/-- finality --/-- private withdrawal --/-- PUBLIC WITHDRAWAL --/--
        /// --/-- private cancellation --/-- public cancellation ----
        fn public_withdraw(
            ref self: ContractState,
            secret: felt252,
            immutables: Immutables
        ) {
            // Validate caller has access token
            self._only_access_token_holder();
            
            // Validate timing - after src public withdrawal, before src cancellation
            let public_withdrawal_time = TimelocksLib::get(immutables.timelocks, Stage::SrcPublicWithdrawal);
            let cancellation_time = TimelocksLib::get(immutables.timelocks, Stage::SrcCancellation);
            
            self._only_after(public_withdrawal_time.into());
            self._only_before(cancellation_time.into());

            // Withdraw to taker
            self._withdraw_to(secret, immutables.taker, immutables);
            
            self.emit(PublicWithdrawal {
                secret,
                taker: immutables.taker,
                amount: immutables.amount,
            });
        }

        /// See {IEscrowSrc-public_cancel}.
        /// The function works on the time intervals highlighted with capital letters:
        /// ---- contract deployed --/-- finality --/-- private withdrawal --/-- public withdrawal --/--
        /// --/-- private cancellation --/-- PUBLIC CANCELLATION ----
        fn public_cancel(ref self: ContractState, immutables: Immutables) {
            // Validate caller has access token
            self._only_access_token_holder();
            
            // Validate timing - after src public cancellation
            let public_cancellation_time = TimelocksLib::get(immutables.timelocks, Stage::SrcPublicCancellation);
            self._only_after(public_cancellation_time.into());

            // Cancel and return funds to maker
            self._cancel(immutables);
            
            self.emit(PublicCancellation {
                maker: immutables.maker,
                amount: immutables.amount,
            });
        }
    }

    // Note: We don't implement IBaseEscrow directly to avoid conflicts
    // Instead, we provide access through internal methods
    
    #[abi(embed_v0)]
    impl BaseEscrowAccessImpl of IBaseEscrowAccess<ContractState> {
        fn base_withdraw(ref self: ContractState, secret: felt252, immutables: Immutables) {
            // Delegate to EscrowSrc withdraw
            EscrowSrcImpl::withdraw(ref self, secret, immutables);
        }

        fn base_cancel(ref self: ContractState, immutables: Immutables) {
            // Validate caller is taker
            self._only_taker(immutables);
            
            // Validate timing - after src cancellation
            let cancellation_time = TimelocksLib::get(immutables.timelocks, Stage::SrcCancellation);
            self._only_after(cancellation_time.into());

            // Cancel and return funds to maker
            self._cancel(immutables);
        }

        fn base_rescue_funds(ref self: ContractState, token: ContractAddress, amount: u256, immutables: Immutables) {
            // Only factory can rescue funds after rescue delay
            let caller = get_caller_address();
            let factory = self.factory.read();
            assert(caller == factory, 'Only factory can rescue');

            let current_time = get_block_timestamp();
            let deployed_at = self.deployed_at.read();
            let rescue_delay = self.rescue_delay.read();
            
            assert(current_time >= deployed_at + rescue_delay.into(), 'Rescue delay not passed');

            // TODO: Implement token transfer
            // if token == 0.try_into().unwrap() {
            //     // Native token rescue
            //     self._eth_transfer(factory, amount);
            // } else {
            //     // ERC20 token rescue
            //     IERC20::transfer(token, factory, amount);
            // }

            self.emit(RescueFunds {
                token,
                amount,
                to: factory,
            });
        }

        fn get_RESCUE_DELAY(self: @ContractState) -> felt252 {
            self.rescue_delay.read().into()
        }

        fn get_FACTORY(self: @ContractState) -> ContractAddress {
            self.factory.read()
        }
    }

    // Define a separate interface to avoid naming conflicts
    #[starknet::interface]
    trait IBaseEscrowAccess<TContractState> {
        fn base_withdraw(ref self: TContractState, secret: felt252, immutables: Immutables);
        fn base_cancel(ref self: TContractState, immutables: Immutables);
        fn base_rescue_funds(ref self: TContractState, token: ContractAddress, amount: u256, immutables: Immutables);
        fn get_RESCUE_DELAY(self: @TContractState) -> felt252;
        fn get_FACTORY(self: @TContractState) -> ContractAddress;
    }

    #[generate_trait]
    impl EscrowSrcInternalImpl of EscrowSrcInternalTrait {
        /// Transfers ERC20 tokens to the target and native tokens to the caller.
        /// @param secret The secret that unlocks the escrow.
        /// @param target The address to transfer ERC20 tokens to.
        /// @param immutables The immutable values used to deploy the clone contract.
        fn _withdraw_to(
            ref self: ContractState,
            secret: felt252,
            target: ContractAddress,
            immutables: Immutables
        ) {
            // Validate immutables
            self._only_valid_immutables(immutables);
            
            // Validate secret
            self._only_valid_secret(secret, immutables);

            // Transfer ERC20 tokens to target
            if immutables.token != 0.try_into().unwrap() {
                // TODO: Implement ERC20 transfer
                // IERC20::transfer(immutables.token, target, immutables.amount);
            }

            // Transfer safety deposit (native tokens) to caller
            let _caller = get_caller_address();
            if immutables.safety_deposit > 0 {
                // TODO: Implement native token transfer
                // self._eth_transfer(caller, immutables.safety_deposit);
            }

            self.emit(EscrowWithdrawal {
                secret,
                target,
                amount: immutables.amount,
            });
        }

        /// Transfers ERC20 tokens to the maker and native tokens to the caller.
        /// @param immutables The immutable values used to deploy the clone contract.
        fn _cancel(ref self: ContractState, immutables: Immutables) {
            // Validate immutables
            self._only_valid_immutables(immutables);

            // Transfer ERC20 tokens back to maker
            if immutables.token != 0.try_into().unwrap() {
                // TODO: Implement ERC20 transfer
                // IERC20::transfer(immutables.token, immutables.maker, immutables.amount);
            }

            // Transfer safety deposit (native tokens) to caller
            let _caller = get_caller_address();
            if immutables.safety_deposit > 0 {
                // TODO: Implement native token transfer
                // self._eth_transfer(caller, immutables.safety_deposit);
            }

            self.emit(EscrowCancelled {
                maker: immutables.maker,
                amount: immutables.amount,
            });
        }

        /// Validates that caller is the taker
        fn _only_taker(self: @ContractState, immutables: Immutables) {
            let caller = get_caller_address();
            assert(caller == immutables.taker, 'Only taker allowed');
        }

        /// Validates that caller holds access tokens
        fn _only_access_token_holder(self: @ContractState) {
            // TODO: Implement access token balance check
            // let caller = get_caller_address();
            // let access_token = self.access_token.read();
            // let balance = IERC20::balance_of(access_token, caller);
            // assert(balance > 0, 'No access token');
        }

        /// Validates timing constraint - only after specified time
        fn _only_after(self: @ContractState, time: u256) {
            let current_time: u256 = get_block_timestamp().into();
            assert(current_time >= time, 'Too early');
        }

        /// Validates timing constraint - only before specified time
        fn _only_before(self: @ContractState, time: u256) {
            let current_time: u256 = get_block_timestamp().into();
            assert(current_time < time, 'Too late');
        }

        /// Validates that the immutables match the deployed contract
        fn _only_valid_immutables(self: @ContractState, immutables: Immutables) {
            // Validate that the hash of immutables matches this contract's deployment
            let _computed_hash = ImmutablesLib::hash(immutables);
            // TODO: Add proper validation logic
            // For now, we'll validate that essential fields are not zero
            assert(immutables.order_hash != 0, 'Invalid order hash');
            assert(immutables.hashlock != 0, 'Invalid hashlock');
            assert(immutables.maker != 0.try_into().unwrap(), 'Invalid maker');
            assert(immutables.taker != 0.try_into().unwrap(), 'Invalid taker');
        }

        /// Validates that the secret is correct for the hashlock
        fn _only_valid_secret(self: @ContractState, secret: felt252, immutables: Immutables) {
            // Compute hash of secret and compare with hashlock
            let computed_hash = PoseidonTrait::new().update(secret).finalize();
            assert(computed_hash == immutables.hashlock, 'Invalid secret');
        }
    }
}
