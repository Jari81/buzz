//! Strict, local ingress checks for the one MyBuzz `test-ready` handoff shape.
//!
//! Relay authentication verifies the outer Nostr signature before this module
//! receives an event.  This module deliberately validates only the immutable
//! handoff grammar; it does not claim to independently verify a relay event.

use nostr::Event;
use sha2::{Digest, Sha256};
use uuid::Uuid;

/// The one project channel whose kind-1 events are MyBuzz review receipts.
pub(crate) const MYBUZZ_CHANNEL: &str = "70114f25-3b91-46f5-bea8-7125dbb18336";

pub(crate) const MYBUZZ_REPOSITORY: &str =
    "30617:1af26bb78ad6313ca562eed7bec2c72f69ceacce968fb06b92de0aad26901ada:mybuzz";
pub(crate) const MYBUZZ_REVIEWER: &str =
    "ea7615e8756cee7ca1cd9176271145c475abdd6e8139d578a9a7f5320dc919b4";
pub(crate) const MYBUZZ_ROBI: &str =
    "1af26bb78ad6313ca562eed7bec2c72f69ceacce968fb06b92de0aad26901ada";
pub(crate) const MYBUZZ_WRITERS: [&str; 2] = [
    "dfbb7275f14e56a93874b59ad65aca19e81005668568820255edda69a44b6e9c",
    "d91956e1547150ee4150aa563263d6c5b937e28be4d44fd0f3157ad5282d8ccc",
];

/// Immutable fields from the already-strictly-validated recovery candidate.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub(crate) struct TestReadyReceipt {
    pub(crate) event_id: String,
    pub(crate) issue_id: String,
    pub(crate) writer_pubkey: String,
    pub(crate) created_at: u64,
}

/// Why a test-ready receipt did not satisfy the local MyBuzz grammar.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum TestReadyRejection {
    NotMyBuzzReceipt,
    InvalidReviewer,
    InvalidAuthor,
    InvalidId,
    InvalidTags,
    InvalidContent,
    InvalidManifest,
    InvalidFingerprint,
}

fn lower_hex(value: &str, length: usize) -> bool {
    value.len() == length
        && value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

fn sha256_hex(input: &str) -> String {
    hex::encode(Sha256::digest(input.as_bytes()))
}

fn tags(event: &Event) -> Vec<Vec<&str>> {
    event
        .tags
        .iter()
        .map(|tag| tag.as_slice().iter().map(String::as_str).collect())
        .collect()
}

fn valid_worktree_path(stream: &str, path: &str) -> bool {
    let expected = match stream {
        "windows" => "/home/coder/work/worktrees/mybuzz-windows",
        "android" => "/home/coder/work/worktrees/buzz-mobile-issue-d",
        "acp" => "/home/coder/work/worktrees/mybuzz-acp",
        _ => return false,
    };
    path == expected
        && path.strip_prefix('/').is_some_and(|relative| {
            relative
                .split('/')
                .all(|part| !part.is_empty() && part != "." && part != "..")
        })
}

fn valid_manifest(raw: &str) -> bool {
    let Ok(value) = serde_json::from_str::<serde_json::Value>(raw) else {
        return false;
    };
    if serde_json::to_string(&value).ok().as_deref() != Some(raw) {
        return false;
    }
    let Some(entries) = value.as_array() else {
        return false;
    };
    if entries.is_empty() {
        return false;
    }
    let mut previous = None;
    for entry in entries {
        let Some(object) = entry.as_object() else {
            return false;
        };
        if object.len() != 3 {
            return false;
        }
        let (Some(path), Some(state), Some(hash)) = (
            object.get("path").and_then(serde_json::Value::as_str),
            object.get("state").and_then(serde_json::Value::as_str),
            object.get("sha256").and_then(serde_json::Value::as_str),
        ) else {
            return false;
        };
        if path.is_empty()
            || path.starts_with('/')
            || path
                .split('/')
                .any(|part| part.is_empty() || part == "." || part == "..")
            || !matches!(state, "added" | "modified" | "deleted" | "symlink")
            || !lower_hex(hash, 64)
            || previous.is_some_and(|last: &str| last >= path)
        {
            return false;
        }
        previous = Some(path);
    }
    true
}

/// Returns whether the event is the single MyBuzz kind that replaces generic ingress.
pub(crate) fn is_strict_mybuzz_kind_one(channel_id: Uuid, kind: u16) -> bool {
    kind == 1
        && MYBUZZ_CHANNEL
            .parse::<Uuid>()
            .is_ok_and(|expected| channel_id == expected)
}

/// Validate the exact signed MyBuzz `test-ready` grammar before queue mutation.
///
/// The caller must invoke this only after its regular author and local-recipient
/// checks.  Non-MyBuzz events receive [`TestReadyRejection::NotMyBuzzReceipt`]
/// and must retain generic ACP handling.
pub(crate) fn strict_test_ready(
    event: &Event,
    channel_id: Uuid,
    reviewer_pubkey: &str,
) -> Result<TestReadyReceipt, TestReadyRejection> {
    let expected_channel = MYBUZZ_CHANNEL
        .parse::<Uuid>()
        .map_err(|_| TestReadyRejection::NotMyBuzzReceipt)?;
    if channel_id != expected_channel || event.kind.as_u16() != 1 {
        return Err(TestReadyRejection::NotMyBuzzReceipt);
    }
    if !lower_hex(reviewer_pubkey, 64) {
        return Err(TestReadyRejection::InvalidReviewer);
    }
    if !MYBUZZ_WRITERS.contains(&event.pubkey.to_hex().as_str()) {
        return Err(TestReadyRejection::InvalidAuthor);
    }
    if !lower_hex(&event.id.to_hex(), 64) {
        return Err(TestReadyRejection::InvalidId);
    }

    let tags = tags(event);
    if tags.len() != 11
        || tags[0] != ["h", MYBUZZ_CHANNEL]
        || tags[1].len() != 4
        || tags[1].as_slice() != ["e", tags[1][1], "", "root"]
        || !lower_hex(tags[1][1], 64)
        || tags[2] != ["a", MYBUZZ_REPOSITORY]
        || tags[3] != ["t", "test-ready"]
        || tags[4].len() != 2
        || tags[4][0] != "stream"
        || !matches!(tags[4][1], "windows" | "android" | "acp")
        || tags[5].len() != 2
        || tags[5][0] != "worktree"
        || !valid_worktree_path(tags[4][1], tags[5][1])
        || tags[6].len() != 2
        || tags[6][0] != "base"
        || !(lower_hex(tags[6][1], 40) || lower_hex(tags[6][1], 64))
        || tags[7].len() != 2
        || tags[7][0] != "candidate"
        || !lower_hex(tags[7][1], 64)
        || tags[8].len() != 2
        || tags[8][0] != "paths-sha256"
        || !lower_hex(tags[8][1], 64)
        || tags[9].len() != 2
        || tags[9][0] != "path-manifest"
        || tags[10] != ["p", reviewer_pubkey]
    {
        return Err(TestReadyRejection::InvalidTags);
    }
    if !valid_manifest(tags[9][1]) {
        return Err(TestReadyRejection::InvalidManifest);
    }
    if sha256_hex(tags[9][1]) != tags[8][1]
        || sha256_hex(&format!(
            r#"{{"base":"{}","paths":{}}}"#,
            tags[6][1], tags[9][1]
        )) != tags[7][1]
    {
        return Err(TestReadyRejection::InvalidFingerprint);
    }

    let expected_content = format!(
        "[TEST-READY]\nIssue: {}\nStream: {}\nWorktree: {}\nBase-SHA: {}\nCandidate-Fingerprint: {}\nPaths-SHA256: {}\nTests: ",
        tags[1][1], tags[4][1], tags[5][1], tags[6][1], tags[7][1], tags[8][1]
    );
    let Some(tests) = event.content.strip_prefix(&expected_content) else {
        return Err(TestReadyRejection::InvalidContent);
    };
    if tests.is_empty()
        || tests != tests.trim()
        || tests.contains('\n')
        || tests.chars().any(char::is_control)
    {
        return Err(TestReadyRejection::InvalidContent);
    }
    Ok(TestReadyReceipt {
        event_id: event.id.to_hex(),
        issue_id: tags[1][1].to_string(),
        writer_pubkey: event.pubkey.to_hex(),
        created_at: event.created_at.as_secs(),
    })
}

#[cfg(test)]
mod tests {
    use sha2::{Digest, Sha256};

    use super::{is_strict_mybuzz_kind_one, strict_test_ready, MYBUZZ_CHANNEL};

    const REVIEWER: &str = "ea7615e8756cee7ca1cd9176271145c475abdd6e8139d578a9a7f5320dc919b4";
    const KILO_WRITER: &str = "d91956e1547150ee4150aa563263d6c5b937e28be4d44fd0f3157ad5282d8ccc";
    const ISSUE: &str = "a5c1c6ebe59db5a38a62157be9f8360e442eefdbd24da2e066484abfd61b54aa";
    const REPOSITORY: &str =
        "30617:1af26bb78ad6313ca562eed7bec2c72f69ceacce968fb06b92de0aad26901ada:mybuzz";

    fn sha256_hex(input: &str) -> String {
        hex::encode(Sha256::digest(input.as_bytes()))
    }

    fn valid_receipt() -> nostr::Event {
        let manifest = r#"[{"path":"crates/buzz-acp/src/lib.rs","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","state":"modified"}]"#;
        let base = "0123456789abcdef0123456789abcdef01234567";
        let paths_sha256 = sha256_hex(manifest);
        let candidate = sha256_hex(&format!(r#"{{"base":"{base}","paths":{manifest}}}"#));
        let content = format!(
            "[TEST-READY]\nIssue: {ISSUE}\nStream: acp\nWorktree: /home/coder/work/worktrees/mybuzz-acp\nBase-SHA: {base}\nCandidate-Fingerprint: {candidate}\nPaths-SHA256: {paths_sha256}\nTests: cargo test -p buzz-acp --lib: 1 passed"
        );
        let tags = serde_json::json!([
            ["h", MYBUZZ_CHANNEL],
            ["e", ISSUE, "", "root"],
            ["a", REPOSITORY],
            ["t", "test-ready"],
            ["stream", "acp"],
            ["worktree", "/home/coder/work/worktrees/mybuzz-acp"],
            ["base", base],
            ["candidate", candidate],
            ["paths-sha256", paths_sha256],
            ["path-manifest", manifest],
            ["p", REVIEWER]
        ]);
        serde_json::from_value(serde_json::json!({
            "id": "b".repeat(64),
            "pubkey": KILO_WRITER,
            "created_at": 1,
            "kind": 1,
            "tags": tags,
            "content": content,
            "sig": "c".repeat(128)
        }))
        .expect("valid Nostr event fixture")
    }

    #[test]
    fn strict_gate_only_targets_mybuzz_kind_one() {
        let channel = MYBUZZ_CHANNEL.parse().expect("channel UUID");

        assert!(is_strict_mybuzz_kind_one(channel, 1));
        assert!(!is_strict_mybuzz_kind_one(channel, 9));
        assert!(!is_strict_mybuzz_kind_one(uuid::Uuid::new_v4(), 1));
    }

    #[test]
    fn exact_mybuzz_test_ready_receipt_is_accepted() {
        let event = valid_receipt();
        let channel = MYBUZZ_CHANNEL.parse().expect("channel UUID");

        assert!(strict_test_ready(&event, channel, REVIEWER).is_ok());
    }

    #[test]
    fn worktree_tag_with_parent_traversal_is_rejected() {
        let mut value = serde_json::to_value(valid_receipt()).expect("serialize fixture");
        value["tags"][5][1] = serde_json::json!("/home/coder/work/../outside");
        value["content"] =
            serde_json::Value::String(value["content"].as_str().expect("fixture content").replace(
                "/home/coder/work/worktrees/mybuzz-acp",
                "/home/coder/work/../outside",
            ));
        let event: nostr::Event = serde_json::from_value(value).expect("event fixture");
        let channel = MYBUZZ_CHANNEL.parse().expect("channel UUID");

        assert!(strict_test_ready(&event, channel, REVIEWER).is_err());
    }

    #[test]
    fn worktree_path_must_match_the_declared_stream_exactly() {
        let mut value = serde_json::to_value(valid_receipt()).expect("serialize fixture");
        value["tags"][4][1] = serde_json::json!("windows");
        value["content"] = serde_json::Value::String(
            value["content"]
                .as_str()
                .expect("fixture content")
                .replace("Stream: acp", "Stream: windows"),
        );
        let event: nostr::Event = serde_json::from_value(value).expect("event fixture");
        let channel = MYBUZZ_CHANNEL.parse().expect("channel UUID");

        assert!(strict_test_ready(&event, channel, REVIEWER).is_err());
    }
}
