// src/contracts/base_escrow_factory.cairo

#[starknet::contract]
pub mod BaseEscrowFactory {
    use starknet::{ContractAddress, get_block_timestamp, get_contract_address, ClassHash};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess, Map};
    use starknet::syscalls::deploy_syscall;
    use core::traits::Into;
    use core::array::ArrayTrait;
    use core::keccak::keccak_u256s_be_inputs;

    use hello_starknet::interfaces::i_escrow_factory::IEscrowFactory;
    use hello_starknet::interfaces::i_base_escrow::Immutables;
    use hello_starknet::libraries::immutables_lib::ImmutablesLib;
    use hello_starknet::libraries::timelocks_lib::{TimelocksLib, Timelocks, Stage};

    // Constants
    const SRC_IMMUTABLES_LENGTH: u32 = 256; // Equivalent to Solidity constant

    #[storage]
    struct Storage {
        escrow_src_implementation: ContractAddress,
        escrow_dst_implementation: ContractAddress,
        proxy_src_bytecode_hash: felt252,
        proxy_dst_bytecode_hash: felt252,
        escrow_src_class_hash: ClassHash,
        escrow_dst_class_hash: ClassHash,
        // Validation data for partial fills
        last_validated: Map<felt252, ValidationData>,
    }

    #[derive(Drop, Copy, Serde, starknet::Store)]
    struct ValidationData {
        leaf: felt252,
        index: u256,
    }

    #[derive(Drop, Copy, Serde)]
    struct ExtraDataArgs {
        hashlock_info: felt252,
        dst_chain_id: u256,
        dst_token: ContractAddress,
        deposits: u256,
        timelocks: Timelocks,
    }

    #[derive(Drop, Copy, Serde)]
    struct DstImmutablesComplement {
        maker: ContractAddress,
        amount: u256,
        token: ContractAddress,
        safety_deposit: u256,
        chain_id: u256,
    }

    #[derive(Drop, Copy, Serde)]
    struct Order {
        maker: ContractAddress,
        maker_asset: ContractAddress,
        taker_asset: ContractAddress,
        receiver: ContractAddress,
        making_amount: u256,
        taking_amount: u256,
        maker_traits: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        SrcEscrowCreated: SrcEscrowCreated,
        DstEscrowCreated: DstEscrowCreated,
    }

    #[derive(Drop, starknet::Event)]
    struct SrcEscrowCreated {
        src_immutables: Immutables,
        dst_immutables_complement: DstImmutablesComplement,
    }

    #[derive(Drop, starknet::Event)]
    struct DstEscrowCreated {
        escrow: ContractAddress,
        hashlock: felt252,
        taker: ContractAddress,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        escrow_src_implementation: ContractAddress,
        escrow_dst_implementation: ContractAddress,
        escrow_src_class_hash: ClassHash,
        escrow_dst_class_hash: ClassHash,
    ) {
        self.escrow_src_implementation.write(escrow_src_implementation);
        self.escrow_dst_implementation.write(escrow_dst_implementation);
        self.escrow_src_class_hash.write(escrow_src_class_hash);
        self.escrow_dst_class_hash.write(escrow_dst_class_hash);

        // Compute proxy bytecode hashes
        let src_hash = self._compute_proxy_bytecode_hash(escrow_src_implementation);
        let dst_hash = self._compute_proxy_bytecode_hash(escrow_dst_implementation);
        self.proxy_src_bytecode_hash.write(src_hash);
        self.proxy_dst_bytecode_hash.write(dst_hash);
    }

    #[abi(embed_v0)]
    impl EscrowFactoryImpl of IEscrowFactory<ContractState> {
        /// See {IEscrowFactory-get_ESCROW_SRC_IMPLEMENTATION}.
        fn get_ESCROW_SRC_IMPLEMENTATION(self: @ContractState) -> ContractAddress {
            self.escrow_src_implementation.read()
        }

        /// See {IEscrowFactory-get_ESCROW_DST_IMPLEMENTATION}.
        fn get_ESCROW_DST_IMPLEMENTATION(self: @ContractState) -> ContractAddress {
            self.escrow_dst_implementation.read()
        }

        /// See {IEscrowFactory-create_dst_escrow}.
        fn create_dst_escrow(
            ref self: ContractState,
            dst_immutables: Immutables,
            src_cancellation_timestamp: u256
        ) {
            let token = dst_immutables.token;
            let native_amount = dst_immutables.safety_deposit;
            let total_amount = if token == 0.try_into().unwrap() {
                native_amount + dst_immutables.amount
            } else {
                native_amount
            };

            // In Starknet, we'd need to handle value transfer differently
            // For now, we'll validate the caller has sufficient balance

            // Create mutable copy and set deployment timestamp
            let mut immutables = dst_immutables;
            immutables.timelocks = TimelocksLib::set_deployed_at(
                immutables.timelocks, 
                get_block_timestamp().into()
            );

            // Check that escrow cancellation will start not later than source chain cancellation
            let dst_cancellation: u64 = TimelocksLib::get(immutables.timelocks, Stage::DstCancellation).try_into().unwrap();
            let src_cancellation: u64 = src_cancellation_timestamp.try_into().unwrap();
            assert(dst_cancellation <= src_cancellation, 'Invalid creation time');

            let salt = ImmutablesLib::hash(immutables);
            let escrow = self._deploy_escrow(salt, total_amount, self.escrow_dst_class_hash.read());

            // If not native token, transfer tokens to escrow
            if token != 0.try_into().unwrap() {
                // TODO: Implement ERC20 transfer from caller to escrow
                // IERC20::transfer_from(token, get_caller_address(), escrow, immutables.amount);
            }

            self.emit(DstEscrowCreated {
                escrow,
                hashlock: dst_immutables.hashlock,
                taker: dst_immutables.taker,
            });
        }

        /// See {IEscrowFactory-address_of_escrow_src}.
        fn address_of_escrow_src(self: @ContractState, immutables: Immutables) -> ContractAddress {
            let salt = ImmutablesLib::hash(immutables);
            let proxy_hash = self.proxy_src_bytecode_hash.read();
            self._compute_address(salt, proxy_hash)
        }

        /// See {IEscrowFactory-address_of_escrow_dst}.
        fn address_of_escrow_dst(self: @ContractState, immutables: Immutables) -> ContractAddress {
            let salt = ImmutablesLib::hash(immutables);
            let proxy_hash = self.proxy_dst_bytecode_hash.read();
            self._compute_address(salt, proxy_hash)
        }
    }

    #[generate_trait]
    impl BaseEscrowFactoryInternalImpl of BaseEscrowFactoryInternalTrait {
        /// Creates a new escrow contract for maker on the source chain.
        /// Equivalent to Solidity's _postInteraction function
        fn _post_interaction(
            ref self: ContractState,
            order: Order,
            extension: Array<felt252>,
            order_hash: felt252,
            taker: ContractAddress,
            making_amount: u256,
            taking_amount: u256,
            remaining_making_amount: u256,
            extra_data: Array<felt252>
        ) {
            // Simplified implementation - in real contract you'd parse extraData properly
            let extra_data_args = self._parse_extra_data(@extra_data);

            let hashlock = extra_data_args.hashlock_info;

            let immutables = Immutables {
                order_hash,
                hashlock,
                maker: order.maker,
                taker,
                token: order.maker_asset,
                amount: making_amount,
                safety_deposit: extra_data_args.deposits / 0x100000000000000000000000000000000, // >> 128
                timelocks: TimelocksLib::set_deployed_at(extra_data_args.timelocks, get_block_timestamp().into()),
            };

            let receiver = if order.receiver == 0.try_into().unwrap() {
                order.maker
            } else {
                order.receiver
            };

            let immutables_complement = DstImmutablesComplement {
                maker: receiver,
                amount: taking_amount,
                token: extra_data_args.dst_token,
                safety_deposit: extra_data_args.deposits & 0xffffffffffffffffffffffffffffffff, // & type(uint128).max
                chain_id: extra_data_args.dst_chain_id,
            };

            self.emit(SrcEscrowCreated {
                src_immutables: immutables,
                dst_immutables_complement: immutables_complement,
            });

            let salt = ImmutablesLib::hash_mem(immutables);
            let _escrow = self._deploy_escrow(salt, 0, self.escrow_src_class_hash.read());

            // Validate escrow has sufficient balance
            // TODO: Implement balance checks
            // assert(escrow.balance >= immutables.safety_deposit, 'Insufficient escrow balance');
            // assert(IERC20::balance_of(order.maker_asset, escrow) >= making_amount, 'Insufficient token balance');
        }

        /// Handles partial fill validation for orders that allow multiple fills

        /// Deploys a new escrow contract using Starknet's deploy syscall
        fn _deploy_escrow(
            self: @ContractState,
            salt: felt252,
            _value: u256, // In Starknet, value is handled differently
            class_hash: ClassHash
        ) -> ContractAddress {
            let mut constructor_calldata = ArrayTrait::new();
            // Add constructor parameters if needed
            
            let (escrow_address, _) = deploy_syscall(
                class_hash,
                salt,
                constructor_calldata.span(),
                false
            ).unwrap();

            escrow_address
        }

        

        /// Parses extra data into structured format
        fn _parse_extra_data(self: @ContractState, extra_data: @Array<felt252>) -> ExtraDataArgs {
            // Simplified parsing - in real implementation you'd properly decode the array
            ExtraDataArgs {
                hashlock_info: *extra_data.at(0),
                dst_chain_id: (*extra_data.at(1)).into(),
                dst_token: (*extra_data.at(2)).try_into().unwrap(),
                deposits: (*extra_data.at(3)).into(),
                timelocks: Timelocks { value: *extra_data.at(4) },
            }
        }

        /// Computes key for validation data storage
        fn _compute_key(self: @ContractState, order_hash: felt252, hashlock_info: felt252) -> felt252 {
            let mut data = ArrayTrait::new();
            data.append(order_hash.into());
            data.append(hashlock_info.into());
            let hash = keccak_u256s_be_inputs(data.span());
            hash.low.into()
        }

        /// Computes proxy bytecode hash
        fn _compute_proxy_bytecode_hash(self: @ContractState, implementation: ContractAddress) -> felt252 {
            let mut data = ArrayTrait::new();
            let impl_felt: felt252 = implementation.into();
            data.append(impl_felt.into());
            let hash = keccak_u256s_be_inputs(data.span());
            hash.low.into()
        }

        /// Computes deterministic address similar to CREATE2
        fn _compute_address(self: @ContractState, salt: felt252, proxy_hash: felt252) -> ContractAddress {
            let mut data = ArrayTrait::new();
            data.append(salt.into());
            data.append(proxy_hash.into());
            let contract_addr: felt252 = get_contract_address().into();
            data.append(contract_addr.into());
            
            let hash = keccak_u256s_be_inputs(data.span());
            let address_felt: felt252 = hash.low.into();
            address_felt.try_into().unwrap()
        }
    }
}
