//! `verify-selected-message` contract and exit codes.

use serde::{Deserialize, Serialize};

use crate::journal::{content_sha256_hex, CopySelectedJournal, INTENDED_KIND, INTENDED_RELAY_URL};
use crate::semantic::{filter_semantic_copies, parse_event_array, SemanticCopyExpectation};
use crate::step::{source_plan_matches, SourcePlan};

/// Exit: exactly one valid destination copy.
pub const EXIT_OK: i32 = 0;
/// Exit: invalid signature or semantic mismatch on required event.
pub const EXIT_SEMANTIC: i32 = 22;
/// Exit: none found after publish/retrieval window.
pub const EXIT_NONE: i32 = 23;
/// Exit: relay/query I/O failure (or input I/O).
pub const EXIT_IO: i32 = 24;
/// Exit: ambiguous duplicate.
pub const EXIT_AMBIGUOUS: i32 = 26;
/// Exit: source-plan drift.
pub const EXIT_SOURCE_DRIFT: i32 = 27;

/// Input document for `verify-selected-message`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VerifySelectedInput {
    pub schema_version: u32,
    pub permanent_human_pubkey: String,
    pub destination_channel_id: String,
    pub expected_content: String,
    pub intended_kind: u16,
    pub intended_relay_url: String,
    /// Path or inline JSON array of events retrieved from the permanent relay.
    pub events_json: String,
    /// Journal snapshot (or equivalent plan binding) for source-unchanged checks.
    pub journal: CopySelectedJournal,
    /// Approved source plan (must match journal).
    pub source_plan: SourcePlanDto,
    /// When set, require this exact destination event id among the valid copies.
    #[serde(default)]
    pub expected_destination_event_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SourcePlanDto {
    pub source_event_id: String,
    pub source_event_author: String,
    pub source_channel_id: String,
    pub content: String,
}

impl From<&SourcePlanDto> for SourcePlan {
    fn from(d: &SourcePlanDto) -> Self {
        Self {
            source_event_id: d.source_event_id.clone(),
            source_event_author: d.source_event_author.clone(),
            source_channel_id: d.source_channel_id.clone(),
            content: d.content.clone(),
            content_sha256: content_sha256_hex(&d.content),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VerifySelectedOutput {
    pub schema_version: u32,
    pub ok: bool,
    pub exit_code: i32,
    pub valid_copy_count: usize,
    pub destination_event_id: Option<String>,
    pub valid_event_ids: Vec<String>,
    pub errors: Vec<String>,
    pub checks: VerifyChecks,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct VerifyChecks {
    pub event_verify: bool,
    pub kind_ok: bool,
    pub author_ok: bool,
    pub h_tag_ok: bool,
    pub content_ok: bool,
    pub exactly_one_valid_copy: bool,
    pub destination_id_recorded: bool,
    pub source_unchanged: bool,
    pub relay_url_ok: bool,
}

#[derive(Debug, Clone)]
pub struct VerifySelectedResult {
    pub exit_code: i32,
    pub output: VerifySelectedOutput,
}

/// Run the hard verifier contract for the selected migration message.
pub fn verify_selected_message(input: &VerifySelectedInput) -> VerifySelectedResult {
    let mut errors = Vec::new();
    let mut checks = VerifyChecks::default();

    if input.schema_version != 1 {
        errors.push(format!("unsupported schema_version {}", input.schema_version));
        return fail(EXIT_IO, 0, None, vec![], errors, checks);
    }

    checks.relay_url_ok = input.intended_relay_url == INTENDED_RELAY_URL
        && input.journal.intended_relay_url == INTENDED_RELAY_URL;
    if !checks.relay_url_ok {
        errors.push(format!(
            "intended_relay_url must be {INTENDED_RELAY_URL}"
        ));
    }

    if input.intended_kind != INTENDED_KIND || input.journal.intended_kind != INTENDED_KIND {
        errors.push(format!("intended_kind must be {INTENDED_KIND}"));
    }

    let plan = SourcePlan::from(&input.source_plan);
    checks.source_unchanged = source_plan_matches(&input.journal, &plan)
        && input.journal.source_event_id == input.source_plan.source_event_id
        && input.journal.source_event_author == input.source_plan.source_event_author
        && input.journal.source_channel_id == input.source_plan.source_channel_id
        && content_sha256_hex(&input.expected_content) == input.journal.content_sha256
        && input.expected_content == input.source_plan.content;

    if !checks.source_unchanged {
        errors.push("source-plan drift: source event/channel/content hash mismatch".into());
        return fail(EXIT_SOURCE_DRIFT, 0, None, vec![], errors, checks);
    }

    let events = match parse_event_array(&input.events_json) {
        Ok(e) => e,
        Err(e) => {
            errors.push(e);
            return fail(EXIT_IO, 0, None, vec![], errors, checks);
        }
    };

    let expected = SemanticCopyExpectation::new(
        &input.permanent_human_pubkey,
        &input.destination_channel_id,
        &input.expected_content,
    );
    // Align expectation kind if caller set it.
    let mut expected = expected;
    expected.kind = input.intended_kind;

    let matches = filter_semantic_copies(&events, &expected);
    let ids: Vec<String> = matches.iter().map(|m| m.event_id.clone()).collect();
    let count = ids.len();

    // Populate aggregate checks from the sole match when present.
    if count == 1 {
        checks.event_verify = true;
        checks.kind_ok = true;
        checks.author_ok = true;
        checks.h_tag_ok = true;
        checks.content_ok = true;
        checks.exactly_one_valid_copy = true;
        let dest = ids[0].clone();
        let recorded = input
            .journal
            .destination_event_id
            .as_ref()
            .map(|s| s == &dest)
            .unwrap_or(false)
            || input
                .expected_destination_event_id
                .as_ref()
                .map(|s| s == &dest)
                .unwrap_or(false);
        // Destination must be recorded on the journal for the migration receipt.
        checks.destination_id_recorded = input.journal.destination_event_id.as_ref() == Some(&dest)
            || input.expected_destination_event_id.as_ref() == Some(&dest);

        if let Some(expected_id) = &input.expected_destination_event_id {
            if expected_id != &dest {
                errors.push("destination event id does not match expected".into());
                checks.destination_id_recorded = false;
                return fail(EXIT_SEMANTIC, count, Some(dest), ids, errors, checks);
            }
        }

        if input.journal.destination_event_id.is_none()
            && input.expected_destination_event_id.is_none()
        {
            // Allow verify to report the observed id even if journal not yet written,
            // but require recorded flag false → still fail closed for migration.
            errors.push("destination_event_id not recorded in journal/receipt".into());
            checks.destination_id_recorded = false;
            return fail(EXIT_SEMANTIC, count, Some(dest), ids, errors, checks);
        }

        if !checks.destination_id_recorded && !recorded {
            errors.push("destination_event_id not recorded".into());
            return fail(EXIT_SEMANTIC, count, Some(dest), ids, errors, checks);
        }

        // If journal has a different id, fail.
        if let Some(j_id) = &input.journal.destination_event_id {
            if j_id != &dest {
                errors.push("journal destination_event_id does not match sole valid copy".into());
                return fail(EXIT_SEMANTIC, count, Some(dest), ids, errors, checks);
            }
        }

        checks.destination_id_recorded = true;
        if !checks.relay_url_ok {
            return fail(EXIT_SEMANTIC, count, Some(dest), ids, errors, checks);
        }

        return VerifySelectedResult {
            exit_code: EXIT_OK,
            output: VerifySelectedOutput {
                schema_version: 1,
                ok: true,
                exit_code: EXIT_OK,
                valid_copy_count: count,
                destination_event_id: Some(dest),
                valid_event_ids: ids,
                errors,
                checks,
            },
        };
    }

    if count == 0 {
        // Distinguish empty retrieval vs present-but-invalid.
        if events.is_empty() {
            errors.push("no events retrieved from relay query".into());
            return fail(EXIT_NONE, 0, None, vec![], errors, checks);
        }
        errors.push(
            "events present but none passed Event::verify + kind/author/h/content checks".into(),
        );
        // Prefer semantic failure when candidates existed but were invalid.
        return fail(EXIT_SEMANTIC, 0, None, vec![], errors, checks);
    }

    // count > 1
    checks.exactly_one_valid_copy = false;
    errors.push(format!("ambiguous duplicate: {count} valid semantic copies"));
    fail(EXIT_AMBIGUOUS, count, None, ids, errors, checks)
}

fn fail(
    exit_code: i32,
    valid_copy_count: usize,
    destination_event_id: Option<String>,
    valid_event_ids: Vec<String>,
    errors: Vec<String>,
    checks: VerifyChecks,
) -> VerifySelectedResult {
    VerifySelectedResult {
        exit_code,
        output: VerifySelectedOutput {
            schema_version: 1,
            ok: false,
            exit_code,
            valid_copy_count,
            destination_event_id,
            valid_event_ids,
            errors,
            checks,
        },
    }
}
