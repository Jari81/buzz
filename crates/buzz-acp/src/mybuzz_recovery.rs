//! Persistent, fail-closed recovery ledger for the opt-in MyBuzz exact-ID flow.

use std::collections::BTreeMap;
use std::fs::{self, File, OpenOptions};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};

use nostr::Event;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use thiserror::Error;

use crate::mybuzz_handoff::{
    TestReadyReceipt, MYBUZZ_CHANNEL, MYBUZZ_REPOSITORY, MYBUZZ_REVIEWER, MYBUZZ_ROBI,
};

const STATE_FILE_NAME: &str = "mybuzz-recovery-v1.json";
const STATE_VERSION: u32 = 1;
const RECOVERY_WINDOW_SECS: u64 = 300;
const MAX_ATTEMPTS: u32 = 3;
pub(crate) const MYBUZZ_TERMINAL_EVIDENCE_ROOT: &str = "/mnt/mybuzz-review-recovery";
const MAX_TERMINAL_EVIDENCE_BYTES: u64 = 256 * 1024;
const MAX_SANITY_BLOCK_REASON_BYTES: usize = 500;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) struct TerminalEvidenceContract {
    repository: String,
    channel_id: String,
    reviewer_pubkey: String,
    robi_pubkey: String,
}

impl TerminalEvidenceContract {
    fn mybuzz() -> Self {
        Self {
            repository: MYBUZZ_REPOSITORY.to_string(),
            channel_id: MYBUZZ_CHANNEL.to_string(),
            reviewer_pubkey: MYBUZZ_REVIEWER.to_string(),
            robi_pubkey: MYBUZZ_ROBI.to_string(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct RecoveryState {
    pub version: u32,
    pub event_id: String,
    pub source_fingerprint: String,
    pub attempts_started: u32,
    pub deadline_unix_secs: u64,
    pub phase: RecoveryPhase,
    pub failure_class: Option<String>,
    #[serde(default)]
    pub candidate: Option<TestReadyReceipt>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub(crate) enum RecoveryPhase {
    Pending,
    Claimed,
    Dispatched,
    Terminal,
    Exhausted,
    Ambiguous,
}
impl RecoveryPhase {
    fn is_closed(self) -> bool {
        matches!(self, Self::Terminal | Self::Exhausted | Self::Ambiguous)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum ClaimResult {
    Claimed,
    AlreadyClaimed,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum AttemptStart {
    Started,
    Exhausted,
}

#[derive(Debug, Error)]
pub(crate) enum RecoveryError {
    #[error("recovery event ID must be exactly 64 lowercase hexadecimal characters")]
    InvalidEventId,
    #[error("recovery source fingerprint must be exactly 64 lowercase hexadecimal characters")]
    InvalidFingerprint,
    #[error("recovery state directory is unsafe: {0}")]
    UnsafeStateDirectory(String),
    #[error("recovery state file is unsafe: {0}")]
    UnsafeStateFile(String),
    #[error("recovery state I/O failed: {0}")]
    Io(#[from] std::io::Error),
    #[error("recovery state JSON failed: {0}")]
    Json(#[from] serde_json::Error),
    #[error("recovery state version {0} is unsupported")]
    UnsupportedVersion(u32),
    #[error("recovery state event ID does not match the configured event")]
    EventIdMismatch,
    #[error("recovery state source fingerprint does not match the configured source")]
    FingerprintMismatch,
    #[error("recovery ledger is closed in phase {0:?}")]
    Closed(RecoveryPhase),
    #[error("recovery ledger cannot {action} from phase {phase:?}")]
    InvalidTransition {
        action: &'static str,
        phase: RecoveryPhase,
    },
    #[error("recovery deadline overflow")]
    DeadlineOverflow,
    #[error("recovery failure class must be non-empty and at most 128 bytes")]
    InvalidFailureClass,
    #[error("terminal evidence is invalid: {0}")]
    InvalidTerminalEvidence(&'static str),
    #[error("terminal evidence path is unsafe: {0}")]
    UnsafeTerminalEvidence(String),
}

/// Synchronous state holder; it is intentionally not wired to relay lifecycle.
#[derive(Debug)]
pub(crate) struct RecoveryLedger {
    state_file: PathBuf,
    state: RecoveryState,
}

impl RecoveryLedger {
    /// Opens a secure existing ledger or initializes an exact-ID ledger at `now + 300`.
    pub(crate) fn open_or_create(
        state_dir: &Path,
        event_id: &str,
        source_fingerprint: &str,
        now_unix_secs: u64,
    ) -> Result<Self, RecoveryError> {
        if !valid_hex64(event_id) {
            return Err(RecoveryError::InvalidEventId);
        }
        if !valid_hex64(source_fingerprint) {
            return Err(RecoveryError::InvalidFingerprint);
        }
        validate_state_dir(state_dir)?;
        let state_file = state_dir.join(STATE_FILE_NAME);
        match fs::symlink_metadata(&state_file) {
            Ok(metadata) => {
                validate_state_file(&metadata)?;
                let state: RecoveryState = serde_json::from_slice(&fs::read(&state_file)?)?;
                if state.version != STATE_VERSION {
                    return Err(RecoveryError::UnsupportedVersion(state.version));
                }
                if state.event_id != event_id {
                    return Err(RecoveryError::EventIdMismatch);
                }
                if state.source_fingerprint != source_fingerprint {
                    return Err(RecoveryError::FingerprintMismatch);
                }
                Ok(Self { state_file, state })
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                let deadline_unix_secs = now_unix_secs
                    .checked_add(RECOVERY_WINDOW_SECS)
                    .ok_or(RecoveryError::DeadlineOverflow)?;
                let state = RecoveryState {
                    version: STATE_VERSION,
                    event_id: event_id.to_string(),
                    source_fingerprint: source_fingerprint.to_string(),
                    attempts_started: 0,
                    deadline_unix_secs,
                    phase: RecoveryPhase::Pending,
                    failure_class: None,
                    candidate: None,
                };
                write_state_atomically(state_dir, &state_file, &state)?;
                Ok(Self { state_file, state })
            }
            Err(error) => Err(RecoveryError::Io(error)),
        }
    }
    pub(crate) fn state(&self) -> &RecoveryState {
        &self.state
    }
    pub(crate) fn state_file(&self) -> &Path {
        &self.state_file
    }

    /// Stores only the immutable binding extracted from a strict test-ready receipt.
    pub(crate) fn bind_candidate(
        &mut self,
        candidate: TestReadyReceipt,
    ) -> Result<(), RecoveryError> {
        if candidate.event_id != self.state.event_id {
            return Err(RecoveryError::EventIdMismatch);
        }
        match self.state.phase {
            RecoveryPhase::Pending => {
                if self.state.candidate.as_ref() == Some(&candidate) {
                    return Ok(());
                }
                if self.state.candidate.is_some() {
                    return Err(RecoveryError::InvalidTransition {
                        action: "replace candidate binding",
                        phase: self.state.phase,
                    });
                }
                let mut next = self.state.clone();
                next.candidate = Some(candidate);
                self.persist(next)
            }
            phase if phase.is_closed() => Err(RecoveryError::Closed(phase)),
            phase => Err(RecoveryError::InvalidTransition {
                action: "bind candidate",
                phase,
            }),
        }
    }

    /// Accepts terminal evidence only for a dispatched, already-bound receipt.
    /// Closed ambiguous/exhausted ledgers deliberately remain untouched.
    pub(crate) fn try_mark_terminal_from_evidence(
        &mut self,
        evidence_root: &Path,
    ) -> Result<bool, RecoveryError> {
        match self.state.phase {
            RecoveryPhase::Terminal => return Ok(true),
            RecoveryPhase::Dispatched => {}
            _ => return Ok(false),
        }
        let Some(candidate) = self.state.candidate.as_ref() else {
            return Ok(false);
        };
        if read_terminal_evidence(
            evidence_root,
            &self.state.event_id,
            candidate,
            &TerminalEvidenceContract::mybuzz(),
        )?
        .is_none()
        {
            return Ok(false);
        }
        self.mark_terminal()?;
        Ok(true)
    }

    /// Persists the attempt count before a caller may send a recovery REQ.
    pub(crate) fn start_attempt(
        &mut self,
        now_unix_secs: u64,
    ) -> Result<AttemptStart, RecoveryError> {
        match self.state.phase {
            RecoveryPhase::Pending => {}
            phase if phase.is_closed() => return Err(RecoveryError::Closed(phase)),
            phase => {
                return Err(RecoveryError::InvalidTransition {
                    action: "start attempt",
                    phase,
                });
            }
        }
        if self.state.attempts_started >= MAX_ATTEMPTS
            || now_unix_secs >= self.state.deadline_unix_secs
        {
            let mut next = self.state.clone();
            next.phase = RecoveryPhase::Exhausted;
            next.failure_class = Some("attempt-cap-or-deadline".into());
            self.persist(next)?;
            return Ok(AttemptStart::Exhausted);
        }
        let mut next = self.state.clone();
        next.attempts_started = next
            .attempts_started
            .checked_add(1)
            .ok_or(RecoveryError::DeadlineOverflow)?;
        self.persist(next)?;
        Ok(AttemptStart::Started)
    }
    pub(crate) fn claim(&mut self) -> Result<ClaimResult, RecoveryError> {
        match self.state.phase {
            RecoveryPhase::Pending => {
                let mut next = self.state.clone();
                next.phase = RecoveryPhase::Claimed;
                self.persist(next)?;
                Ok(ClaimResult::Claimed)
            }
            RecoveryPhase::Claimed => Ok(ClaimResult::AlreadyClaimed),
            phase if phase.is_closed() => Err(RecoveryError::Closed(phase)),
            phase => Err(RecoveryError::InvalidTransition {
                action: "claim",
                phase,
            }),
        }
    }
    /// A restarted claim/dispatch cannot be retried until terminal evidence exists.
    pub(crate) fn mark_restart_without_terminal_readback(&mut self) -> Result<(), RecoveryError> {
        match self.state.phase {
            RecoveryPhase::Claimed | RecoveryPhase::Dispatched => self.mark_closed(
                RecoveryPhase::Ambiguous,
                Some("restart-without-terminal-readback".to_string()),
            ),
            phase if phase.is_closed() => Err(RecoveryError::Closed(phase)),
            phase => Err(RecoveryError::InvalidTransition {
                action: "mark restart without terminal readback",
                phase,
            }),
        }
    }
    pub(crate) fn mark_dispatched(&mut self) -> Result<(), RecoveryError> {
        match self.state.phase {
            RecoveryPhase::Claimed => {
                let mut next = self.state.clone();
                next.phase = RecoveryPhase::Dispatched;
                self.persist(next)
            }
            RecoveryPhase::Dispatched => Ok(()),
            phase if phase.is_closed() => Err(RecoveryError::Closed(phase)),
            phase => Err(RecoveryError::InvalidTransition {
                action: "mark dispatched",
                phase,
            }),
        }
    }
    pub(crate) fn mark_terminal(&mut self) -> Result<(), RecoveryError> {
        match self.state.phase {
            RecoveryPhase::Dispatched => self.mark_closed(RecoveryPhase::Terminal, None),
            RecoveryPhase::Terminal => Ok(()),
            phase if phase.is_closed() => Err(RecoveryError::Closed(phase)),
            phase => Err(RecoveryError::InvalidTransition {
                action: "mark terminal",
                phase,
            }),
        }
    }
    pub(crate) fn mark_ambiguous(&mut self, failure_class: &str) -> Result<(), RecoveryError> {
        if failure_class.is_empty() || failure_class.len() > 128 {
            return Err(RecoveryError::InvalidFailureClass);
        }
        self.mark_closed(RecoveryPhase::Ambiguous, Some(failure_class.to_string()))
    }
    fn mark_closed(
        &mut self,
        phase: RecoveryPhase,
        failure_class: Option<String>,
    ) -> Result<(), RecoveryError> {
        if self.state.phase.is_closed() {
            return Err(RecoveryError::Closed(self.state.phase));
        }
        let mut next = self.state.clone();
        next.phase = phase;
        next.failure_class = failure_class;
        self.persist(next)
    }
    fn persist(&mut self, next: RecoveryState) -> Result<(), RecoveryError> {
        let state_dir = self.state_file.parent().ok_or_else(|| {
            RecoveryError::UnsafeStateDirectory("state file has no parent".into())
        })?;
        validate_state_dir(state_dir)?;
        write_state_atomically(state_dir, &self.state_file, &next)?;
        self.state = next;
        Ok(())
    }
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct TerminalEvidenceRecord {
    candidate_event_id: String,
    route: String,
    terminal_events: Vec<serde_json::Value>,
    source_sha256: String,
}

/// Read one bounded, signed terminal record. Missing evidence is normal; every
/// malformed or unauthenticated record is rejected instead of being interpreted.
fn read_terminal_evidence(
    evidence_root: &Path,
    expected_event_id: &str,
    candidate: &TestReadyReceipt,
    contract: &TerminalEvidenceContract,
) -> Result<Option<()>, RecoveryError> {
    if !valid_hex64(expected_event_id) || candidate.event_id != expected_event_id {
        return Err(RecoveryError::InvalidTerminalEvidence("candidate identity"));
    }
    validate_terminal_contract(contract)?;
    let root_metadata = fs::symlink_metadata(evidence_root)?;
    if root_metadata.file_type().is_symlink() || !root_metadata.is_dir() {
        return Err(RecoveryError::UnsafeTerminalEvidence(
            evidence_root.display().to_string(),
        ));
    }
    let path = evidence_root.join(format!("{expected_event_id}.json"));
    let metadata = match fs::symlink_metadata(&path) {
        Ok(metadata) => metadata,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
        Err(error) => return Err(RecoveryError::Io(error)),
    };
    if metadata.file_type().is_symlink() || !metadata.is_file() {
        return Err(RecoveryError::UnsafeTerminalEvidence(
            path.display().to_string(),
        ));
    }
    if metadata.len() > MAX_TERMINAL_EVIDENCE_BYTES {
        return Err(RecoveryError::InvalidTerminalEvidence("record too large"));
    }
    let mut file = File::open(&path)?;
    let mut bytes = Vec::with_capacity(metadata.len() as usize + 1);
    std::io::Read::by_ref(&mut file)
        .take(MAX_TERMINAL_EVIDENCE_BYTES + 1)
        .read_to_end(&mut bytes)?;
    if bytes.len() as u64 > MAX_TERMINAL_EVIDENCE_BYTES {
        return Err(RecoveryError::InvalidTerminalEvidence("record too large"));
    }
    let record: TerminalEvidenceRecord = serde_json::from_slice(&bytes)?;
    if record.candidate_event_id != expected_event_id || !valid_hex64(&record.source_sha256) {
        return Err(RecoveryError::InvalidTerminalEvidence(
            "record identity or hash",
        ));
    }
    let source = canonical_json(&serde_json::json!({
        "candidate_event_id": record.candidate_event_id,
        "route": record.route,
        "terminal_events": record.terminal_events,
    }))?;
    if hex::encode(Sha256::digest(source.as_bytes())) != record.source_sha256 {
        return Err(RecoveryError::InvalidTerminalEvidence("source hash"));
    }
    match record.route.as_str() {
        "claude" if record.terminal_events.len() == 1 => {
            let event = parse_signed_terminal_event(&record.terminal_events[0])?;
            validate_direct_review(&event, candidate, contract)?;
        }
        "robi" if record.terminal_events.len() == 2 => {
            let fallback = parse_signed_terminal_event(&record.terminal_events[0])?;
            let review = parse_signed_terminal_event(&record.terminal_events[1])?;
            if fallback.id == review.id {
                return Err(RecoveryError::InvalidTerminalEvidence(
                    "duplicate terminal event",
                ));
            }
            validate_capacity_fallback(&fallback, candidate, contract)?;
            validate_robi_review(&review, &fallback, candidate, contract)?;
        }
        _ => {
            return Err(RecoveryError::InvalidTerminalEvidence(
                "route or event count",
            ))
        }
    }
    Ok(Some(()))
}

fn validate_terminal_contract(contract: &TerminalEvidenceContract) -> Result<(), RecoveryError> {
    if !valid_hex64(&contract.reviewer_pubkey)
        || !valid_hex64(&contract.robi_pubkey)
        || contract.channel_id.parse::<uuid::Uuid>().is_err()
        || contract.repository != MYBUZZ_REPOSITORY
    {
        return Err(RecoveryError::InvalidTerminalEvidence(
            "configured contract",
        ));
    }
    Ok(())
}

fn parse_signed_terminal_event(value: &serde_json::Value) -> Result<Event, RecoveryError> {
    let object = value
        .as_object()
        .ok_or(RecoveryError::InvalidTerminalEvidence("raw event object"))?;
    let expected: BTreeMap<_, _> = [
        "content",
        "created_at",
        "id",
        "kind",
        "pubkey",
        "sig",
        "tags",
    ]
    .into_iter()
    .map(|key| (key, ()))
    .collect();
    let actual: BTreeMap<_, _> = object.keys().map(|key| (key.as_str(), ())).collect();
    if actual != expected {
        return Err(RecoveryError::InvalidTerminalEvidence("raw event fields"));
    }
    let event: Event = serde_json::from_value(value.clone())?;
    event
        .verify()
        .map_err(|_| RecoveryError::InvalidTerminalEvidence("event signature"))?;
    Ok(event)
}

fn canonical_json(value: &serde_json::Value) -> Result<String, RecoveryError> {
    match value {
        serde_json::Value::Null
        | serde_json::Value::Bool(_)
        | serde_json::Value::Number(_)
        | serde_json::Value::String(_) => serde_json::to_string(value).map_err(RecoveryError::Json),
        serde_json::Value::Array(values) => values
            .iter()
            .map(canonical_json)
            .collect::<Result<Vec<_>, _>>()
            .map(|values| format!("[{}]", values.join(","))),
        serde_json::Value::Object(values) => {
            let mut sorted = BTreeMap::new();
            for (key, value) in values {
                sorted.insert(key, value);
            }
            let mut members = Vec::with_capacity(sorted.len());
            for (key, value) in sorted {
                members.push(format!(
                    "{}:{}",
                    serde_json::to_string(key)?,
                    canonical_json(value)?
                ));
            }
            Ok(format!("{{{}}}", members.join(",")))
        }
    }
}

fn event_tags(event: &Event) -> Vec<Vec<String>> {
    event
        .tags
        .iter()
        .map(|tag| tag.as_slice().to_vec())
        .collect()
}

fn one_tag(tags: &[Vec<String>], expected: &[&str]) -> bool {
    tags.iter()
        .filter(|tag| tag.first().map(String::as_str) == expected.first().copied())
        .count()
        == 1
        && tags
            .iter()
            .any(|tag| tag.iter().map(String::as_str).eq(expected.iter().copied()))
}

fn exact_review_base(
    event: &Event,
    candidate: &TestReadyReceipt,
    contract: &TerminalEvidenceContract,
    author: &str,
    p_recipient: &str,
    allowed_tags: &[&str],
) -> Result<Vec<Vec<String>>, RecoveryError> {
    if event.kind.as_u16() != 1
        || event.pubkey.to_hex() != author
        || event.created_at.as_secs() < candidate.created_at
    {
        return Err(RecoveryError::InvalidTerminalEvidence(
            "event role or order",
        ));
    }
    let tags = event_tags(event);
    if tags
        .iter()
        .any(|tag| tag.is_empty() || !allowed_tags.contains(&tag[0].as_str()))
        || !one_tag(&tags, &["e", &candidate.issue_id, "", "root"])
        || !one_tag(&tags, &["a", &contract.repository])
        || !one_tag(&tags, &["t", "technical-review"])
        || !one_tag(&tags, &["review", &candidate.event_id])
        || !one_tag(&tags, &["h", &contract.channel_id])
        || !one_tag(&tags, &["p", p_recipient])
    {
        return Err(RecoveryError::InvalidTerminalEvidence("review tags"));
    }
    Ok(tags)
}

fn valid_sanity_verdict(value: &str) -> bool {
    if value == "sanity-ok" {
        return true;
    }
    let Some(reason) = value.strip_prefix("sanity-blocked: ") else {
        return false;
    };
    !reason.is_empty()
        && reason.len() <= MAX_SANITY_BLOCK_REASON_BYTES
        && reason == reason.trim()
        && !reason.chars().any(char::is_control)
        && !value.contains(['\n', '\r'])
}

fn validate_direct_review(
    event: &Event,
    candidate: &TestReadyReceipt,
    contract: &TerminalEvidenceContract,
) -> Result<(), RecoveryError> {
    let tags = exact_review_base(
        event,
        candidate,
        contract,
        &contract.reviewer_pubkey,
        &candidate.writer_pubkey,
        &["e", "a", "t", "review", "h", "p"],
    )?;
    if tags.iter().any(|tag| tag[0] == "fallback") || !valid_sanity_verdict(&event.content) {
        return Err(RecoveryError::InvalidTerminalEvidence("direct review"));
    }
    Ok(())
}

fn validate_capacity_fallback(
    event: &Event,
    candidate: &TestReadyReceipt,
    contract: &TerminalEvidenceContract,
) -> Result<(), RecoveryError> {
    let tags = exact_review_base(
        event,
        candidate,
        contract,
        &contract.reviewer_pubkey,
        &contract.robi_pubkey,
        &["e", "a", "t", "review", "h", "p"],
    )?;
    if tags.iter().any(|tag| tag[0] == "fallback")
        || !matches!(
            event.content.as_str(),
            "fallback: capacity-below-10" | "fallback: usage-unknown"
        )
    {
        return Err(RecoveryError::InvalidTerminalEvidence("fallback review"));
    }
    Ok(())
}

fn validate_robi_review(
    event: &Event,
    fallback: &Event,
    candidate: &TestReadyReceipt,
    contract: &TerminalEvidenceContract,
) -> Result<(), RecoveryError> {
    if event.created_at.as_secs() < fallback.created_at.as_secs() {
        return Err(RecoveryError::InvalidTerminalEvidence("fallback order"));
    }
    let tags = exact_review_base(
        event,
        candidate,
        contract,
        &contract.robi_pubkey,
        &candidate.writer_pubkey,
        &["e", "a", "t", "review", "fallback", "h", "p"],
    )?;
    if !one_tag(&tags, &["fallback", &fallback.id.to_hex()])
        || !valid_sanity_verdict(&event.content)
    {
        return Err(RecoveryError::InvalidTerminalEvidence("Robi review"));
    }
    Ok(())
}

/// Builds the fresh, cursor-free exact-ID NIP-01 recovery REQ frame.
pub(crate) fn recovery_subscription_frame(
    event_id: &str,
) -> Result<serde_json::Value, RecoveryError> {
    if !valid_hex64(event_id) {
        return Err(RecoveryError::InvalidEventId);
    }
    Ok(
        serde_json::json!(["REQ", "mybuzz-recovery-v1", {"ids": [event_id], "kinds": [1], "#h": [MYBUZZ_CHANNEL]}]),
    )
}

fn valid_hex64(value: &str) -> bool {
    value.len() == 64
        && value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}
fn validate_state_dir(path: &Path) -> Result<(), RecoveryError> {
    let metadata = fs::symlink_metadata(path)?;
    if metadata.file_type().is_symlink() || !metadata.is_dir() {
        return Err(RecoveryError::UnsafeStateDirectory(
            path.display().to_string(),
        ));
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        if metadata.mode() & 0o777 != 0o700
            || metadata.uid() != nix::unistd::Uid::effective().as_raw()
        {
            return Err(RecoveryError::UnsafeStateDirectory(
                path.display().to_string(),
            ));
        }
    }
    Ok(())
}
fn validate_state_file(metadata: &fs::Metadata) -> Result<(), RecoveryError> {
    if metadata.file_type().is_symlink() || !metadata.is_file() {
        return Err(RecoveryError::UnsafeStateFile("not a regular file".into()));
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        if metadata.mode() & 0o777 != 0o600
            || metadata.uid() != nix::unistd::Uid::effective().as_raw()
        {
            return Err(RecoveryError::UnsafeStateFile(
                "owner or mode mismatch".into(),
            ));
        }
    }
    Ok(())
}
fn write_state_atomically(
    state_dir: &Path,
    state_file: &Path,
    state: &RecoveryState,
) -> Result<(), RecoveryError> {
    let bytes = serde_json::to_vec(state)?;
    let temp_file = state_dir.join(format!(".{STATE_FILE_NAME}.tmp-{}", uuid::Uuid::new_v4()));
    let result = (|| -> Result<(), std::io::Error> {
        let mut file = private_create(&temp_file)?;
        file.write_all(&bytes)?;
        file.sync_all()?;
        fs::rename(&temp_file, state_file)?;
        File::open(state_dir)?.sync_all()?;
        Ok(())
    })();
    if result.is_err() {
        fs::remove_file(&temp_file).ok();
    }
    result.map_err(RecoveryError::Io)
}
fn private_create(path: &Path) -> Result<File, std::io::Error> {
    let mut options = OpenOptions::new();
    options.write(true).create_new(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    options.open(path)
}

#[cfg(test)]
mod tests {
    use std::fs;
    use std::path::PathBuf;

    use nostr::{EventBuilder, Keys, Kind, Tag};

    use super::*;

    const EVENT_ID: &str = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    const OTHER_EVENT_ID: &str = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
    const FINGERPRINT: &str = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc";

    fn secure_state_dir(label: &str) -> PathBuf {
        let path = std::env::temp_dir().join(format!(
            "buzz-acp-recovery-{label}-{}",
            uuid::Uuid::new_v4()
        ));
        fs::create_dir(&path).expect("create state directory");
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(&path, fs::Permissions::from_mode(0o700))
                .expect("restrict state directory");
        }
        path
    }

    fn cleanup(path: PathBuf) {
        fs::remove_dir_all(path).ok();
    }

    fn signed_event(keys: &Keys, content: &str) -> nostr::Event {
        EventBuilder::new(Kind::Custom(1), content)
            .tags([Tag::parse(["h", MYBUZZ_CHANNEL]).expect("tag")])
            .sign_with_keys(keys)
            .expect("sign event")
    }

    #[test]
    fn raw_terminal_event_requires_a_real_nostr_signature() {
        let event = signed_event(&Keys::generate(), "sanity-ok");
        let valid = serde_json::to_value(&event).expect("serialize signed event");
        assert!(parse_signed_terminal_event(&valid).is_ok());

        let mut tampered = valid;
        tampered["content"] = serde_json::json!("sanity-blocked: forged");
        assert!(parse_signed_terminal_event(&tampered).is_err());
    }

    #[test]
    fn sanity_verdict_accepts_ok_and_bounded_blocked_only() {
        assert!(valid_sanity_verdict("sanity-ok"));
        assert!(valid_sanity_verdict("sanity-blocked: build fails"));
        assert!(!valid_sanity_verdict("sanity-blocked: "));
        assert!(!valid_sanity_verdict("sanity-ok\nforged"));
    }

    #[test]
    fn initializes_once_and_keeps_deadline_across_restart() {
        let dir = secure_state_dir("deadline");
        let ledger = RecoveryLedger::open_or_create(&dir, EVENT_ID, FINGERPRINT, 1_000)
            .expect("initialize ledger");
        assert_eq!(ledger.state().deadline_unix_secs, 1_300);
        assert_eq!(ledger.state().attempts_started, 0);
        drop(ledger);

        let reopened = RecoveryLedger::open_or_create(&dir, EVENT_ID, FINGERPRINT, 1_200)
            .expect("reopen ledger");
        assert_eq!(reopened.state().deadline_unix_secs, 1_300);
        assert_eq!(reopened.state().attempts_started, 0);
        cleanup(dir);
    }

    #[test]
    fn start_attempt_persists_before_send_and_exhausts_at_cap() {
        let dir = secure_state_dir("cap");
        let mut ledger = RecoveryLedger::open_or_create(&dir, EVENT_ID, FINGERPRINT, 10)
            .expect("initialize ledger");

        for expected_attempt in 1..=3 {
            assert_eq!(
                ledger.start_attempt(11).expect("attempt"),
                AttemptStart::Started
            );
            assert_eq!(ledger.state().attempts_started, expected_attempt);
        }
        assert_eq!(
            ledger.start_attempt(11).expect("cap result"),
            AttemptStart::Exhausted
        );
        assert_eq!(ledger.state().phase, RecoveryPhase::Exhausted);
        drop(ledger);

        let mut reopened = RecoveryLedger::open_or_create(&dir, EVENT_ID, FINGERPRINT, 12)
            .expect("reopen exhausted ledger");
        assert!(reopened.start_attempt(12).is_err());
        cleanup(dir);
    }

    #[test]
    fn deadline_expiry_is_persisted_without_starting_a_network_attempt() {
        let dir = secure_state_dir("deadline-expiry");
        let mut ledger = RecoveryLedger::open_or_create(&dir, EVENT_ID, FINGERPRINT, 1_000)
            .expect("initialize ledger");

        assert_eq!(
            ledger.start_attempt(1_300).expect("expiry result"),
            AttemptStart::Exhausted
        );
        assert_eq!(ledger.state().attempts_started, 0);
        assert_eq!(ledger.state().phase, RecoveryPhase::Exhausted);
        cleanup(dir);
    }

    #[test]
    fn claim_survives_crash_and_can_be_recorded_as_ambiguous() {
        let dir = secure_state_dir("claim");
        let mut ledger = RecoveryLedger::open_or_create(&dir, EVENT_ID, FINGERPRINT, 10)
            .expect("initialize ledger");
        assert_eq!(ledger.claim().expect("claim"), ClaimResult::Claimed);
        assert_eq!(
            ledger.claim().expect("duplicate claim"),
            ClaimResult::AlreadyClaimed
        );
        drop(ledger);

        let mut reopened = RecoveryLedger::open_or_create(&dir, EVENT_ID, FINGERPRINT, 11)
            .expect("reopen claimed ledger");
        assert_eq!(reopened.state().phase, RecoveryPhase::Claimed);
        reopened
            .mark_ambiguous("crash-after-claim")
            .expect("mark ambiguity");
        assert_eq!(reopened.state().phase, RecoveryPhase::Ambiguous);
        assert_eq!(
            reopened.state().failure_class.as_deref(),
            Some("crash-after-claim")
        );
        assert!(reopened.start_attempt(12).is_err());
        cleanup(dir);
    }

    #[test]
    fn start_attempt_rejects_claimed_and_dispatched_without_incrementing() {
        let claimed_dir = secure_state_dir("claimed-start");
        let mut claimed = RecoveryLedger::open_or_create(&claimed_dir, EVENT_ID, FINGERPRINT, 10)
            .expect("initialize claimed ledger");
        assert_eq!(claimed.claim().expect("claim"), ClaimResult::Claimed);
        assert!(matches!(
            claimed.start_attempt(11),
            Err(RecoveryError::InvalidTransition {
                action: "start attempt",
                phase: RecoveryPhase::Claimed,
            })
        ));
        assert_eq!(claimed.state().attempts_started, 0);
        cleanup(claimed_dir);

        let dispatched_dir = secure_state_dir("dispatched-start");
        let mut dispatched =
            RecoveryLedger::open_or_create(&dispatched_dir, EVENT_ID, FINGERPRINT, 10)
                .expect("initialize dispatched ledger");
        assert_eq!(dispatched.claim().expect("claim"), ClaimResult::Claimed);
        dispatched.mark_dispatched().expect("mark dispatched");
        assert!(matches!(
            dispatched.start_attempt(11),
            Err(RecoveryError::InvalidTransition {
                action: "start attempt",
                phase: RecoveryPhase::Dispatched,
            })
        ));
        assert_eq!(dispatched.state().attempts_started, 0);
        cleanup(dispatched_dir);
    }

    #[test]
    fn restart_of_claimed_or_dispatched_state_becomes_ambiguous_before_retry() {
        for (label, dispatch_before_restart) in
            [("claimed-restart", false), ("dispatched-restart", true)]
        {
            let dir = secure_state_dir(label);
            let mut ledger = RecoveryLedger::open_or_create(&dir, EVENT_ID, FINGERPRINT, 10)
                .expect("initialize ledger");
            assert_eq!(ledger.claim().expect("claim"), ClaimResult::Claimed);
            if dispatch_before_restart {
                ledger.mark_dispatched().expect("mark dispatched");
            }
            drop(ledger);

            let mut reopened = RecoveryLedger::open_or_create(&dir, EVENT_ID, FINGERPRINT, 11)
                .expect("reopen ledger");
            reopened
                .mark_restart_without_terminal_readback()
                .expect("restart must become ambiguous");
            assert_eq!(reopened.state().phase, RecoveryPhase::Ambiguous);
            assert_eq!(
                reopened.state().failure_class.as_deref(),
                Some("restart-without-terminal-readback")
            );
            assert!(reopened.start_attempt(12).is_err());
            cleanup(dir);
        }
    }

    #[test]
    fn terminal_and_dispatched_states_do_not_reopen_automatically() {
        let dir = secure_state_dir("terminal");
        let mut ledger = RecoveryLedger::open_or_create(&dir, EVENT_ID, FINGERPRINT, 10)
            .expect("initialize ledger");
        assert_eq!(ledger.claim().expect("claim"), ClaimResult::Claimed);
        ledger.mark_dispatched().expect("mark dispatched");
        assert_eq!(ledger.state().phase, RecoveryPhase::Dispatched);
        ledger.mark_terminal().expect("mark terminal");
        drop(ledger);

        let mut reopened = RecoveryLedger::open_or_create(&dir, EVENT_ID, FINGERPRINT, 20)
            .expect("reopen terminal ledger");
        assert_eq!(reopened.state().phase, RecoveryPhase::Terminal);
        assert!(reopened.claim().is_err());
        assert!(reopened.start_attempt(20).is_err());
        cleanup(dir);
    }

    #[test]
    fn event_identity_and_malformed_or_symlink_state_are_rejected() {
        let dir = secure_state_dir("identity");
        let ledger = RecoveryLedger::open_or_create(&dir, EVENT_ID, FINGERPRINT, 10)
            .expect("initialize ledger");
        drop(ledger);
        assert!(RecoveryLedger::open_or_create(&dir, OTHER_EVENT_ID, FINGERPRINT, 11).is_err());
        assert!(RecoveryLedger::open_or_create(&dir, "A", FINGERPRINT, 11).is_err());
        cleanup(dir);

        let malformed_dir = secure_state_dir("malformed");
        let malformed_state = malformed_dir.join(STATE_FILE_NAME);
        fs::write(&malformed_state, b"not-json").expect("write malformed state");
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(&malformed_state, fs::Permissions::from_mode(0o600))
                .expect("restrict malformed state");
        }
        assert!(RecoveryLedger::open_or_create(&malformed_dir, EVENT_ID, FINGERPRINT, 10).is_err());
        cleanup(malformed_dir);

        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let wrong_mode_dir = secure_state_dir("wrong-mode");
            fs::set_permissions(&wrong_mode_dir, fs::Permissions::from_mode(0o755))
                .expect("relax state directory");
            assert!(
                RecoveryLedger::open_or_create(&wrong_mode_dir, EVENT_ID, FINGERPRINT, 10).is_err()
            );
            cleanup(wrong_mode_dir);
        }

        #[cfg(unix)]
        {
            let symlink_dir = secure_state_dir("symlink");
            let target = symlink_dir.join("target.json");
            fs::write(&target, b"{}").expect("write symlink target");
            std::os::unix::fs::symlink(&target, symlink_dir.join(STATE_FILE_NAME))
                .expect("create state symlink");
            assert!(
                RecoveryLedger::open_or_create(&symlink_dir, EVENT_ID, FINGERPRINT, 10).is_err()
            );
            cleanup(symlink_dir);
        }
    }

    #[test]
    fn writes_state_atomically_enough_with_private_permissions() {
        let dir = secure_state_dir("permissions");
        let mut ledger = RecoveryLedger::open_or_create(&dir, EVENT_ID, FINGERPRINT, 10)
            .expect("initialize ledger");
        assert_eq!(ledger.claim().expect("claim"), ClaimResult::Claimed);
        let state_path = ledger.state_file().to_path_buf();
        let parsed: RecoveryState =
            serde_json::from_slice(&fs::read(&state_path).expect("read state"))
                .expect("state is complete JSON");
        assert_eq!(parsed.phase, RecoveryPhase::Claimed);
        assert!(
            fs::read_dir(&dir)
                .expect("read state directory")
                .all(|entry| !entry
                    .expect("directory entry")
                    .file_name()
                    .to_string_lossy()
                    .contains(".tmp-")),
            "atomic writes must not leave temporary state files"
        );
        #[cfg(unix)]
        {
            use std::os::unix::fs::MetadataExt;
            assert_eq!(
                fs::metadata(&state_path).expect("state metadata").mode() & 0o777,
                0o600
            );
        }
        cleanup(dir);
    }

    #[test]
    fn terminal_evidence_reader_is_required_before_terminal_transition() {
        let dir = secure_state_dir("terminal-evidence-red");
        let mut ledger = RecoveryLedger::open_or_create(&dir, EVENT_ID, FINGERPRINT, 10)
            .expect("initialize ledger");
        assert_eq!(ledger.claim().expect("claim"), ClaimResult::Claimed);
        ledger.mark_dispatched().expect("dispatch");

        assert!(!ledger
            .try_mark_terminal_from_evidence(&dir)
            .expect("missing evidence is not an error"));
        assert_eq!(ledger.state().phase, RecoveryPhase::Dispatched);
        cleanup(dir);
    }

    #[test]
    fn recovery_subscription_frame_is_exact_and_has_no_cursor_or_recipient_filter() {
        assert_eq!(
            recovery_subscription_frame(EVENT_ID).expect("valid event id"),
            serde_json::json!([
                "REQ",
                "mybuzz-recovery-v1",
                {"ids": [EVENT_ID], "kinds": [1], "#h": [crate::mybuzz_handoff::MYBUZZ_CHANNEL]}
            ])
        );
        assert!(recovery_subscription_frame("A").is_err());
    }
}
