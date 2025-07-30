// Interface module declarations
pub mod i_base_escrow;
pub mod i_escrow;
pub mod i_escrow_factory;
pub mod i_escrow_src;
pub mod i_esrcrow_dst;

// Re-export commonly used interfaces
pub use i_base_escrow::{IBaseEscrow, Immutables};
pub use i_escrow::IEscrow;
pub use i_escrow_factory::IEscrowFactory;
pub use i_escrow_src::IEscrowSrc;
pub use i_esrcrow_dst::IEscrowDst;
