import assert from "node:assert/strict";
import test from "node:test";

import { foldChannelTurnMetrics } from "./channelContextUsage.ts";

function metric(channelId, overrides = {}) {
  return {
    harness: "claude-code",
    model: "claude-sonnet-4-20250514",
    channelId,
    sessionId: "sess-1",
    turnId: "turn-1",
    turnSeq: 1,
    timestamp: "2026-08-20T18:00:00.000Z",
    turn: {
      inputTokens: 60_000,
      outputTokens: 500,
      totalTokens: 60_500,
      costUsd: null,
    },
    cumulative: null,
    deltaReliable: true,
    stopReason: "end_turn",
    ...overrides,
  };
}

test("foldChannelTurnMetrics scopes a thread and retains legacy fallback", () => {
  const rows = [
    metric("group-uuid", {
      threadRoot: "thread-a",
      turn: {
        inputTokens: 80_000,
        outputTokens: 1,
        totalTokens: 1,
        costUsd: null,
      },
    }),
    metric("group-uuid", {
      threadRoot: "thread-b",
      turn: {
        inputTokens: 20_000,
        outputTokens: 1,
        totalTokens: 1,
        costUsd: null,
      },
    }),
    metric("group-uuid", {
      turn: {
        inputTokens: 40_000,
        outputTokens: 1,
        totalTokens: 1,
        costUsd: null,
      },
    }),
  ];

  const usage = foldChannelTurnMetrics("group-uuid", rows, "thread-a");
  assert.equal(usage.reportCount, 2);
  assert.equal(usage.lastInputTokens, 80_000);
});

test("foldChannelTurnMetrics attributes metrics by channelId", () => {
  const rows = [
    metric("dm-uuid", {
      turn: {
        inputTokens: 80_000,
        outputTokens: 1,
        totalTokens: 1,
        costUsd: null,
      },
    }),
    metric("other-channel"),
    metric("dm-uuid", {
      turn: {
        inputTokens: 40_000,
        outputTokens: 1,
        totalTokens: 1,
        costUsd: null,
      },
    }),
  ];
  const usage = foldChannelTurnMetrics("dm-uuid", rows);
  assert.equal(usage.reportCount, 2);
  // Newest-first: 80k is the latest turn for dm-uuid.
  assert.equal(usage.lastInputTokens, 80_000);
  assert.equal(usage.usageRatio != null && usage.usageRatio > 0, true);
});

test("foldChannelTurnMetrics returns zero counts for a channel with no data", () => {
  const usage = foldChannelTurnMetrics("dm-uuid", [metric("elsewhere")]);
  assert.equal(usage.reportCount, 0);
  assert.equal(usage.usageRatio, null);
});

test("foldChannelTurnMetrics ignores malformed rows", () => {
  const usage = foldChannelTurnMetrics("dm-uuid", [
    { kind: 44200, id: "envelope" },
    metric("dm-uuid"),
  ]);
  assert.equal(usage.reportCount, 1);
});
