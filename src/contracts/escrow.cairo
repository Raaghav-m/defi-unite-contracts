// src/contracts/escrow.cairo

#[starknet::contract]
pub mod Escrow {
    use starknet::{ContractAddress, get_contract_address, ClassHash};
    use starknet::storage::{StoragePointerReadAccess, StoragePointerWriteAccess};
    use core::traits::Into;
    use core::array::ArrayTrait;
    use core::poseidon::poseidon_hash_span;

    use hello_starknet::interfaces::i_escrow::IEscrow;
    use hello_starknet::interfaces::i_base_escrow::Immutables;
    use hello_starknet::libraries::immutables_lib::ImmutablesLib;
    use hello_starknet::libraries::proxy_hash_lib::ProxyHashLib;

    #[storage]
    struct Storage {
        rescue_delay: felt252,
        factory: ContractAddress,
        proxy_bytecode_hash: felt252,
        class_hash: ClassHash,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        FundsRescued: FundsRescued,
    }

    #[derive(Drop, starknet::Event)]
    struct FundsRescued {
        token: ContractAddress,
        amount: u256,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState, 
        rescue_delay: felt252, 
        factory: ContractAddress,
        class_hash: ClassHash
    ) {
        self.rescue_delay.write(rescue_delay);
        self.factory.write(factory);
        self.class_hash.write(class_hash);
        
        // Compute proxy bytecode hash equivalent to Solidity's computeProxyBytecodeHash(address(this))
        let contract_address: felt252 = get_contract_address().into();
        let proxy_hash = ProxyHashLib::compute_proxy_bytecode_hash(contract_address);
        self.proxy_bytecode_hash.write(proxy_hash);
    }


    #[generate_trait]
    impl EscrowInternalImpl of EscrowInternalTrait {
        /// Validates that the computed escrow address matches the address of this contract
        /// Equivalent to Solidity's _validateImmutables function
        fn _validate_immutables(self: @ContractState, immutables: Immutables) {
            let salt = ImmutablesLib::hash(immutables);
            let proxy_hash = self.proxy_bytecode_hash.read();
            let factory = self.factory.read();
            
            // In Cairo/Starknet, we would use the class hash and constructor calldata
            // to compute the expected contract address, similar to CREATE2
            let expected_address = self._compute_address(salt, proxy_hash, factory);
            let current_address = get_contract_address();
            
            assert(expected_address == current_address, 'Invalid immutables');
        }

        /// Computes the contract address using Starknet's native address computation
        /// Similar to Solidity's Create2.computeAddress but adapted for Starknet
        fn _compute_address(
            self: @ContractState,
            salt: felt252,
            proxy_hash: felt252,
            factory: ContractAddress
        ) -> ContractAddress {
            // Use the stored class hash for address computation
            let class_hash = self.class_hash.read();
            
            // Create constructor calldata that matches what was used during deployment
            let mut constructor_calldata = ArrayTrait::new();
            constructor_calldata.append(self.rescue_delay.read());
            constructor_calldata.append(factory.into());
            constructor_calldata.append(class_hash.into());
            
            // Compute address using Starknet's standard formula:
            // address = poseidon_hash([
            //   "STARKNET_CONTRACT_ADDRESS",
            //   deployer_address,
            //   salt,
            //   class_hash,
            //   poseidon_hash(constructor_calldata)
            // ]) mod FIELD_PRIME
            
            let constructor_calldata_hash = poseidon_hash_span(constructor_calldata.span());
            
            let mut address_data = ArrayTrait::new();
            address_data.append('STARKNET_CONTRACT_ADDRESS'); // Standard prefix
            address_data.append(factory.into()); // deployer address
            address_data.append(salt);
            address_data.append(class_hash.into());
            address_data.append(constructor_calldata_hash);
            
            let computed_address = poseidon_hash_span(address_data.span());
            computed_address.try_into().unwrap()
        }
    }
}
