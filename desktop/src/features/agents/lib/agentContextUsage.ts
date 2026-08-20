import { useQuery } from "@tanstack/react-query";

import { resolveContextWindow } from "@/features/agents/lib/modelContextLimits";
import { readArchivedEvents } from "@/shared/api/tauriArchive";
import { KIND_AGENT_TURN_METRIC } from "@/shared/constants/kinds";
import { useFocusedRefetchInterval } from "@/shared/lib/useDocumentVisible";

/**
 * BUZZ-DESKTOP-003: per-agent context usage derived from archived NIP-AM
 * kind:44200 turn metrics.
 *
 * Archive rows for kind 44200 store the DECRYPTED plaintext payload as
 * `raw_json` (archive pipeline.rs), so `readArchivedEvents` returns payload
 * objects directly — no owner-key handling on this side. The live read
 * surface is the owner_p scope: metrics are p-addressed to the owner.
 *
 * Empirically verified 2026-08-20 against the self-hosted relay: Claude-Host,
 * Claude-Review and Robi publish kind:44200 with model + sessionId +
 * turn.inputTokens. Claude-DEV/Codex-DEV (Coder container) did not publish
 * in the observed window — their harness build may predate the metric
 * publisher or lack the owner context; the ring simply shows no data there.
 */

/** camelCase wire shape of AgentTurnMetricPayload (buzz-core). */
export type TurnMetricPayload = {
  harness: string;
  model: string | null;
  channelId: string | null;
  sessionId: string | null;
  turnId: string | null;
  turnSeq: number | null;
  timestamp: string;
  turn: TokenCounts | null;
  cumulative: TokenCounts | null;
  deltaReliable: boolean;
  stopReason: string | null;
};

/**
 * Token counters cross as JSON numbers (Rust u64 serde). Precision loss is
 * possible above 2^53 but context windows are orders of magnitude below.
 */
export type TokenCounts = {
  inputTokens: number | null;
  outputTokens: number | null;
  totalTokens: number | null;
  costUsd: number | null;
  cacheReadTokens?: number | null;
  cacheWriteTokens?: number | null;
};

export type AgentContextUsage = {
  /** Model reported by the most recent turn metric. */
  model: string | null;
  /** Context window resolved from the limits table + observed-max heuristic. */
  contextWindow: number;
  /** Input tokens of the most recent turn (≈ context fill at that request). */
  lastInputTokens: number | null;
  /** Highest input-token count observed across archived turns. */
  maxInputTokens: number;
  /** lastInputTokens / contextWindow, clamped to [0, 1]. Null when no data. */
  usageRatio: number | null;
  /** Cumulative turn cost across archived turns (USD), null when unreported. */
  totalCostUsd: number | null;
  /** Number of archived turn metrics feeding this summary. */
  reportCount: number;
  /** Distinct session ids observed, newest first. */
  sessionIds: string[];
};

/**
 * Parse one archived row into a payload. readArchivedEvents already
 * JSON-parses raw_json; for kind 44200 rows that IS the payload object
 * (the envelope was replaced by the decrypted payload at ingest).
 */
export function asTurnMetric(raw: unknown): TurnMetricPayload | null {
  if (raw == null || typeof raw !== "object" || Array.isArray(raw)) return null;
  const candidate = raw as Record<string, unknown>;
  // Payloads carry harness + timestamp and lack relay-envelope fields.
  if (typeof candidate.harness !== "string") return null;
  if (typeof candidate.timestamp !== "string") return null;
  return candidate as unknown as TurnMetricPayload;
}

function asTokenNumber(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value) && value >= 0) {
    return value;
  }
  return null;
}

/**
 * Fold archived turn metrics (newest-first) into a context usage summary.
 * Pure function — exported for unit tests.
 */
export function foldTurnMetrics(rows: readonly unknown[]): AgentContextUsage {
  let model: string | null = null;
  let lastInputTokens: number | null = null;
  let maxInputTokens = 0;
  let totalCostUsd: number | null = null;
  let reportCount = 0;
  const seenSessions: string[] = [];

  for (const raw of rows) {
    const payload = asTurnMetric(raw);
    if (!payload) continue;
    reportCount += 1;

    if (payload.model && model == null) model = payload.model;

    if (payload.sessionId && !seenSessions.includes(payload.sessionId)) {
      seenSessions.push(payload.sessionId);
    }

    const turnInput = asTokenNumber(payload.turn?.inputTokens);
    if (turnInput != null) {
      // Rows are newest-first; first seen is the most recent turn.
      if (lastInputTokens == null) lastInputTokens = turnInput;
      if (turnInput > maxInputTokens) maxInputTokens = turnInput;
    }

    const turnCost = payload.turn?.costUsd;
    if (typeof turnCost === "number" && Number.isFinite(turnCost)) {
      totalCostUsd = (totalCostUsd ?? 0) + turnCost;
    }
  }

  const contextWindow = resolveContextWindow(model, maxInputTokens);
  const usageRatio =
    lastInputTokens == null
      ? null
      : Math.min(1, Math.max(0, lastInputTokens / contextWindow));

  return {
    model,
    contextWindow,
    lastInputTokens,
    maxInputTokens,
    usageRatio,
    totalCostUsd,
    reportCount,
    sessionIds: seenSessions,
  };
}

/** Human-readable token count: 118.4k, 1.02M. */
export function formatTokenCount(tokens: number): string {
  if (tokens >= 1_000_000) {
    return `${(tokens / 1_000_000).toFixed(2).replace(/\.?0+$/, "")}M`;
  }
  if (tokens >= 1_000) {
    return `${(tokens / 1_000).toFixed(1).replace(/\.0$/, "")}k`;
  }
  return String(tokens);
}

const METRIC_PAGE_LIMIT = 200;
const EMPTY_ROWS: unknown[] = [];

/**
 * Query archived kind:44200 metrics for the current identity (owner_p scope
 * = the owner's own pubkey). All owner-addressed metrics across the owner's
 * agents land here; consumers slice by sessionId when per-agent attribution
 * matters.
 */
export function useContextUsageArchive(
  currentPubkey: string | null | undefined,
) {
  const refetchInterval = useFocusedRefetchInterval(60_000);
  return useQuery({
    queryKey: ["agent-context-usage-archive", currentPubkey ?? "none"],
    queryFn: () =>
      readArchivedEvents("owner_p", currentPubkey ?? "", {
        kinds: [KIND_AGENT_TURN_METRIC],
        limit: METRIC_PAGE_LIMIT,
      }).catch(() => EMPTY_ROWS),
    enabled: Boolean(currentPubkey),
    refetchInterval,
    staleTime: 30_000,
  });
}
