import * as React from "react";
import { createFileRoute } from "@tanstack/react-router";

import { usePreviewFeatureWarning } from "@/shared/features";
import { ViewLoadingFallback } from "@/shared/ui/ViewLoadingFallback";

const AgentSessionsScreen = React.lazy(async () => {
  const module = await import(
    "@/features/agent-sessions/ui/AgentSessionsScreen"
  );
  return { default: module.AgentSessionsScreen };
});

export const Route = createFileRoute("/agent-sessions")({
  component: AgentSessionsRouteComponent,
});

function AgentSessionsRouteComponent() {
  usePreviewFeatureWarning("agentSessions");
  return (
    <React.Suspense fallback={<ViewLoadingFallback kind="agents" />}>
      <AgentSessionsScreen />
    </React.Suspense>
  );
}
