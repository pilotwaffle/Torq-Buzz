//! Write-ahead journal record for `COPY_SELECTED_MESSAGE`.
//!
//! No private keys or secret material are accepted in this schema.

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

/// Exact approved acceptance content (byte-for-byte).
pub const APPROVED_CONTENT: &str = "TORQ_BUZZ_RUNTIME_ACCEPTANCE_001";

/// Destination event kind for the migration copy.
pub const INTENDED_KIND: u16 = 9;

/// Permanent relay WebSocket URL for the migration copy.
pub const INTENDED_RELAY_URL: &str = "ws://127.0.0.1:3300";

/// States for the `COPY_SELECTED_MESSAGE` step.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum CopySelectedState {
    Planned,
    DuplicateChecked,
    Signed,
    Published,
    Verified,
    Complete,
    CompleteReused,
    AmbiguousDuplicate,
}

impl CopySelectedState {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Planned => "PLANNED",
            Self::DuplicateChecked => "DUPLICATE_CHECKED",
            Self::Signed => "SIGNED",
            Self::Published => "PUBLISHED",
            Self::Verified => "VERIFIED",
            Self::Complete => "COMPLETE",
            Self::CompleteReused => "COMPLETE_REUSED",
            Self::AmbiguousDuplicate => "AMBIGUOUS_DUPLICATE",
        }
    }

    pub fn is_terminal(self) -> bool {
        matches!(
            self,
            Self::Complete | Self::CompleteReused | Self::AmbiguousDuplicate
        )
    }
}

/// RFC3339 timestamps recorded before each successful transition.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
pub struct JournalTimestamps {
    pub planned_utc: Option<DateTime<Utc>>,
    pub duplicate_checked_utc: Option<DateTime<Utc>>,
    pub signed_utc: Option<DateTime<Utc>>,
    pub published_utc: Option<DateTime<Utc>>,
    pub verified_utc: Option<DateTime<Utc>>,
    pub completed_utc: Option<DateTime<Utc>>,
}

/// Append-only journal record for one `COPY_SELECTED_MESSAGE` run.
///
/// Persist a new copy of this record (or a JSONL line) before each transition.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CopySelectedJournal {
    pub schema_version: u32,
    pub migration_run_id: String,
    pub step: String,
    pub source_event_id: String,
    pub source_event_author: String,
    pub source_channel_id: String,
    pub destination_channel_id: String,
    pub destination_public_key: String,
    pub content_sha256: String,
    pub intended_kind: u16,
    pub intended_relay_url: String,
    pub current_state: CopySelectedState,
    pub destination_event_id: Option<String>,
    pub signed_event_path: Option<String>,
    pub signed_event_sha256: Option<String>,
    pub verification_result: Option<String>,
    pub timestamps: JournalTimestamps,
}

impl CopySelectedJournal {
    pub const SCHEMA_VERSION: u32 = 1;
    pub const STEP: &'static str = "COPY_SELECTED_MESSAGE";

    /// Build a `PLANNED` journal row from migration plan fields.
    ///
    /// `content` must equal [`APPROVED_CONTENT`] for the Gate-1 acceptance copy;
    /// callers may pass it explicitly so source-plan drift is detectable later.
    pub fn planned(
        migration_run_id: impl Into<String>,
        source_event_id: impl Into<String>,
        source_event_author: impl Into<String>,
        source_channel_id: impl Into<String>,
        destination_channel_id: impl Into<String>,
        destination_public_key: impl Into<String>,
        content: &str,
        now: DateTime<Utc>,
    ) -> Self {
        Self {
            schema_version: Self::SCHEMA_VERSION,
            migration_run_id: migration_run_id.into(),
            step: Self::STEP.to_string(),
            source_event_id: source_event_id.into(),
            source_event_author: source_event_author.into(),
            source_channel_id: source_channel_id.into(),
            destination_channel_id: destination_channel_id.into(),
            destination_public_key: destination_public_key.into(),
            content_sha256: content_sha256_hex(content),
            intended_kind: INTENDED_KIND,
            intended_relay_url: INTENDED_RELAY_URL.to_string(),
            current_state: CopySelectedState::Planned,
            destination_event_id: None,
            signed_event_path: None,
            signed_event_sha256: None,
            verification_result: None,
            timestamps: JournalTimestamps {
                planned_utc: Some(now),
                ..JournalTimestamps::default()
            },
        }
    }

    pub fn to_canonical_json(&self) -> Result<String, serde_json::Error> {
        serde_json::to_string_pretty(self)
    }

    pub fn from_json(s: &str) -> Result<Self, serde_json::Error> {
        serde_json::from_str(s)
    }
}

/// SHA-256 of UTF-8 content bytes, lowercase hex.
pub fn content_sha256_hex(content: &str) -> String {
    let digest = Sha256::digest(content.as_bytes());
    hex::encode(digest)
}

/// SHA-256 of arbitrary bytes (e.g. signed event JSON file), lowercase hex.
pub fn bytes_sha256_hex(bytes: &[u8]) -> String {
    let digest = Sha256::digest(bytes);
    hex::encode(digest)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn approved_content_hash_is_stable() {
        let h = content_sha256_hex(APPROVED_CONTENT);
        assert_eq!(h.len(), 64);
        assert_eq!(h, content_sha256_hex(APPROVED_CONTENT));
        assert_ne!(h, content_sha256_hex("other"));
    }

    #[test]
    fn planned_journal_has_required_fields() {
        let now = Utc::now();
        let j = CopySelectedJournal::planned(
            "run-1",
            "aa".repeat(32),
            "bb".repeat(32),
            "11111111-1111-1111-1111-111111111111",
            "22222222-2222-2222-2222-222222222222",
            "cc".repeat(32),
            APPROVED_CONTENT,
            now,
        );
        assert_eq!(j.schema_version, 1);
        assert_eq!(j.step, "COPY_SELECTED_MESSAGE");
        assert_eq!(j.current_state, CopySelectedState::Planned);
        assert_eq!(j.intended_kind, 9);
        assert_eq!(j.intended_relay_url, INTENDED_RELAY_URL);
        assert!(j.destination_event_id.is_none());
        let round = CopySelectedJournal::from_json(&j.to_canonical_json().unwrap()).unwrap();
        assert_eq!(round, j);
    }

    #[test]
    fn journal_json_contains_no_secret_key_fields() {
        let j = CopySelectedJournal::planned(
            "run-1",
            "aa".repeat(32),
            "bb".repeat(32),
            "11111111-1111-1111-1111-111111111111",
            "22222222-2222-2222-2222-222222222222",
            "cc".repeat(32),
            APPROVED_CONTENT,
            Utc::now(),
        );
        let s = j.to_canonical_json().unwrap().to_lowercase();
        assert!(!s.contains("private_key"));
        assert!(!s.contains("secret_key"));
        assert!(!s.contains("nsec"));
        assert!(!s.contains("seckey"));
    }
}
