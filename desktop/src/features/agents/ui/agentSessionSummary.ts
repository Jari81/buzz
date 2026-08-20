import { compareObserverEvents } from "@/features/agents/observerRelayStore";
import type { ObserverEvent } from "./agentSessionTypes";

export type AgentSessionStatus = "running" | "completed" | "error";

export type AgentSessionSummary = {
  sessionId: string;
  channelId: string | null;
  turnCount: number;
  firstTimestamp: string;
  lastTimestamp: string;
  status: AgentSessionStatus;
};

/**
 * Group one agent's observer events by `sessionId` into per-session
 * summaries for the session tree (turn count, span, last-known status),
 * newest-activity-first.
 *
 * Pure function: the caller owns merging live + archive event windows
 * before calling this, same contract as `buildTranscriptState`. Events with
 * no `sessionId` (rare pre-session-resolution frames) are skipped — they
 * have nothing to group by.
 *
 * "Last-known status" is a heuristic over the last event observed for the
 * session in `compareObserverEvents` order (timestamp, then seq on a tie —
 * reused rather than re-implemented to avoid drifting from transcript
 * ordering): `turn_error`/`agent_panic` mark the session errored,
 * `turn_completed` marks it completed, anything else leaves it "running".
 * A session can go error -> running again if a later turn starts in the
 * same session after an earlier turn's error; that reflects reality (the
 * agent kept going), not a bug.
 */
export function deriveAgentSessions(
  events: readonly ObserverEvent[],
): AgentSessionSummary[] {
  const bySession = new Map<
    string,
    {
      channelId: string | null;
      turnIds: Set<string>;
      firstEvent: ObserverEvent;
      lastEvent: ObserverEvent;
      status: AgentSessionStatus;
    }
  >();

  for (const event of events) {
    const sessionId = event.sessionId;
    if (!sessionId) continue;

    let entry = bySession.get(sessionId);
    if (!entry) {
      entry = {
        channelId: event.channelId,
        turnIds: new Set(),
        firstEvent: event,
        lastEvent: event,
        status: "running",
      };
      bySession.set(sessionId, entry);
    }

    if (event.channelId && !entry.channelId) {
      entry.channelId = event.channelId;
    }
    if (event.turnId) {
      entry.turnIds.add(event.turnId);
    }
    if (compareObserverEvents(event, entry.firstEvent) < 0) {
      entry.firstEvent = event;
    }
    if (compareObserverEvents(event, entry.lastEvent) >= 0) {
      entry.lastEvent = event;
      entry.status = statusForEventKind(event.kind);
    }
  }

  return Array.from(bySession.values())
    .sort((a, b) => compareObserverEvents(b.lastEvent, a.lastEvent))
    .map((entry) => ({
      sessionId: entry.lastEvent.sessionId as string,
      channelId: entry.channelId,
      turnCount: entry.turnIds.size,
      firstTimestamp: entry.firstEvent.timestamp,
      lastTimestamp: entry.lastEvent.timestamp,
      status: entry.status,
    }));
}

function statusForEventKind(kind: string): AgentSessionStatus {
  if (kind === "turn_error" || kind === "agent_panic") return "error";
  if (kind === "turn_completed") return "completed";
  return "running";
}
