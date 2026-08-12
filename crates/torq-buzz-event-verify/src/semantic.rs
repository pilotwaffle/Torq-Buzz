//! Semantic equality for destination migration copies.
//!
//! A valid semantic copy requires all of:
//! - `Event::verify()` success
//! - `kind == 9`
//! - `author == permanent human pubkey`
//! - at least one `h` tag equal to the destination channel UUID
//! - content byte-for-byte equal to the approved text
//!
//! Invalid signature / wrong author / wrong tag / wrong content does **not** count.

use nostr::{Event, JsonUtil, Kind, PublicKey};
use serde::{Deserialize, Serialize};

use crate::journal::INTENDED_KIND;

/// Fields that define semantic equality for the migration copy.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SemanticCopyExpectation {
    pub permanent_human_pubkey: String,
    pub destination_channel_id: String,
    pub content: String,
    #[serde(default = "default_kind")]
    pub kind: u16,
}

fn default_kind() -> u16 {
    INTENDED_KIND
}

impl SemanticCopyExpectation {
    pub fn new(
        permanent_human_pubkey: impl Into<String>,
        destination_channel_id: impl Into<String>,
        content: impl Into<String>,
    ) -> Self {
        Self {
            permanent_human_pubkey: permanent_human_pubkey.into(),
            destination_channel_id: destination_channel_id.into(),
            content: content.into(),
            kind: INTENDED_KIND,
        }
    }
}

/// One event that passed semantic equality.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SemanticCopyMatch {
    pub event_id: String,
    pub author: String,
}

/// Returns true when `event` is a valid semantic destination copy.
pub fn is_semantic_copy(event: &Event, expected: &SemanticCopyExpectation) -> bool {
    if event.verify().is_err() {
        return false;
    }
    if event.kind.as_u16() != expected.kind {
        return false;
    }
    let Ok(expected_pk) = PublicKey::parse(&expected.permanent_human_pubkey) else {
        return false;
    };
    if event.pubkey != expected_pk {
        return false;
    }
    if event.content != expected.content {
        return false;
    }
    has_h_tag(event, &expected.destination_channel_id)
}

fn has_h_tag(event: &Event, channel_id: &str) -> bool {
    event.tags.iter().any(|tag| {
        let slice = tag.as_slice();
        slice.len() >= 2 && slice[0] == "h" && slice[1] == channel_id
    })
}

/// Filter a list of candidate events down to valid semantic copies.
pub fn filter_semantic_copies(
    events: &[Event],
    expected: &SemanticCopyExpectation,
) -> Vec<SemanticCopyMatch> {
    events
        .iter()
        .filter(|e| is_semantic_copy(e, expected))
        .map(|e| SemanticCopyMatch {
            event_id: e.id.to_hex(),
            author: e.pubkey.to_hex(),
        })
        .collect()
}

/// Parse a JSON array of Nostr events (as returned by relay query).
pub fn parse_event_array(json: &str) -> Result<Vec<Event>, String> {
    let values: Vec<serde_json::Value> =
        serde_json::from_str(json).map_err(|e| format!("event array json: {e}"))?;
    let mut out = Vec::with_capacity(values.len());
    for (i, v) in values.into_iter().enumerate() {
        let s = serde_json::to_string(&v).map_err(|e| format!("event[{i}] re-serialize: {e}"))?;
        let event = Event::from_json(&s).map_err(|e| format!("event[{i}] parse: {e}"))?;
        out.push(event);
    }
    Ok(out)
}

/// Kind helper for tests and builders.
pub fn kind_9() -> Kind {
    Kind::from_u16(INTENDED_KIND)
}

#[cfg(test)]
mod tests {
    use super::*;
    use nostr::{EventBuilder, Keys, Tag};

    fn sign_copy(keys: &Keys, channel: &str, content: &str) -> Event {
        EventBuilder::new(kind_9(), content)
            .tags([Tag::parse(["h", channel]).expect("h tag")])
            .sign_with_keys(keys)
            .expect("sign")
    }

    #[test]
    fn accepts_valid_semantic_copy() {
        let keys = Keys::generate();
        let channel = "22222222-2222-2222-2222-222222222222";
        let content = "TORQ_BUZZ_RUNTIME_ACCEPTANCE_001";
        let event = sign_copy(&keys, channel, content);
        let expected = SemanticCopyExpectation::new(keys.public_key().to_hex(), channel, content);
        assert!(is_semantic_copy(&event, &expected));
    }

    #[test]
    fn rejects_wrong_content() {
        let keys = Keys::generate();
        let channel = "22222222-2222-2222-2222-222222222222";
        let event = sign_copy(&keys, channel, "WRONG");
        let expected = SemanticCopyExpectation::new(
            keys.public_key().to_hex(),
            channel,
            "TORQ_BUZZ_RUNTIME_ACCEPTANCE_001",
        );
        assert!(!is_semantic_copy(&event, &expected));
    }

    #[test]
    fn rejects_wrong_author() {
        let keys = Keys::generate();
        let other = Keys::generate();
        let channel = "22222222-2222-2222-2222-222222222222";
        let content = "TORQ_BUZZ_RUNTIME_ACCEPTANCE_001";
        let event = sign_copy(&keys, channel, content);
        let expected = SemanticCopyExpectation::new(other.public_key().to_hex(), channel, content);
        assert!(!is_semantic_copy(&event, &expected));
    }

    #[test]
    fn rejects_wrong_h_tag() {
        let keys = Keys::generate();
        let content = "TORQ_BUZZ_RUNTIME_ACCEPTANCE_001";
        let event = sign_copy(&keys, "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", content);
        let expected = SemanticCopyExpectation::new(
            keys.public_key().to_hex(),
            "22222222-2222-2222-2222-222222222222",
            content,
        );
        assert!(!is_semantic_copy(&event, &expected));
    }

    #[test]
    fn rejects_tampered_signature() {
        let keys = Keys::generate();
        let channel = "22222222-2222-2222-2222-222222222222";
        let content = "TORQ_BUZZ_RUNTIME_ACCEPTANCE_001";
        let event = sign_copy(&keys, channel, content);
        let mut json: serde_json::Value = serde_json::from_str(&event.as_json()).unwrap();
        json["sig"] = serde_json::Value::String("0".repeat(128));
        let tampered = Event::from_json(json.to_string()).unwrap();
        let expected = SemanticCopyExpectation::new(keys.public_key().to_hex(), channel, content);
        assert!(!is_semantic_copy(&tampered, &expected));
    }

    #[test]
    fn invalid_candidates_do_not_count_in_filter() {
        let keys = Keys::generate();
        let other = Keys::generate();
        let channel = "22222222-2222-2222-2222-222222222222";
        let content = "TORQ_BUZZ_RUNTIME_ACCEPTANCE_001";
        let good = sign_copy(&keys, channel, content);
        let bad_author = sign_copy(&other, channel, content);
        let bad_content = sign_copy(&keys, channel, "nope");
        let expected = SemanticCopyExpectation::new(keys.public_key().to_hex(), channel, content);
        let matches = filter_semantic_copies(&[good, bad_author, bad_content], &expected);
        assert_eq!(matches.len(), 1);
    }
}
