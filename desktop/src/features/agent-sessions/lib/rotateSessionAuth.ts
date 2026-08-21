import { normalizePubkey } from "@/shared/lib/pubkey";

type RelayAgentDirectoryRow = {
  pubkey: string;
  respondToAllowlist: string[];
};

/**
 * Rotation gate for the Agent Sessions panel Reset button.
 *
 * `!rotate` is enforced owner-side by buzz-acp: a rotate command from a
 * non-owner falls through to normal prompt handling, it is never an
 * authority bypass. The button therefore stays honest about who can
 * actually rotate: it is enabled when the current identity appears in the
 * agent's respond-to allowlist (owner + allowlisted siblings).
 *
 * Agents without a relay directory record (local managed agents) stay
 * ungated here — the harness author check remains the authority and the
 * button simply attempts the send, which fails closed at the harness.
 *
 * No current identity -> deny (nothing can be attributed).
 */
export function isRotateSessionAuthorized(
  relayAgents: readonly RelayAgentDirectoryRow[] | undefined,
  currentPubkey: string | null,
  agentPubkey: string,
): boolean {
  if (!currentPubkey) return false;
  const agent = (relayAgents ?? []).find(
    (candidate) =>
      normalizePubkey(candidate.pubkey) === normalizePubkey(agentPubkey),
  );
  if (!agent) return true;
  return agent.respondToAllowlist
    .map((pubkey) => normalizePubkey(pubkey))
    .includes(normalizePubkey(currentPubkey));
}
