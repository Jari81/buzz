//! Conversation scoping for buzz-acp.
//!
//! A **conversation** is the unit that owns an ACP session, a turn counter, a
//! delivery ledger, a queue, and the mid-turn steer/cancel path. It is *not*
//! the channel:
//!
//! - **DM channel** — exactly one conversation, replies included. A DM is
//!   already a two-party thread; splitting it per NIP-10 root would fragment a
//!   single human conversation across sessions.
//! - **Group channel, top-level event** — the event's own id is the stable
//!   conversation root.
//! - **Group channel, reply** — the NIP-10 `root` event id is the stable
//!   conversation root, so every reply under a root reuses that root's session.
//!
//! Two threads in the same group channel therefore never share an ACP session,
//! turn counter, delivery ledger, cancelled batch, retry state, or in-flight
//! control path.
//!
//! Membership removal and agent teardown stay channel-wide and iterate every
//! conversation scope belonging to the channel. Owner `!cancel` / `!rotate`
//! commands intentionally target only the conversation where they were posted.
//! Channel metadata, canvas, and core-memory caches remain channel-keyed —
//! those are properties of the channel, not of a thread.

use std::fmt;

use nostr::Event;
use uuid::Uuid;

/// Stable identity of one agent conversation.
///
/// Hashable and ordered so it can key every per-conversation map in
/// [`EventQueue`](crate::queue::EventQueue) and
/// [`SessionState`](crate::pool::SessionState).
#[derive(Clone, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct ConversationScope {
    /// The Buzz channel this conversation lives in. Always meaningful — every
    /// relay call, observer frame, CLI hint, and channel-scoped cache keys off
    /// this. Read it with [`channel_id`](Self::channel_id).
    channel_id: Uuid,
    /// `None` for DM channels (one conversation per DM channel).
    /// `Some(root_event_id)` for group channels, lowercase hex.
    thread_root: Option<String>,
}

impl ConversationScope {
    /// The single conversation of a DM channel.
    pub fn dm(channel_id: Uuid) -> Self {
        Self {
            channel_id,
            thread_root: None,
        }
    }

    /// The conversation rooted at `root_event_id` inside a group channel.
    pub fn thread(channel_id: Uuid, root_event_id: impl AsRef<str>) -> Self {
        Self {
            channel_id,
            thread_root: Some(root_event_id.as_ref().trim().to_ascii_lowercase()),
        }
    }

    /// Derive the scope an inbound event belongs to.
    ///
    /// `is_dm` must come from definitive channel metadata. Unknown channel
    /// types are rejected by the routing layer before this constructor is
    /// called; authorization may independently treat unknown as DM fail-closed.
    pub fn for_event(channel_id: Uuid, is_dm: bool, event: &Event) -> Self {
        if is_dm {
            return Self::dm(channel_id);
        }
        match crate::queue::parse_thread_tags(event).root_event_id {
            Some(root) => Self::thread(channel_id, root),
            None => Self::thread(channel_id, event.id.to_hex()),
        }
    }

    /// The Buzz channel this conversation lives in.
    ///
    /// Channel-wide concerns — channel metadata, canvas, core memory, observer
    /// and metric frames, relay calls — key off this, never off the scope.
    pub fn channel_id(&self) -> Uuid {
        self.channel_id
    }

    /// The thread root for group conversations; `None` for DM conversations.
    pub fn thread_root(&self) -> Option<&str> {
        self.thread_root.as_deref()
    }
}

impl fmt::Display for ConversationScope {
    /// `<channel-uuid>` for a DM, `<channel-uuid>#<root-prefix>` for a thread —
    /// short enough to read in a log line, unique enough to correlate turns.
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match &self.thread_root {
            Some(root) => {
                let prefix: String = root.chars().take(12).collect();
                write!(f, "{}#{prefix}", self.channel_id)
            }
            None => write!(f, "{}", self.channel_id),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use nostr::{EventBuilder, Keys, Kind, Tag};

    fn top_level(content: &str) -> Event {
        EventBuilder::new(Kind::Custom(9), content)
            .tags([])
            .sign_with_keys(&Keys::generate())
            .unwrap()
    }

    fn root_only(root_id: &str, content: &str) -> Event {
        EventBuilder::new(Kind::Custom(9), content)
            .tags([Tag::parse(["e", root_id, "", "root"]).unwrap()])
            .sign_with_keys(&Keys::generate())
            .unwrap()
    }

    fn direct_reply(parent_id: &str, content: &str) -> Event {
        EventBuilder::new(Kind::Custom(9), content)
            .tags([Tag::parse(["e", parent_id, "", "reply"]).unwrap()])
            .sign_with_keys(&Keys::generate())
            .unwrap()
    }

    fn deep_reply(root_id: &str, parent_id: &str, content: &str) -> Event {
        EventBuilder::new(Kind::Custom(9), content)
            .tags([
                Tag::parse(["e", root_id, "", "root"]).unwrap(),
                Tag::parse(["e", parent_id, "", "reply"]).unwrap(),
            ])
            .sign_with_keys(&Keys::generate())
            .unwrap()
    }

    #[test]
    fn two_group_top_level_events_in_one_channel_are_separate_scopes() {
        let ch = Uuid::new_v4();
        let a = top_level("thread A");
        let b = top_level("thread B");

        let scope_a = ConversationScope::for_event(ch, false, &a);
        let scope_b = ConversationScope::for_event(ch, false, &b);

        assert_ne!(scope_a, scope_b);
        assert_eq!(scope_a.channel_id(), ch);
        assert_eq!(scope_b.channel_id(), ch);
        assert_eq!(scope_a.thread_root(), Some(a.id.to_hex().as_str()));
    }

    #[test]
    fn a_group_reply_reuses_its_roots_scope() {
        let ch = Uuid::new_v4();
        let root = top_level("thread A");
        let root_scope = ConversationScope::for_event(ch, false, &root);

        let reply = direct_reply(&root.id.to_hex(), "reply one");
        let deep_reply = deep_reply(&root.id.to_hex(), &reply.id.to_hex(), "reply two");

        assert_eq!(ConversationScope::for_event(ch, false, &reply), root_scope);
        assert_eq!(
            ConversationScope::for_event(ch, false, &deep_reply),
            root_scope
        );
    }

    #[test]
    fn a_root_only_event_is_top_level_like_relay_ingestion() {
        let ch = Uuid::new_v4();
        let unrelated = top_level("unrelated root");
        let event = root_only(&unrelated.id.to_hex(), "accepted as top-level");

        assert_eq!(
            ConversationScope::for_event(ch, false, &event),
            ConversationScope::thread(ch, event.id.to_hex())
        );
    }

    #[test]
    fn malformed_and_invalid_trailing_ids_match_relay_ingestion() {
        let ch = Uuid::new_v4();
        let root = top_level("root");
        let parent = direct_reply(&root.id.to_hex(), "parent");
        let root_id = root.id.to_hex();
        let parent_id = parent.id.to_hex();
        let malformed = EventBuilder::new(Kind::Custom(9), "deep")
            .tags([
                Tag::parse(["e", root_id.as_str(), "", "root"]).unwrap(),
                Tag::parse(["e", "not-hex", "", "root"]).unwrap(),
                Tag::parse(["e", parent_id.as_str(), "", "reply"]).unwrap(),
            ])
            .sign_with_keys(&Keys::generate())
            .unwrap();

        assert_eq!(
            ConversationScope::for_event(ch, false, &malformed),
            ConversationScope::thread(ch, root.id.to_hex()),
            "relay ignores the invalid trailing root and retains the last valid root"
        );

        let invalid_reply_id = "f".repeat(63);
        let invalid_reply = EventBuilder::new(Kind::Custom(9), "top-level")
            .tags([Tag::parse(["e", invalid_reply_id.as_str(), "", "reply"]).unwrap()])
            .sign_with_keys(&Keys::generate())
            .unwrap();
        assert_eq!(
            ConversationScope::for_event(ch, false, &invalid_reply),
            ConversationScope::thread(ch, invalid_reply.id.to_hex())
        );
    }

    #[test]
    fn a_direct_reply_without_a_root_marker_uses_the_parent_as_root() {
        // NIP-10: a direct reply to the root carries only a `reply` marker.
        let ch = Uuid::new_v4();
        let root = top_level("thread A");
        let root_scope = ConversationScope::for_event(ch, false, &root);

        let reply = direct_reply(&root.id.to_hex(), "direct reply");
        assert_eq!(ConversationScope::for_event(ch, false, &reply), root_scope);
    }

    #[test]
    fn dm_top_level_and_replies_share_the_channel_scope() {
        let ch = Uuid::new_v4();
        let first = top_level("hi");
        let reply = direct_reply(&first.id.to_hex(), "hi back");

        let a = ConversationScope::for_event(ch, true, &first);
        let b = ConversationScope::for_event(ch, true, &reply);

        assert_eq!(a, b, "a DM channel is one conversation, replies included");
        assert_eq!(a, ConversationScope::dm(ch));
        assert_eq!(a.thread_root(), None);
    }

    #[test]
    fn the_same_root_in_two_channels_is_two_scopes() {
        let root = top_level("cross-posted");
        let a = ConversationScope::for_event(Uuid::new_v4(), false, &root);
        let b = ConversationScope::for_event(Uuid::new_v4(), false, &root);
        assert_ne!(a, b);
    }

    #[test]
    fn display_never_panics_on_a_public_non_ascii_thread_root() {
        let scope = ConversationScope::thread(Uuid::new_v4(), "a€€€€thread-root");
        let rendered = scope.to_string();
        assert!(rendered.contains("#a"));
    }

    #[test]
    fn thread_roots_are_case_normalized() {
        let ch = Uuid::new_v4();
        let root = top_level("thread A");
        let upper = root.id.to_hex().to_ascii_uppercase();
        assert_eq!(
            ConversationScope::thread(ch, upper),
            ConversationScope::for_event(ch, false, &root)
        );
    }
}
