//! `COPY_SELECTED_MESSAGE` state transitions and retry / recovery rules.
//!
//! Transition path:
//! `PLANNED -> DUPLICATE_CHECKED -> SIGNED -> PUBLISHED -> VERIFIED -> COMPLETE`
//!
//! Terminal branches:
//! - `COMPLETE_REUSED` (exactly one existing valid semantic copy)
//! - `AMBIGUOUS_DUPLICATE` (more than one valid semantic copy)

use std::fs;
use std::path::{Path, PathBuf};

use chrono::{DateTime, Utc};
use nostr::{Event, JsonUtil};
use thiserror::Error;

use crate::journal::{
    bytes_sha256_hex, content_sha256_hex, CopySelectedJournal, CopySelectedState, APPROVED_CONTENT,
    INTENDED_KIND, INTENDED_RELAY_URL,
};
use crate::semantic::{filter_semantic_copies, SemanticCopyExpectation};

/// Approved source-plan fields that must remain unchanged through the step.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SourcePlan {
    pub source_event_id: String,
    pub source_event_author: String,
    pub source_channel_id: String,
    pub content: String,
    pub content_sha256: String,
}

impl SourcePlan {
    pub fn gate1_acceptance(
        source_event_id: impl Into<String>,
        source_event_author: impl Into<String>,
        source_channel_id: impl Into<String>,
    ) -> Self {
        Self {
            source_event_id: source_event_id.into(),
            source_event_author: source_event_author.into(),
            source_channel_id: source_channel_id.into(),
            content: APPROVED_CONTENT.to_string(),
            content_sha256: content_sha256_hex(APPROVED_CONTENT),
        }
    }
}

/// True when journal source fields still match the approved plan.
pub fn source_plan_matches(journal: &CopySelectedJournal, plan: &SourcePlan) -> bool {
    journal.source_event_id == plan.source_event_id
        && journal.source_event_author == plan.source_event_author
        && journal.source_channel_id == plan.source_channel_id
        && journal.content_sha256 == plan.content_sha256
        && journal.intended_kind == INTENDED_KIND
        && journal.intended_relay_url == INTENDED_RELAY_URL
        && journal.content_sha256 == content_sha256_hex(&plan.content)
}

#[derive(Debug, Error)]
pub enum AdvanceError {
    #[error("source-plan drift: journal no longer matches approved plan")]
    SourcePlanDrift,
    #[error("invalid state for operation: {0}")]
    InvalidState(String),
    #[error("signed event I/O: {0}")]
    Io(String),
    #[error("signed event parse: {0}")]
    Parse(String),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AdvanceOutcome {
    /// Zero valid copies — caller must sign exactly once, then call [`persist_signed_event`].
    NeedsSign { journal: CopySelectedJournal },
    /// Exactly one valid copy — terminal reuse.
    CompleteReused {
        journal: CopySelectedJournal,
        destination_event_id: String,
    },
    /// More than one valid copy — terminal failure.
    AmbiguousDuplicate {
        journal: CopySelectedJournal,
        event_ids: Vec<String>,
    },
}

/// After `PLANNED`, run the pre-sign duplicate query against candidate events.
///
/// `candidates` should already be scoped by the relay query
/// `{kinds:[9], authors:[human], "#h":[channel]}`; this function still applies
/// full semantic validation locally.
pub fn advance_after_duplicate_check(
    mut journal: CopySelectedJournal,
    candidates: &[Event],
    plan: &SourcePlan,
    now: DateTime<Utc>,
) -> Result<AdvanceOutcome, AdvanceError> {
    if !source_plan_matches(&journal, plan) {
        return Err(AdvanceError::SourcePlanDrift);
    }
    if journal.current_state != CopySelectedState::Planned
        && journal.current_state != CopySelectedState::DuplicateChecked
        && journal.current_state != CopySelectedState::Signed
        && journal.current_state != CopySelectedState::Published
    {
        // Allow re-entry from recovery paths; reject terminal states.
        if journal.current_state.is_terminal() {
            return Err(AdvanceError::InvalidState(format!(
                "already terminal: {}",
                journal.current_state.as_str()
            )));
        }
    }

    let expected = SemanticCopyExpectation::new(
        &journal.destination_public_key,
        &journal.destination_channel_id,
        &plan.content,
    );
    let matches = filter_semantic_copies(candidates, &expected);
    let ids: Vec<String> = matches.iter().map(|m| m.event_id.clone()).collect();

    match ids.len() {
        0 => {
            journal.current_state = CopySelectedState::DuplicateChecked;
            journal.timestamps.duplicate_checked_utc = Some(now);
            journal.verification_result = Some("duplicate_check:0".to_string());
            Ok(AdvanceOutcome::NeedsSign { journal })
        }
        1 => {
            let destination_event_id = ids[0].clone();
            journal.destination_event_id = Some(destination_event_id.clone());
            journal.current_state = CopySelectedState::CompleteReused;
            journal.timestamps.duplicate_checked_utc = Some(now);
            journal.timestamps.completed_utc = Some(now);
            journal.verification_result = Some("duplicate_check:1_reused".to_string());
            Ok(AdvanceOutcome::CompleteReused {
                journal,
                destination_event_id,
            })
        }
        _ => {
            journal.current_state = CopySelectedState::AmbiguousDuplicate;
            journal.timestamps.duplicate_checked_utc = Some(now);
            journal.timestamps.completed_utc = Some(now);
            journal.verification_result =
                Some(format!("duplicate_check:ambiguous:{}", ids.len()));
            Ok(AdvanceOutcome::AmbiguousDuplicate {
                journal,
                event_ids: ids,
            })
        }
    }
}

/// Persist a newly signed event (public payload only) and advance to `SIGNED`.
///
/// Never call this a second time for the same run when `signed_event_path` is set —
/// publish retries must reuse the file.
pub fn persist_signed_event(
    mut journal: CopySelectedJournal,
    signed_event: &Event,
    signed_event_path: impl AsRef<Path>,
    now: DateTime<Utc>,
) -> Result<CopySelectedJournal, AdvanceError> {
    if journal.current_state != CopySelectedState::DuplicateChecked
        && journal.current_state != CopySelectedState::Planned
    {
        // Allow first-time sign only from DUPLICATE_CHECKED (or PLANNED if caller skipped).
        if journal.signed_event_path.is_some() {
            return Err(AdvanceError::InvalidState(
                "signed event already persisted; reuse for publish retry".into(),
            ));
        }
    }
    if journal.signed_event_path.is_some() {
        return Err(AdvanceError::InvalidState(
            "signed event already persisted; never re-sign".into(),
        ));
    }

    // Author and kind guards — permanent-human only, kind 9.
    if signed_event.kind.as_u16() != INTENDED_KIND {
        return Err(AdvanceError::InvalidState(format!(
            "signed event kind {} != {}",
            signed_event.kind.as_u16(),
            INTENDED_KIND
        )));
    }
    if signed_event.pubkey.to_hex() != journal.destination_public_key {
        return Err(AdvanceError::InvalidState(
            "signed event author is not destination permanent-human pubkey".into(),
        ));
    }
    if signed_event.verify().is_err() {
        return Err(AdvanceError::InvalidState(
            "signed event failed Event::verify".into(),
        ));
    }

    let path = signed_event_path.as_ref();
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|e| AdvanceError::Io(e.to_string()))?;
    }
    let json = signed_event.as_json();
    let bytes = json.as_bytes();
    atomic_write(path, bytes).map_err(AdvanceError::Io)?;

    journal.destination_event_id = Some(signed_event.id.to_hex());
    journal.signed_event_path = Some(path_to_string(path));
    journal.signed_event_sha256 = Some(bytes_sha256_hex(bytes));
    journal.current_state = CopySelectedState::Signed;
    journal.timestamps.signed_utc = Some(now);
    Ok(journal)
}

/// Load the persisted signed event for publish retry. Never re-signs.
pub fn load_signed_event(journal: &CopySelectedJournal) -> Result<Event, AdvanceError> {
    let path = journal
        .signed_event_path
        .as_ref()
        .ok_or_else(|| AdvanceError::InvalidState("no signed_event_path".into()))?;
    let bytes = fs::read(path).map_err(|e| AdvanceError::Io(e.to_string()))?;
    if let Some(expected) = &journal.signed_event_sha256 {
        let actual = bytes_sha256_hex(&bytes);
        if &actual != expected {
            return Err(AdvanceError::Io(
                "signed event file hash mismatch — refuse re-sign; restore file".into(),
            ));
        }
    }
    let text = String::from_utf8(bytes).map_err(|e| AdvanceError::Parse(e.to_string()))?;
    let event = Event::from_json(&text).map_err(|e| AdvanceError::Parse(e.to_string()))?;
    if let Some(id) = &journal.destination_event_id {
        if event.id.to_hex() != *id {
            return Err(AdvanceError::Parse(
                "signed event id does not match journal.destination_event_id".into(),
            ));
        }
    }
    Ok(event)
}

#[derive(Debug, Error)]
pub enum PublishError {
    #[error("publish failed: {0}")]
    Failed(String),
    #[error(transparent)]
    Advance(#[from] AdvanceError),
}

/// Callback used by the orchestrator to publish a signed event to the relay.
///
/// Tests inject a mock. Production wires HTTP/WS event submission.
/// `FnMut` allows retry counters in tests without interior mutability.
pub fn retry_publish<F>(
    mut journal: CopySelectedJournal,
    publish: &mut F,
    now: DateTime<Utc>,
) -> Result<CopySelectedJournal, PublishError>
where
    F: FnMut(&Event) -> Result<(), String>,
{
    if journal.current_state != CopySelectedState::Signed
        && journal.current_state != CopySelectedState::Published
    {
        // Allow re-publish only from SIGNED (or after a prior soft publish mark).
        if journal.current_state != CopySelectedState::Signed {
            return Err(PublishError::Advance(AdvanceError::InvalidState(format!(
                "cannot publish from state {}",
                journal.current_state.as_str()
            ))));
        }
    }
    let event = load_signed_event(&journal)?;
    publish(&event).map_err(PublishError::Failed)?;
    journal.current_state = CopySelectedState::Published;
    journal.timestamps.published_utc = Some(now);
    Ok(journal)
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RecoveryOutcome {
    Complete {
        journal: CopySelectedJournal,
        destination_event_id: String,
    },
    CompleteReused {
        journal: CopySelectedJournal,
        destination_event_id: String,
    },
    NeedsPublish {
        journal: CopySelectedJournal,
    },
    AmbiguousDuplicate {
        journal: CopySelectedJournal,
        event_ids: Vec<String>,
    },
    StillMissing {
        journal: CopySelectedJournal,
    },
}

/// After publish success with interrupted verification, re-query candidates and
/// resume without re-signing.
pub fn recover_interrupted_verification(
    mut journal: CopySelectedJournal,
    candidates: &[Event],
    plan: &SourcePlan,
    now: DateTime<Utc>,
) -> Result<RecoveryOutcome, AdvanceError> {
    if !source_plan_matches(&journal, plan) {
        return Err(AdvanceError::SourcePlanDrift);
    }
    let expected = SemanticCopyExpectation::new(
        &journal.destination_public_key,
        &journal.destination_channel_id,
        &plan.content,
    );
    let matches = filter_semantic_copies(candidates, &expected);
    let ids: Vec<String> = matches.iter().map(|m| m.event_id.clone()).collect();

    match ids.len() {
        0 => {
            // Not on relay yet — if we have a signed event, re-publish same ID.
            if journal.signed_event_path.is_some() {
                journal.current_state = CopySelectedState::Signed;
                Ok(RecoveryOutcome::NeedsPublish { journal })
            } else {
                Ok(RecoveryOutcome::StillMissing { journal })
            }
        }
        1 => {
            let destination_event_id = ids[0].clone();
            // If we signed this ID, complete the normal path; else reuse.
            let reused = journal.destination_event_id.as_ref() != Some(&destination_event_id)
                || journal.signed_event_path.is_none();
            journal.destination_event_id = Some(destination_event_id.clone());
            journal.timestamps.verified_utc = Some(now);
            journal.timestamps.completed_utc = Some(now);
            if reused && journal.signed_event_path.is_none() {
                journal.current_state = CopySelectedState::CompleteReused;
                journal.verification_result = Some("recovery:reused".to_string());
                Ok(RecoveryOutcome::CompleteReused {
                    journal,
                    destination_event_id,
                })
            } else {
                journal.current_state = CopySelectedState::Complete;
                journal.verification_result = Some("recovery:verified_complete".to_string());
                Ok(RecoveryOutcome::Complete {
                    journal,
                    destination_event_id,
                })
            }
        }
        _ => {
            journal.current_state = CopySelectedState::AmbiguousDuplicate;
            journal.timestamps.completed_utc = Some(now);
            journal.verification_result =
                Some(format!("recovery:ambiguous:{}", ids.len()));
            Ok(RecoveryOutcome::AmbiguousDuplicate {
                journal,
                event_ids: ids,
            })
        }
    }
}

/// Mark VERIFIED then COMPLETE after successful post-publish verification.
pub fn complete_after_verify(
    mut journal: CopySelectedJournal,
    destination_event_id: &str,
    now: DateTime<Utc>,
) -> Result<CopySelectedJournal, AdvanceError> {
    if journal.current_state != CopySelectedState::Published
        && journal.current_state != CopySelectedState::Verified
    {
        return Err(AdvanceError::InvalidState(format!(
            "cannot complete from {}",
            journal.current_state.as_str()
        )));
    }
    if let Some(existing) = &journal.destination_event_id {
        if existing != destination_event_id {
            return Err(AdvanceError::InvalidState(
                "destination_event_id mismatch on complete".into(),
            ));
        }
    }
    journal.destination_event_id = Some(destination_event_id.to_string());
    journal.current_state = CopySelectedState::Verified;
    journal.timestamps.verified_utc = Some(now);
    journal.current_state = CopySelectedState::Complete;
    journal.timestamps.completed_utc = Some(now);
    journal.verification_result = Some("verify:ok".to_string());
    Ok(journal)
}

fn atomic_write(path: &Path, bytes: &[u8]) -> Result<(), String> {
    let parent = path
        .parent()
        .map(Path::to_path_buf)
        .unwrap_or_else(|| PathBuf::from("."));
    let tmp = parent.join(format!(
        ".{}.tmp",
        path.file_name()
            .and_then(|s| s.to_str())
            .unwrap_or("signed-event.json")
    ));
    fs::write(&tmp, bytes).map_err(|e| e.to_string())?;
    fs::rename(&tmp, path).map_err(|e| e.to_string())?;
    Ok(())
}

fn path_to_string(path: &Path) -> String {
    path.to_string_lossy().replace('\\', "/")
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::semantic::kind_9;
    use nostr::{EventBuilder, Keys, Tag};
    use tempfile::tempdir;

    const CHANNEL: &str = "22222222-2222-2222-2222-222222222222";
    const SOURCE_CHANNEL: &str = "11111111-1111-1111-1111-111111111111";
    const SOURCE_EVENT: &str =
        "5ff77c3fb4c15b8362c23398a998e45a9fe77d13622adcd9a88cd2f3115dd670";
    const SOURCE_AUTHOR: &str =
        "bf89795d33481f5b83e918bc2837ebb2f7b01bbcaf8fecc740fc83c94ef5a9b7";

    fn plan() -> SourcePlan {
        SourcePlan::gate1_acceptance(SOURCE_EVENT, SOURCE_AUTHOR, SOURCE_CHANNEL)
    }

    fn planned_journal(human: &str) -> CopySelectedJournal {
        CopySelectedJournal::planned(
            "run-test",
            SOURCE_EVENT,
            SOURCE_AUTHOR,
            SOURCE_CHANNEL,
            CHANNEL,
            human,
            APPROVED_CONTENT,
            Utc::now(),
        )
    }

    fn sign(keys: &Keys, channel: &str, content: &str) -> Event {
        EventBuilder::new(kind_9(), content)
            .tags([Tag::parse(["h", channel]).expect("h")])
            .sign_with_keys(keys)
            .expect("sign")
    }

    #[test]
    fn zero_match_needs_sign() {
        let keys = Keys::generate();
        let journal = planned_journal(&keys.public_key().to_hex());
        let out = advance_after_duplicate_check(journal, &[], &plan(), Utc::now()).unwrap();
        match out {
            AdvanceOutcome::NeedsSign { journal } => {
                assert_eq!(journal.current_state, CopySelectedState::DuplicateChecked);
            }
            other => panic!("unexpected {other:?}"),
        }
    }

    #[test]
    fn one_match_reuses() {
        let keys = Keys::generate();
        let event = sign(&keys, CHANNEL, APPROVED_CONTENT);
        let journal = planned_journal(&keys.public_key().to_hex());
        let out =
            advance_after_duplicate_check(journal, &[event.clone()], &plan(), Utc::now()).unwrap();
        match out {
            AdvanceOutcome::CompleteReused {
                journal,
                destination_event_id,
            } => {
                assert_eq!(journal.current_state, CopySelectedState::CompleteReused);
                assert_eq!(destination_event_id, event.id.to_hex());
                assert_eq!(journal.destination_event_id.as_deref(), Some(destination_event_id.as_str()));
            }
            other => panic!("unexpected {other:?}"),
        }
    }

    #[test]
    fn multi_match_ambiguous() {
        let keys = Keys::generate();
        let e1 = sign(&keys, CHANNEL, APPROVED_CONTENT);
        // Distinct id via different created_at by generating twice (timestamp resolution).
        std::thread::sleep(std::time::Duration::from_millis(1100));
        let e2 = sign(&keys, CHANNEL, APPROVED_CONTENT);
        assert_ne!(e1.id, e2.id);
        let journal = planned_journal(&keys.public_key().to_hex());
        let out =
            advance_after_duplicate_check(journal, &[e1, e2], &plan(), Utc::now()).unwrap();
        match out {
            AdvanceOutcome::AmbiguousDuplicate { journal, event_ids } => {
                assert_eq!(journal.current_state, CopySelectedState::AmbiguousDuplicate);
                assert_eq!(event_ids.len(), 2);
            }
            other => panic!("unexpected {other:?}"),
        }
    }

    #[test]
    fn publish_retry_reuses_same_event_id() {
        let keys = Keys::generate();
        let event = sign(&keys, CHANNEL, APPROVED_CONTENT);
        let dir = tempdir().unwrap();
        let path = dir.path().join("signed-event.json");
        let journal = planned_journal(&keys.public_key().to_hex());
        let journal = match advance_after_duplicate_check(journal, &[], &plan(), Utc::now()).unwrap()
        {
            AdvanceOutcome::NeedsSign { journal } => journal,
            other => panic!("{other:?}"),
        };
        let journal = persist_signed_event(journal, &event, &path, Utc::now()).unwrap();
        assert_eq!(journal.current_state, CopySelectedState::Signed);
        let signed_id = journal.destination_event_id.clone().unwrap();

        let mut attempts = 0;
        let mut fail_once = |e: &Event| {
            attempts += 1;
            assert_eq!(e.id.to_hex(), signed_id);
            if attempts == 1 {
                Err("relay unavailable".into())
            } else {
                Ok(())
            }
        };
        let err = retry_publish(journal.clone(), &mut fail_once, Utc::now()).unwrap_err();
        assert!(matches!(err, PublishError::Failed(_)));
        // state remains SIGNED on failure
        assert_eq!(journal.current_state, CopySelectedState::Signed);

        let mut ok_publish = |e: &Event| {
            assert_eq!(e.id.to_hex(), signed_id);
            Ok(())
        };
        let journal = retry_publish(journal, &mut ok_publish, Utc::now()).unwrap();
        assert_eq!(journal.current_state, CopySelectedState::Published);
        assert_eq!(journal.destination_event_id.as_deref(), Some(signed_id.as_str()));

        // Second persist must fail (never re-sign).
        let err = persist_signed_event(journal, &event, &path, Utc::now()).unwrap_err();
        assert!(matches!(err, AdvanceError::InvalidState(_)));
    }

    #[test]
    fn interrupted_verification_recovery_reuses_on_relay() {
        let keys = Keys::generate();
        let event = sign(&keys, CHANNEL, APPROVED_CONTENT);
        let dir = tempdir().unwrap();
        let path = dir.path().join("signed-event.json");
        let journal = planned_journal(&keys.public_key().to_hex());
        let journal = match advance_after_duplicate_check(journal, &[], &plan(), Utc::now()).unwrap()
        {
            AdvanceOutcome::NeedsSign { journal } => journal,
            other => panic!("{other:?}"),
        };
        let journal = persist_signed_event(journal, &event, &path, Utc::now()).unwrap();
        let mut publish = |_e: &Event| Ok(());
        let journal = retry_publish(journal, &mut publish, Utc::now()).unwrap();
        assert_eq!(journal.current_state, CopySelectedState::Published);

        // Verification interrupted — recover by re-query.
        let out =
            recover_interrupted_verification(journal, &[event.clone()], &plan(), Utc::now())
                .unwrap();
        match out {
            RecoveryOutcome::Complete {
                journal,
                destination_event_id,
            } => {
                assert_eq!(journal.current_state, CopySelectedState::Complete);
                assert_eq!(destination_event_id, event.id.to_hex());
            }
            other => panic!("unexpected {other:?}"),
        }
    }

    #[test]
    fn source_plan_drift_blocks_advance() {
        let keys = Keys::generate();
        let mut journal = planned_journal(&keys.public_key().to_hex());
        journal.source_event_id = "0".repeat(64);
        let err = advance_after_duplicate_check(journal, &[], &plan(), Utc::now()).unwrap_err();
        assert!(matches!(err, AdvanceError::SourcePlanDrift));
    }
}
