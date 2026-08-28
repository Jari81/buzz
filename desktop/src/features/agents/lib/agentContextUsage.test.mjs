import assert from "node:assert/strict";
import test from "node:test";

import {
  asTurnMetric,
  foldTurnMetrics,
  formatTokenCount,
} from "./agentContextUsage.ts";

function metric(overrides = {}) {
  return {
    harness: "claude-code",
    model: "claude-sonnet-4-20250514",
    channelId: null,
    sessionId: "sess-1",
    turnId: "turn-1",
    turnSeq: 1,
    timestamp: "2026-08-20T18:00:00.000Z",
    turn: {
      inputTokens: 100_000,
      outputTokens: 2_000,
      totalTokens: 102_000,
      costUsd: 0.05,
    },
    cumulative: null,
    deltaReliable: true,
    stopReason: "end_turn",
    ...overrides,
  };
}

test("asTurnMetric accepts payload rows and rejects relay envelopes", () => {
  assert.ok(asTurnMetric(metric()));
  assert.equal(asTurnMetric({ kind: 44200, id: "abc", pubkey: "def" }), null);
  assert.equal(asTurnMetric(null), null);
  assert.equal(asTurnMetric([1, 2]), null);
});

test("foldTurnMetrics takes the newest turn as the fill proxy", () => {
  // Archive rows arrive newest-first.
  const rows = [
    metric({
      turn: {
        inputTokens: 118_000,
        outputTokens: 1,
        totalTokens: 1,
        costUsd: null,
      },
    }),
    metric({
      turn: {
        inputTokens: 90_000,
        outputTokens: 1,
        totalTokens: 1,
        costUsd: null,
      },
    }),
  ];
  const summary = foldTurnMetrics(rows);
  assert.equal(summary.lastInputTokens, 118_000);
  assert.equal(summary.maxInputTokens, 118_000);
  assert.equal(summary.model, "claude-sonnet-4-20250514");
  assert.equal(summary.contextWindow, 200_000);
  assert.ok(Math.abs(summary.usageRatio - 118_000 / 200_000) < 1e-9);
  assert.equal(summary.reportCount, 2);
});

test("foldTurnMetrics sums per-turn costs", () => {
  const rows = [
    metric({
      turn: { inputTokens: 1, outputTokens: 1, totalTokens: 1, costUsd: 0.1 },
    }),
    metric({
      turn: { inputTokens: 1, outputTokens: 1, totalTokens: 1, costUsd: 0.25 },
    }),
  ];
  const summary = foldTurnMetrics(rows);
  assert.ok(Math.abs(summary.totalCostUsd - 0.35) < 1e-9);
});

test("foldTurnMetrics handles missing turn blocks gracefully", () => {
  const rows = [metric({ turn: null }), metric()];
  const summary = foldTurnMetrics(rows);
  assert.equal(summary.lastInputTokens, 100_000);
  assert.equal(summary.reportCount, 2);
});

test("foldTurnMetrics returns null ratio when no token data exists", () => {
  const rows = [metric({ turn: null })];
  const summary = foldTurnMetrics(rows);
  assert.equal(summary.usageRatio, null);
  assert.equal(summary.lastInputTokens, null);
});

test("foldTurnMetrics promotes the window when a turn exceeded it", () => {
  const rows = [
    metric({
      turn: {
        inputTokens: 250_000,
        outputTokens: 1,
        totalTokens: 1,
        costUsd: null,
      },
    }),
  ];
  const summary = foldTurnMetrics(rows);
  assert.equal(summary.contextWindow, 1_048_576);
  assert.ok(Math.abs(summary.usageRatio - 250_000 / 1_048_576) < 1e-9);
});

test("foldTurnMetrics collects distinct session ids newest-first", () => {
  const rows = [
    metric({ sessionId: "s2" }),
    metric({ sessionId: "s1" }),
    metric({ sessionId: "s2" }),
  ];
  const summary = foldTurnMetrics(rows);
  assert.deepEqual(summary.sessionIds, ["s2", "s1"]);
});

test("formatTokenCount renders k and M units", () => {
  assert.equal(formatTokenCount(999), "999");
  assert.equal(formatTokenCount(1_000), "1k");
  assert.equal(formatTokenCount(118_400), "118.4k");
  assert.equal(formatTokenCount(1_048_576), "1.05M");
});
