//! Shared persistence limits for canonical registration evidence.
//!
//! Every layer that constructs, validates, or stores an evidence reference
//! uses this boundary so a protected copy cannot be created and then rejected
//! by the ledger or SQLite schema for its length.

pub const max_evidence_storage_reference_bytes: usize = 2048;
