import type * as React from "react";

import { useChannelContextUsage } from "@/features/agents/lib/channelContextUsage";
import {
  ContextUsageRing,
  formatTokenCount,
} from "@/features/messages/ui/ContextUsageRing";

function renderContextRing(
  usage: NonNullable<ReturnType<typeof useChannelContextUsage>>,
) {
  const { usageRatio, model, lastInputTokens, contextWindow } = usage;
  const pct = usageRatio == null ? null : Math.round(usageRatio * 100);
  const label = [
    model ?? "unknown model",
    pct == null ? "no usage data" : `${pct}% context used`,
    lastInputTokens != null && contextWindow > 0
      ? `${formatTokenCount(lastInputTokens)}/${formatTokenCount(contextWindow)} tokens`
      : null,
  ]
    .filter(Boolean)
    .join(" · ");

  return (
    <span className="inline-flex items-center px-1" title={label}>
      <ContextUsageRing label={label} ratio={usageRatio} />
    </span>
  );
}

/**
 * Fold owner-wide metric history into independent composer accessories. DMs are
 * channel-scoped; group threads are scoped by their root while retaining the
 * root-less legacy fallback in `useChannelContextUsage`.
 */
export function useChannelContextRings({
  channelId,
  currentPubkey,
  isDmChannel,
  threadRoot,
}: {
  channelId: string | null;
  currentPubkey: string | null | undefined;
  isDmChannel: boolean;
  threadRoot: string | null;
}) {
  const dmUsage = useChannelContextUsage(
    isDmChannel ? channelId : null,
    currentPubkey,
  );
  const threadUsage = useChannelContextUsage(
    threadRoot ? channelId : null,
    currentPubkey,
    threadRoot,
  );

  return {
    dmContextRing: isDmChannel && dmUsage ? renderContextRing(dmUsage) : null,
    threadContextRing:
      threadRoot && threadUsage ? renderContextRing(threadUsage) : null,
  } satisfies Record<"dmContextRing" | "threadContextRing", React.ReactNode>;
}
