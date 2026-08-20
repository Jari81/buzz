import * as React from "react";

import {
  useContextUsageArchive,
  asTurnMetric,
  type TurnMetricPayload,
} from "@/features/agents/lib/agentContextUsage";
import { resolveContextWindow } from "@/features/agents/lib/modelContextLimits";

/**
 * BUZZ-DESKTOP-003: context usage for ONE channel (the DM ring's data path).
 *
 * kind:44200 payloads carry `channelId`, so per-channel attribution works
 * without agent-pubkey plumbing: in a DM, every metric whose channelId
 * matches the DM belongs to that DM's agent.
 */

export type ChannelContextUsage = {
  model: string | null;
  contextWindow: number;
  lastInputTokens: number | null;
  maxInputTokens: number;
  usageRatio: number | null;
  reportCount: number;
};

const EMPTY: ChannelContextUsage = {
  model: null,
  contextWindow: 0,
  lastInputTokens: null,
  maxInputTokens: 0,
  usageRatio: null,
  reportCount: 0,
};

function asTokenNumber(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value) && value >= 0) {
    return value;
  }
  return null;
}

/** Filter + fold archived metrics to one channel. Pure, exported for tests. */
export function foldChannelTurnMetrics(
  channelId: string,
  rows: readonly unknown[],
): ChannelContextUsage {
  let model: string | null = null;
  let lastInputTokens: number | null = null;
  let maxInputTokens = 0;
  let reportCount = 0;

  for (const raw of rows) {
    const payload: TurnMetricPayload | null = asTurnMetric(raw);
    if (!payload || payload.channelId !== channelId) continue;
    reportCount += 1;

    if (payload.model && model == null) model = payload.model;

    const turnInput = asTokenNumber(payload.turn?.inputTokens);
    if (turnInput != null) {
      if (lastInputTokens == null) lastInputTokens = turnInput;
      if (turnInput > maxInputTokens) maxInputTokens = turnInput;
    }
  }

  if (reportCount === 0) return EMPTY;

  const contextWindow = resolveContextWindow(model, maxInputTokens);
  return {
    model,
    contextWindow,
    lastInputTokens,
    maxInputTokens,
    usageRatio:
      lastInputTokens == null
        ? null
        : Math.min(1, Math.max(0, lastInputTokens / contextWindow)),
    reportCount,
  };
}

/** Context usage for the given channel, or null when there is no data. */
export function useChannelContextUsage(
  channelId: string | null | undefined,
  currentPubkey: string | null | undefined,
): ChannelContextUsage | null {
  const archive = useContextUsageArchive(currentPubkey);

  return React.useMemo(() => {
    if (!channelId || !archive.data || archive.data.length === 0) return null;
    const folded = foldChannelTurnMetrics(channelId, archive.data);
    return folded.reportCount > 0 ? folded : null;
  }, [channelId, archive.data]);
}
