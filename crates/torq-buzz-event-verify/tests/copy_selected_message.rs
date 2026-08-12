//! Integration tests for COPY_SELECTED_MESSAGE:
//! no-match, reuse, ambiguous, publish-retry, interrupted verification recovery.

use chrono::Utc;
use nostr::{Event, EventBuilder, JsonUtil, Keys, Tag};
use tempfile::tempdir;
use torq_buzz_event_verify::journal::{
    content_sha256_hex, CopySelectedJournal, CopySelectedState, APPROVED_CONTENT, INTENDED_KIND,
    INTENDED_RELAY_URL,
};
use torq_buzz_event_verify::semantic::kind_9;
use torq_buzz_event_verify::step::{
    advance_after_duplicate_check, complete_after_verify, persist_signed_event,
    recover_interrupted_verification, retry_publish, AdvanceOutcome, RecoveryOutcome, SourcePlan,
};
use torq_buzz_event_verify::verify_selected::{
    verify_selected_message, SourcePlanDto, VerifySelectedInput, EXIT_AMBIGUOUS, EXIT_IO,
    EXIT_NONE, EXIT_OK, EXIT_SEMANTIC, EXIT_SOURCE_DRIFT,
};

const SOURCE_EVENT: &str = "5ff77c3fb4c15b8362c23398a998e45a9fe77d13622adcd9a88cd2f3115dd670";
const SOURCE_AUTHOR: &str = "bf89795d33481f5b83e918bc2837ebb2f7b01bbcaf8fecc740fc83c94ef5a9b7";
const SOURCE_CHANNEL: &str = "1999fab3-9d01-46be-a1e2-5d2459a2ee01";
const DEST_CHANNEL: &str = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";

fn plan() -> SourcePlan {
    SourcePlan::gate1_acceptance(SOURCE_EVENT, SOURCE_AUTHOR, SOURCE_CHANNEL)
}

fn plan_dto() -> SourcePlanDto {
    SourcePlanDto {
        source_event_id: SOURCE_EVENT.into(),
        source_event_author: SOURCE_AUTHOR.into(),
        source_channel_id: SOURCE_CHANNEL.into(),
        content: APPROVED_CONTENT.into(),
    }
}

fn journal_for(human_hex: &str) -> CopySelectedJournal {
    CopySelectedJournal::planned(
        "mig-run-itest",
        SOURCE_EVENT,
        SOURCE_AUTHOR,
        SOURCE_CHANNEL,
        DEST_CHANNEL,
        human_hex,
        APPROVED_CONTENT,
        Utc::now(),
    )
}

fn sign(keys: &Keys, channel: &str, content: &str) -> Event {
    EventBuilder::new(kind_9(), content)
        .tags([Tag::parse(["h", channel]).expect("h tag")])
        .sign_with_keys(keys)
        .expect("sign")
}

#[test]
fn t_copy_0match_sign_publish_verify_complete() {
    let keys = Keys::generate();
    let human = keys.public_key().to_hex();
    let journal = journal_for(&human);
    let plan = plan();

    let out = advance_after_duplicate_check(journal, &[], &plan, Utc::now()).unwrap();
    let journal = match out {
        AdvanceOutcome::NeedsSign { journal } => {
            assert_eq!(journal.current_state, CopySelectedState::DuplicateChecked);
            journal
        }
        other => panic!("expected NeedsSign, got {other:?}"),
    };

    let signed = sign(&keys, DEST_CHANNEL, APPROVED_CONTENT);
    let dir = tempdir().unwrap();
    let path = dir.path().join("signed-event.json");
    let journal = persist_signed_event(journal, &signed, &path, Utc::now()).unwrap();
    assert_eq!(journal.current_state, CopySelectedState::Signed);
    assert_eq!(
        journal.destination_event_id.as_deref(),
        Some(signed.id.to_hex().as_str())
    );

    let signed_id = signed.id;
    let mut publish = |e: &Event| {
        assert_eq!(e.id, signed_id);
        Ok(())
    };
    let journal = retry_publish(journal, &mut publish, Utc::now()).unwrap();
    assert_eq!(journal.current_state, CopySelectedState::Published);

    let input = VerifySelectedInput {
        schema_version: 1,
        permanent_human_pubkey: human.clone(),
        destination_channel_id: DEST_CHANNEL.into(),
        expected_content: APPROVED_CONTENT.into(),
        intended_kind: INTENDED_KIND,
        intended_relay_url: INTENDED_RELAY_URL.into(),
        events_json: format!("[{}]", signed.as_json()),
        journal: journal.clone(),
        source_plan: plan_dto(),
        expected_destination_event_id: journal.destination_event_id.clone(),
    };
    let result = verify_selected_message(&input);
    assert_eq!(result.exit_code, EXIT_OK, "{:?}", result.output.errors);
    assert!(result.output.ok);
    assert_eq!(result.output.valid_copy_count, 1);

    let journal = complete_after_verify(
        journal,
        result.output.destination_event_id.as_deref().unwrap(),
        Utc::now(),
    )
    .unwrap();
    assert_eq!(journal.current_state, CopySelectedState::Complete);
}

#[test]
fn t_copy_1match_reuse() {
    let keys = Keys::generate();
    let human = keys.public_key().to_hex();
    let existing = sign(&keys, DEST_CHANNEL, APPROVED_CONTENT);
    let journal = journal_for(&human);
    let out =
        advance_after_duplicate_check(journal, &[existing.clone()], &plan(), Utc::now()).unwrap();
    match out {
        AdvanceOutcome::CompleteReused {
            journal,
            destination_event_id,
        } => {
            assert_eq!(journal.current_state, CopySelectedState::CompleteReused);
            assert_eq!(destination_event_id, existing.id.to_hex());
            assert!(journal.signed_event_path.is_none());
        }
        other => panic!("expected CompleteReused, got {other:?}"),
    }
}

#[test]
fn t_copy_ambiguous() {
    let keys = Keys::generate();
    let human = keys.public_key().to_hex();
    let e1 = sign(&keys, DEST_CHANNEL, APPROVED_CONTENT);
    std::thread::sleep(std::time::Duration::from_millis(1100));
    let e2 = sign(&keys, DEST_CHANNEL, APPROVED_CONTENT);
    assert_ne!(e1.id, e2.id);
    let journal = journal_for(&human);
    let out = advance_after_duplicate_check(journal, &[e1, e2], &plan(), Utc::now()).unwrap();
    match out {
        AdvanceOutcome::AmbiguousDuplicate { journal, event_ids } => {
            assert_eq!(journal.current_state, CopySelectedState::AmbiguousDuplicate);
            assert_eq!(event_ids.len(), 2);
        }
        other => panic!("expected AmbiguousDuplicate, got {other:?}"),
    }
}

#[test]
fn t_copy_publish_retry_same_signed_event() {
    let keys = Keys::generate();
    let human = keys.public_key().to_hex();
    let signed = sign(&keys, DEST_CHANNEL, APPROVED_CONTENT);
    let dir = tempdir().unwrap();
    let path = dir.path().join("signed-event.json");

    let journal = journal_for(&human);
    let journal = match advance_after_duplicate_check(journal, &[], &plan(), Utc::now()).unwrap() {
        AdvanceOutcome::NeedsSign { journal } => journal,
        other => panic!("{other:?}"),
    };
    let journal = persist_signed_event(journal, &signed, &path, Utc::now()).unwrap();
    let id = journal.destination_event_id.clone().unwrap();

    let mut n = 0;
    let mut fail_then_ok = |e: &Event| {
        n += 1;
        assert_eq!(e.id.to_hex(), id);
        if n < 3 {
            Err(format!("transient fail #{n}"))
        } else {
            Ok(())
        }
    };

    let j1 = journal.clone();
    assert!(retry_publish(j1, &mut fail_then_ok, Utc::now()).is_err());
    let j2 = journal.clone();
    assert!(retry_publish(j2, &mut fail_then_ok, Utc::now()).is_err());
    let journal = retry_publish(journal, &mut fail_then_ok, Utc::now()).unwrap();
    assert_eq!(journal.current_state, CopySelectedState::Published);
    assert_eq!(journal.destination_event_id.as_deref(), Some(id.as_str()));

    // Loaded file is the same event.
    let loaded = torq_buzz_event_verify::load_signed_event(&journal).unwrap();
    assert_eq!(loaded.id.to_hex(), id);
    assert_eq!(n, 3);
}

#[test]
fn t_copy_verification_recovery() {
    let keys = Keys::generate();
    let human = keys.public_key().to_hex();
    let signed = sign(&keys, DEST_CHANNEL, APPROVED_CONTENT);
    let dir = tempdir().unwrap();
    let path = dir.path().join("signed-event.json");

    let journal = journal_for(&human);
    let journal = match advance_after_duplicate_check(journal, &[], &plan(), Utc::now()).unwrap() {
        AdvanceOutcome::NeedsSign { journal } => journal,
        other => panic!("{other:?}"),
    };
    let journal = persist_signed_event(journal, &signed, &path, Utc::now()).unwrap();
    let mut publish = |_e: &Event| Ok(());
    let journal = retry_publish(journal, &mut publish, Utc::now()).unwrap();
    assert_eq!(journal.current_state, CopySelectedState::Published);

    // Interrupted: re-query empty → needs publish of same signed event.
    let out =
        recover_interrupted_verification(journal.clone(), &[], &plan(), Utc::now()).unwrap();
    match out {
        RecoveryOutcome::NeedsPublish { journal: j } => {
            assert_eq!(j.current_state, CopySelectedState::Signed);
            assert_eq!(j.destination_event_id, journal.destination_event_id);
        }
        other => panic!("expected NeedsPublish, got {other:?}"),
    }

    // Interrupted: re-query finds the one copy → COMPLETE without re-sign.
    let out =
        recover_interrupted_verification(journal, &[signed.clone()], &plan(), Utc::now()).unwrap();
    match out {
        RecoveryOutcome::Complete {
            journal,
            destination_event_id,
        } => {
            assert_eq!(journal.current_state, CopySelectedState::Complete);
            assert_eq!(destination_event_id, signed.id.to_hex());
            // signed path still the original
            assert!(journal.signed_event_path.is_some());
        }
        other => panic!("expected Complete, got {other:?}"),
    }
}

#[test]
fn t_copy_verifier_none_and_semantic_and_drift() {
    let keys = Keys::generate();
    let human = keys.public_key().to_hex();
    let mut journal = journal_for(&human);
    journal.destination_event_id = Some("f".repeat(64));

    // none
    let input = VerifySelectedInput {
        schema_version: 1,
        permanent_human_pubkey: human.clone(),
        destination_channel_id: DEST_CHANNEL.into(),
        expected_content: APPROVED_CONTENT.into(),
        intended_kind: INTENDED_KIND,
        intended_relay_url: INTENDED_RELAY_URL.into(),
        events_json: "[]".into(),
        journal: journal.clone(),
        source_plan: plan_dto(),
        expected_destination_event_id: journal.destination_event_id.clone(),
    };
    assert_eq!(verify_selected_message(&input).exit_code, EXIT_NONE);

    // semantic: wrong author event present
    let other = Keys::generate();
    let wrong = sign(&other, DEST_CHANNEL, APPROVED_CONTENT);
    let input = VerifySelectedInput {
        events_json: format!("[{}]", wrong.as_json()),
        ..input
    };
    assert_eq!(verify_selected_message(&input).exit_code, EXIT_SEMANTIC);

    // source drift
    let mut bad = journal.clone();
    bad.source_event_id = "0".repeat(64);
    let input = VerifySelectedInput {
        journal: bad,
        events_json: "[]".into(),
        source_plan: plan_dto(),
        permanent_human_pubkey: human,
        destination_channel_id: DEST_CHANNEL.into(),
        expected_content: APPROVED_CONTENT.into(),
        intended_kind: INTENDED_KIND,
        intended_relay_url: INTENDED_RELAY_URL.into(),
        schema_version: 1,
        expected_destination_event_id: None,
    };
    assert_eq!(verify_selected_message(&input).exit_code, EXIT_SOURCE_DRIFT);
}

#[test]
fn t_copy_verifier_ambiguous_exit() {
    let keys = Keys::generate();
    let human = keys.public_key().to_hex();
    let e1 = sign(&keys, DEST_CHANNEL, APPROVED_CONTENT);
    std::thread::sleep(std::time::Duration::from_millis(1100));
    let e2 = sign(&keys, DEST_CHANNEL, APPROVED_CONTENT);
    let mut journal = journal_for(&human);
    journal.destination_event_id = Some(e1.id.to_hex());
    let input = VerifySelectedInput {
        schema_version: 1,
        permanent_human_pubkey: human,
        destination_channel_id: DEST_CHANNEL.into(),
        expected_content: APPROVED_CONTENT.into(),
        intended_kind: INTENDED_KIND,
        intended_relay_url: INTENDED_RELAY_URL.into(),
        events_json: format!("[{},{}]", e1.as_json(), e2.as_json()),
        journal,
        source_plan: plan_dto(),
        expected_destination_event_id: None,
    };
    let result = verify_selected_message(&input);
    assert_eq!(result.exit_code, EXIT_AMBIGUOUS);
    assert_eq!(result.output.valid_copy_count, 2);
}

#[test]
fn t_copy_verifier_exit_io_malformed_events_json() {
    let keys = Keys::generate();
    let human = keys.public_key().to_hex();
    let mut journal = journal_for(&human);
    journal.destination_event_id = Some("f".repeat(64));
    let input = VerifySelectedInput {
        schema_version: 1,
        permanent_human_pubkey: human,
        destination_channel_id: DEST_CHANNEL.into(),
        expected_content: APPROVED_CONTENT.into(),
        intended_kind: INTENDED_KIND,
        intended_relay_url: INTENDED_RELAY_URL.into(),
        events_json: "not-json".into(),
        journal,
        source_plan: plan_dto(),
        expected_destination_event_id: None,
    };
    let result = verify_selected_message(&input);
    assert_eq!(result.exit_code, EXIT_IO);
    assert_eq!(result.exit_code, 24);
    assert!(!result.output.ok);
}

#[test]
fn approved_source_constants_match_pilot_evidence() {
    assert_eq!(APPROVED_CONTENT, "TORQ_BUZZ_RUNTIME_ACCEPTANCE_001");
    assert_eq!(INTENDED_KIND, 9);
    assert_eq!(INTENDED_RELAY_URL, "ws://127.0.0.1:3300");
    assert_eq!(
        content_sha256_hex(APPROVED_CONTENT),
        content_sha256_hex("TORQ_BUZZ_RUNTIME_ACCEPTANCE_001")
    );
}
