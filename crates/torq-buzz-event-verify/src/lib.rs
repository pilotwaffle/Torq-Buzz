//! TORQ Buzz migration support for the Gate-1 `COPY_SELECTED_MESSAGE` step.
//!
//! Scope (bounded Luna implementation):
//! - write-ahead journal record + state machine
//! - semantic duplicate filter (`Event::verify` + kind/author/h/content)
//! - publish-retry reuse of the same signed event
//! - `verify-selected-message` contract and exit codes
//!
//! Does **not** hold private keys, mutate pilot data, or contact a live relay
//! unless a caller supplies relay events / a publish callback.

pub mod journal;
pub mod semantic;
pub mod step;
pub mod verify_selected;

pub use journal::{
    CopySelectedJournal, CopySelectedState, JournalTimestamps, APPROVED_CONTENT, INTENDED_KIND,
    INTENDED_RELAY_URL,
};
pub use semantic::{
    filter_semantic_copies, is_semantic_copy, parse_event_array, SemanticCopyExpectation,
    SemanticCopyMatch,
};
pub use step::{
    advance_after_duplicate_check, complete_after_verify, load_signed_event, persist_signed_event,
    recover_interrupted_verification, retry_publish, source_plan_matches, AdvanceError,
    AdvanceOutcome, PublishError, RecoveryOutcome, SourcePlan,
};
pub use verify_selected::{
    verify_selected_message, VerifySelectedInput, VerifySelectedOutput, VerifySelectedResult,
    EXIT_AMBIGUOUS, EXIT_IO, EXIT_NONE, EXIT_OK, EXIT_SEMANTIC, EXIT_SOURCE_DRIFT,
};
