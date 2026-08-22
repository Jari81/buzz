/**
 * Local kill list for the Agent Sessions panel.
 *
 * "Kill" removes a session from the panel's list on this device: the
 * session id is recorded per identity in localStorage and filtered out of
 * every derived session tree. Observer frames are immutable relay data —
 * they cannot be deleted — so kill is a display-level removal, not a relay
 * mutation. A running agent turn is not interrupted by kill; `!rotate`
 * (the Reset button) is the path that cancels in-flight work.
 *
 * Identity-scoped key, same convention as observerArchivePreference.ts:
 * killing on one identity must not hide sessions on another.
 */

const KEY_PREFIX = "buzz:killed-agent-sessions";

function storageKey(identityPubkey: string): string {
  return `${KEY_PREFIX}:${identityPubkey}`;
}

export function readKilledAgentSessions(
  identityPubkey: string | null,
): Set<string> {
  if (!identityPubkey || typeof window === "undefined") return new Set();
  try {
    const raw = window.localStorage.getItem(storageKey(identityPubkey));
    if (!raw) return new Set();
    const parsed: unknown = JSON.parse(raw);
    if (!Array.isArray(parsed)) return new Set();
    return new Set(
      parsed.filter((entry): entry is string => typeof entry === "string"),
    );
  } catch {
    // Corrupt or unavailable storage reads as "nothing killed" — the panel
    // keeps showing every session rather than hiding unknown ones.
    return new Set();
  }
}

export function recordKilledAgentSession(
  identityPubkey: string | null,
  sessionId: string,
): void {
  if (!identityPubkey || typeof window === "undefined") return;
  try {
    const killed = readKilledAgentSessions(identityPubkey);
    killed.add(sessionId);
    window.localStorage.setItem(
      storageKey(identityPubkey),
      JSON.stringify([...killed]),
    );
  } catch {
    // Best-effort persistence: the in-memory kill state in the panel still
    // hides the session for the rest of this run.
  }
}
