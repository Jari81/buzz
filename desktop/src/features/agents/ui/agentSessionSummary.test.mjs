import assert from "node:assert/strict";
import test from "node:test";

import { deriveAgentSessions } from "./agentSessionSummary.ts";

function event(overrides) {
  return {
    seq: 0,
    timestamp: "2026-08-20T08:00:00.000Z",
    kind: "acp_read",
    agentIndex: 0,
    channelId: "chan-1",
    sessionId: "sess-1",
    turnId: null,
    payload: {},
    ...overrides,
  };
}

test("groups events by sessionId and counts distinct turns", () => {
  const sessions = deriveAgentSessions([
    event({ seq: 1, turnId: "turn-1" }),
    event({ seq: 2, turnId: "turn-1" }),
    event({ seq: 3, turnId: "turn-2" }),
  ]);

  assert.equal(sessions.length, 1);
  assert.equal(sessions[0].sessionId, "sess-1");
  assert.equal(sessions[0].turnCount, 2);
});

test("skips events with no sessionId", () => {
  const sessions = deriveAgentSessions([
    event({ seq: 1, sessionId: null }),
    event({ seq: 2, sessionId: "sess-1" }),
  ]);

  assert.equal(sessions.length, 1);
  assert.equal(sessions[0].sessionId, "sess-1");
});

test("orders sessions newest-last-activity first, using seq as tiebreak on equal timestamps", () => {
  const sessions = deriveAgentSessions([
    event({
      seq: 1,
      sessionId: "sess-old",
      timestamp: "2026-08-20T08:00:00.000Z",
    }),
    event({
      seq: 2,
      sessionId: "sess-new",
      timestamp: "2026-08-20T08:00:00.000Z",
    }),
  ]);

  assert.deepEqual(
    sessions.map((s) => s.sessionId),
    ["sess-new", "sess-old"],
  );
});

test("marks a session errored when its last event is turn_error", () => {
  const sessions = deriveAgentSessions([
    event({ seq: 1, kind: "turn_started" }),
    event({ seq: 2, kind: "turn_error" }),
  ]);

  assert.equal(sessions[0].status, "error");
});

test("marks a session errored on agent_panic", () => {
  const sessions = deriveAgentSessions([
    event({ seq: 1, kind: "turn_started" }),
    event({ seq: 2, kind: "agent_panic" }),
  ]);

  assert.equal(sessions[0].status, "error");
});

test("marks a session completed when its last event is turn_completed", () => {
  const sessions = deriveAgentSessions([
    event({ seq: 1, kind: "turn_started" }),
    event({ seq: 2, kind: "turn_completed" }),
  ]);

  assert.equal(sessions[0].status, "completed");
});

test("a later turn_started after an earlier error moves the session back to running", () => {
  const sessions = deriveAgentSessions([
    event({ seq: 1, kind: "turn_error" }),
    event({ seq: 2, kind: "turn_started" }),
  ]);

  assert.equal(sessions[0].status, "running");
});

test("keeps the earliest channelId seen when later events omit it", () => {
  const sessions = deriveAgentSessions([
    event({ seq: 1, channelId: "chan-1" }),
    event({ seq: 2, channelId: null }),
  ]);

  assert.equal(sessions[0].channelId, "chan-1");
});

test("first/last timestamp span the full session regardless of input order", () => {
  const sessions = deriveAgentSessions([
    event({ seq: 2, timestamp: "2026-08-20T08:05:00.000Z" }),
    event({ seq: 1, timestamp: "2026-08-20T08:00:00.000Z" }),
  ]);

  assert.equal(sessions[0].firstTimestamp, "2026-08-20T08:00:00.000Z");
  assert.equal(sessions[0].lastTimestamp, "2026-08-20T08:05:00.000Z");
});

test("keeps distinct sessions separate across different channels", () => {
  const sessions = deriveAgentSessions([
    event({ seq: 1, sessionId: "sess-a", channelId: "chan-a" }),
    event({ seq: 2, sessionId: "sess-b", channelId: "chan-b" }),
  ]);

  assert.equal(sessions.length, 2);
  const byId = Object.fromEntries(sessions.map((s) => [s.sessionId, s]));
  assert.equal(byId["sess-a"].channelId, "chan-a");
  assert.equal(byId["sess-b"].channelId, "chan-b");
});
