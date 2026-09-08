//! Owner-authored global role-prompt payload contract.
//!
//! The signed NIP-33 envelope identifies its role through the `d` tag; this
//! module validates and builds the corresponding non-secret JSON body. Secret
//! configuration belongs in encrypted private managed-agent records, never here.

use std::str::FromStr;

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use thiserror::Error;

/// Current role-prompt payload schema version.
pub const ROLE_PROMPT_VERSION: u32 = 1;

/// The only stable role coordinates supported by the global role-prompt registry.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum RolePromptRole {
    /// Implementation-focused writer prompt.
    Writer,
    /// Independent review prompt.
    Review,
    /// Host-operations prompt.
    Host,
}

impl RolePromptRole {
    /// Return the stable NIP-33 `d`-tag coordinate for this role.
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Writer => "writer",
            Self::Review => "review",
            Self::Host => "host",
        }
    }
}

impl FromStr for RolePromptRole {
    type Err = RolePromptError;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        match value {
            "writer" => Ok(Self::Writer),
            "review" => Ok(Self::Review),
            "host" => Ok(Self::Host),
            _ => Err(RolePromptError::UnsupportedRole),
        }
    }
}

/// Strict, public-safe role-prompt payload.
///
/// The structure intentionally has no extension map: accepting unrecognized
/// fields could let secret configuration appear in globally readable events.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RolePromptPayload {
    /// Payload schema version, currently [`ROLE_PROMPT_VERSION`].
    pub v: u32,
    /// Role duplicated from the signed `d` tag for reader-side consistency checks.
    pub role: RolePromptRole,
    /// Positive, owner-controlled prompt revision.
    pub revision: u64,
    /// Exact UTF-8 prompt bytes covered by [`Self::sha256`].
    pub prompt: String,
    /// Lowercase SHA-256 digest of the exact [`Self::prompt`] UTF-8 bytes.
    pub sha256: String,
}

/// Errors returned when a role-prompt payload is malformed or inconsistent.
#[derive(Debug, Error, PartialEq, Eq)]
pub enum RolePromptError {
    /// The role identifier is not one of writer, review, or host.
    #[error("role must be one of writer, review, or host")]
    UnsupportedRole,
    /// The payload is not strict version-one JSON.
    #[error("role-prompt payload must be strict JSON: {0}")]
    InvalidJson(String),
    /// The schema version is not supported.
    #[error("role-prompt payload v must be {ROLE_PROMPT_VERSION}")]
    UnsupportedVersion,
    /// Revisions begin at one so zero is never a valid head.
    #[error("role-prompt payload revision must be positive")]
    NonPositiveRevision,
    /// A role prompt must contain actual prompt text.
    #[error("role-prompt payload prompt must not be empty")]
    EmptyPrompt,
    /// The supplied payload role did not duplicate the signed coordinate.
    #[error("role-prompt payload role must match the d tag")]
    RoleMismatch,
    /// The supplied digest is not canonical lowercase SHA-256 text.
    #[error("role-prompt payload sha256 must be 64 lowercase hexadecimal characters")]
    InvalidSha256,
    /// The supplied digest does not cover the exact prompt bytes.
    #[error("role-prompt payload sha256 must match the exact prompt")]
    Sha256Mismatch,
    /// Canonical JSON serialization unexpectedly failed.
    #[error("role-prompt payload serialization failed: {0}")]
    Serialization(String),
}

impl RolePromptPayload {
    /// Create a canonical version-one payload and calculate its prompt digest.
    pub fn new(
        role: RolePromptRole,
        revision: u64,
        prompt: impl Into<String>,
    ) -> Result<Self, RolePromptError> {
        let prompt = prompt.into();
        if revision == 0 {
            return Err(RolePromptError::NonPositiveRevision);
        }
        if prompt.is_empty() {
            return Err(RolePromptError::EmptyPrompt);
        }
        Ok(Self {
            v: ROLE_PROMPT_VERSION,
            role,
            revision,
            sha256: prompt_sha256(&prompt),
            prompt,
        })
    }

    /// Parse and validate a strict payload for the signed `d`-tag role.
    pub fn parse_for_role(content: &str, role: RolePromptRole) -> Result<Self, RolePromptError> {
        let payload: Self = serde_json::from_str(content)
            .map_err(|error| RolePromptError::InvalidJson(error.to_string()))?;
        if payload.v != ROLE_PROMPT_VERSION {
            return Err(RolePromptError::UnsupportedVersion);
        }
        if payload.role != role {
            return Err(RolePromptError::RoleMismatch);
        }
        if payload.revision == 0 {
            return Err(RolePromptError::NonPositiveRevision);
        }
        if payload.prompt.is_empty() {
            return Err(RolePromptError::EmptyPrompt);
        }
        if !is_lowercase_sha256(&payload.sha256) {
            return Err(RolePromptError::InvalidSha256);
        }
        if payload.sha256 != prompt_sha256(&payload.prompt) {
            return Err(RolePromptError::Sha256Mismatch);
        }
        Ok(payload)
    }

    /// Serialize this already-validated payload to compact canonical field order.
    pub fn to_json(&self) -> Result<String, RolePromptError> {
        serde_json::to_string(self)
            .map_err(|error| RolePromptError::Serialization(error.to_string()))
    }
}

/// Return the lowercase SHA-256 of exact UTF-8 prompt bytes.
pub fn prompt_sha256(prompt: &str) -> String {
    hex::encode(Sha256::digest(prompt.as_bytes()))
}

fn is_lowercase_sha256(value: &str) -> bool {
    value.len() == 64
        && value.bytes().all(|byte| {
            byte.is_ascii_digit() || (byte.is_ascii_lowercase() && byte.is_ascii_hexdigit())
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn payload_round_trips_for_each_supported_role() {
        for role in [
            RolePromptRole::Writer,
            RolePromptRole::Review,
            RolePromptRole::Host,
        ] {
            let payload = RolePromptPayload::new(role, 1, "Public role instructions.").unwrap();
            let parsed =
                RolePromptPayload::parse_for_role(&payload.to_json().unwrap(), role).unwrap();
            assert_eq!(parsed, payload);
        }
    }

    #[test]
    fn payload_rejects_extra_json_fields() {
        let content = r#"{"v":1,"role":"writer","revision":1,"prompt":"Public","sha256":"a91a505360e3b0464eae9c9e5f5900988651e3a313b6cd8d7b37639e6a58a2f6","secret":"no"}"#;
        assert!(matches!(
            RolePromptPayload::parse_for_role(content, RolePromptRole::Writer),
            Err(RolePromptError::InvalidJson(_))
        ));
    }

    #[test]
    fn payload_rejects_duplicate_json_fields() {
        let content = r#"{"v":1,"v":1,"role":"writer","revision":1,"prompt":"Public","sha256":"a91a505360e3b0464eae9c9e5f5900988651e3a313b6cd8d7b37639e6a58a2f6"}"#;
        assert!(matches!(
            RolePromptPayload::parse_for_role(content, RolePromptRole::Writer),
            Err(RolePromptError::InvalidJson(_))
        ));
    }

    #[test]
    fn payload_rejects_noncanonical_or_mismatched_digests() {
        let payload = RolePromptPayload::new(RolePromptRole::Host, 1, "Public").unwrap();
        let uppercase = payload.sha256.to_ascii_uppercase();
        let noncanonical = format!(
            r#"{{"v":1,"role":"host","revision":1,"prompt":"Public","sha256":"{uppercase}"}}"#
        );
        assert_eq!(
            RolePromptPayload::parse_for_role(&noncanonical, RolePromptRole::Host),
            Err(RolePromptError::InvalidSha256)
        );

        let mismatched = r#"{"v":1,"role":"host","revision":1,"prompt":"Public","sha256":"0000000000000000000000000000000000000000000000000000000000000000"}"#;
        assert_eq!(
            RolePromptPayload::parse_for_role(mismatched, RolePromptRole::Host),
            Err(RolePromptError::Sha256Mismatch)
        );
    }

    #[test]
    fn payload_requires_version_one_and_a_positive_revision() {
        assert_eq!(
            RolePromptPayload::new(RolePromptRole::Writer, 0, "Public"),
            Err(RolePromptError::NonPositiveRevision)
        );

        let mut payload = RolePromptPayload::new(RolePromptRole::Writer, 1, "Public").unwrap();
        payload.v = 2;
        assert_eq!(
            RolePromptPayload::parse_for_role(&payload.to_json().unwrap(), RolePromptRole::Writer),
            Err(RolePromptError::UnsupportedVersion)
        );

        payload.v = ROLE_PROMPT_VERSION;
        payload.revision = 0;
        assert_eq!(
            RolePromptPayload::parse_for_role(&payload.to_json().unwrap(), RolePromptRole::Writer),
            Err(RolePromptError::NonPositiveRevision)
        );
    }
}
