import * as React from "react";
import {
  Bot,
  Circle,
  CircleAlert,
  Loader2,
  RotateCcw,
  TerminalSquare,
} from "lucide-react";
import { toast } from "sonner";

import {
  deriveAgentSessions,
  type AgentSessionSummary,
} from "@/features/agents/ui/agentSessionSummary";
import { buildTranscriptState } from "@/features/agents/ui/agentSessionTranscript";
import { useObserverEvents } from "@/features/agents/ui/useObserverEvents";
import { AgentSessionTranscriptList } from "@/features/agents/ui/AgentSessionTranscriptList";
import { isRotateSessionAuthorized } from "@/features/agent-sessions/lib/rotateSessionAuth";
import {
  useContextUsageArchive,
  asTurnMetric,
  formatTokenCount,
} from "@/features/agents/lib/agentContextUsage";
import { resolveContextWindow } from "@/features/agents/lib/modelContextLimits";
import {
  useRelayAgentsQuery,
  useManagedAgentsQuery,
} from "@/features/agents/hooks";
import { useIdentityQuery } from "@/shared/api/hooks";
import { sendChannelMessage } from "@/shared/api/tauri";
import { normalizePubkey } from "@/shared/lib/pubkey";
import { cn } from "@/shared/lib/cn";
import { UserAvatar } from "@/shared/ui/UserAvatar";

/**
 * BUZZ-DESKTOP-003 / Phase 1: the Agent Sessions panel.
 *
 * Left column: every agent with observer coverage (managed + relay), each
 * expandable into its sessions (grouped by sessionId via deriveAgentSessions).
 * Right column: the full transcript of the selected session.
 *
 * Data sources:
 * - Live observer frames (kind 24200) via useObserverEvents — the same store
 *   the activity bar and existing session panels read.
 * - Archived kind:44200 metrics for token/cost context per session.
 */

type AgentIdentity = {
  pubkey: string;
  name: string;
  source: "managed" | "relay";
};

/** Stuck heuristic: no turn_completed/turn_error since the last event and
 *  last activity older than this threshold → possibly stuck. */
const STUCK_THRESHOLD_MS = 15 * 60_000;

function isPossiblyStuck(session: AgentSessionSummary): boolean {
  if (session.status !== "running") return false;
  const last = Date.parse(session.lastTimestamp);
  return Number.isFinite(last) && Date.now() - last > STUCK_THRESHOLD_MS;
}

function useAgentIdentities(): AgentIdentity[] {
  const managed = useManagedAgentsQuery();
  const relay = useRelayAgentsQuery();

  return React.useMemo(() => {
    const byKey = new Map<string, AgentIdentity>();
    for (const agent of relay.data ?? []) {
      byKey.set(normalizePubkey(agent.pubkey), {
        pubkey: agent.pubkey,
        name: agent.name,
        source: "relay",
      });
    }
    for (const agent of managed.data ?? []) {
      const key = normalizePubkey(agent.pubkey);
      if (!byKey.has(key)) {
        byKey.set(key, {
          pubkey: agent.pubkey,
          name: agent.name,
          source: "managed",
        });
      }
    }
    return [...byKey.values()];
  }, [managed.data, relay.data]);
}

/** One agent's session list derived from its live observer window. */
function useAgentSessionTree(agent: AgentIdentity) {
  const snapshot = useObserverEvents(true, agent.pubkey);
  return React.useMemo(() => {
    const sessions = deriveAgentSessions(snapshot.events);
    return { sessions, eventCount: snapshot.events.length };
  }, [snapshot.events]);
}

/** Token/cost context for one session from archived kind:44200 metrics. */
function useSessionMetrics(sessionId: string | null) {
  const identity = useIdentityQuery();
  const archive = useContextUsageArchive(identity.data?.pubkey);

  return React.useMemo(() => {
    if (!sessionId || !archive.data) return null;
    let model: string | null = null;
    let maxInput = 0;
    let lastInput: number | null = null;
    let cost = 0;
    let turns = 0;
    for (const raw of archive.data) {
      const payload = asTurnMetric(raw);
      if (!payload || payload.sessionId !== sessionId) continue;
      turns += 1;
      if (payload.model && !model) model = payload.model;
      const input = payload.turn?.inputTokens;
      if (typeof input === "number" && Number.isFinite(input)) {
        if (lastInput == null) lastInput = input;
        if (input > maxInput) maxInput = input;
      }
      const c = payload.turn?.costUsd;
      if (typeof c === "number" && Number.isFinite(c)) cost += c;
    }
    if (turns === 0) return null;
    const window = resolveContextWindow(model, maxInput);
    return { model, contextWindow: window, lastInput, cost, turns };
  }, [sessionId, archive.data]);
}

function StatusIcon({
  status,
  stuck,
}: {
  status: AgentSessionSummary["status"];
  stuck: boolean;
}) {
  if (status === "error")
    return <CircleAlert aria-hidden className="h-3.5 w-3.5 text-destructive" />;
  if (stuck)
    return <CircleAlert aria-hidden className="h-3.5 w-3.5 text-amber-500" />;
  if (status === "running")
    return (
      <Loader2
        aria-hidden
        className="h-3.5 w-3.5 animate-spin text-muted-foreground"
      />
    );
  return (
    <Circle aria-hidden className="h-3.5 w-3.5 text-muted-foreground/50" />
  );
}

function relativeTime(iso: string): string {
  const ts = Date.parse(iso);
  if (!Number.isFinite(ts)) return "";
  const mins = Math.max(0, Math.round((Date.now() - ts) / 60_000));
  if (mins < 1) return "now";
  if (mins < 60) return `${mins}m ago`;
  const hours = Math.round(mins / 60);
  if (hours < 24) return `${hours}h ago`;
  return `${Math.round(hours / 24)}d ago`;
}

function SessionRow({
  selected,
  session,
  onSelect,
}: {
  selected: boolean;
  session: AgentSessionSummary;
  onSelect: () => void;
}) {
  const stuck = isPossiblyStuck(session);
  return (
    <button
      className={cn(
        "flex w-full items-center gap-2 rounded-md px-2 py-1.5 text-left text-sm hover:bg-accent",
        selected && "bg-accent",
      )}
      onClick={onSelect}
      type="button"
    >
      <StatusIcon status={session.status} stuck={stuck} />
      <span className="min-w-0 flex-1 truncate font-mono text-xs">
        {session.sessionId.slice(0, 8)}
      </span>
      {stuck ? <span className="text-xs text-amber-500">stuck?</span> : null}
      <span className="shrink-0 text-xs text-muted-foreground">
        {session.turnCount}t · {relativeTime(session.lastTimestamp)}
      </span>
    </button>
  );
}

/** One agent row with its session list. Owns its hook calls (one per
 * component instance — hooks in a .map() would be invalid React). */
function AgentTreeSection({
  agent,
  selectedSessionId,
  onSelect,
}: {
  agent: AgentIdentity;
  selectedSessionId: string | null;
  onSelect: (agentPubkey: string, sessionId: string) => void;
}) {
  const { sessions } = useAgentSessionTree(agent);
  return (
    <div className="mb-3">
      <div className="flex items-center gap-2 px-1 py-1">
        <UserAvatar avatarUrl={null} displayName={agent.name} size="sm" />
        <span className="min-w-0 flex-1 truncate text-sm font-medium">
          {agent.name}
        </span>
        <span className="text-xs text-muted-foreground">{sessions.length}</span>
      </div>
      {sessions.length === 0 ? (
        <p className="px-2 py-1 text-xs text-muted-foreground">
          No observer events yet.
        </p>
      ) : (
        sessions.map((session) => (
          <SessionRow
            key={session.sessionId}
            onSelect={() => onSelect(agent.pubkey, session.sessionId)}
            selected={selectedSessionId === session.sessionId}
            session={session}
          />
        ))
      )}
    </div>
  );
}

export function AgentSessionsScreen() {
  const agents = useAgentIdentities();
  const [selected, setSelected] = React.useState<{
    agentPubkey: string;
    sessionId: string;
  } | null>(null);

  // Observer ingestion is app-wide already (AppShell mounts
  // useAgentObserverIngestion), so per-agent tree reads are cheap store
  // lookups inside AgentTreeSection — no hook-in-loop here.
  const selectedAgent = selected
    ? (agents.find((a) => a.pubkey === selected.agentPubkey) ?? null)
    : null;
  const metrics = useSessionMetrics(selected?.sessionId ?? null);

  return (
    <div className="flex h-full min-h-0">
      {/* Left: agent → session tree */}
      <aside className="flex w-72 shrink-0 flex-col overflow-y-auto border-r border-border/60 p-3">
        <h2 className="mb-2 flex items-center gap-2 text-sm font-semibold tracking-tight">
          <Bot aria-hidden className="h-4 w-4" />
          Agent sessions
        </h2>
        {agents.length === 0 ? (
          <p className="text-sm text-muted-foreground">No agents discovered.</p>
        ) : null}
        {agents.map((agent) => (
          <AgentTreeSection
            agent={agent}
            key={agent.pubkey}
            onSelect={(agentPubkey, sessionId) =>
              setSelected({ agentPubkey, sessionId })
            }
            selectedSessionId={
              selected?.agentPubkey === agent.pubkey ? selected.sessionId : null
            }
          />
        ))}
      </aside>

      {/* Right: transcript + metrics for the selected session */}
      <section className="flex min-w-0 flex-1 flex-col overflow-hidden">
        {selected && selectedAgent ? (
          <SelectedSessionTranscript
            agentPubkey={selectedAgent.pubkey}
            agentName={selectedAgent.name}
            metrics={metrics}
            sessionId={selected.sessionId}
          />
        ) : (
          <div className="flex h-full flex-col items-center justify-center gap-3 text-muted-foreground">
            <TerminalSquare aria-hidden className="h-6 w-6" />
            <p className="text-sm">
              Select a session to inspect its transcript.
            </p>
          </div>
        )}
      </section>
    </div>
  );
}

function SelectedSessionTranscript({
  agentName,
  agentPubkey,
  metrics,
  sessionId,
}: {
  agentName: string;
  agentPubkey: string;
  metrics: ReturnType<typeof useSessionMetrics>;
  sessionId: string;
}) {
  const snapshot = useObserverEvents(true, agentPubkey);
  const sessionEvents = React.useMemo(
    () => snapshot.events.filter((e) => e.sessionId === sessionId),
    [snapshot.events, sessionId],
  );
  const transcript = React.useMemo(
    () => buildTranscriptState(sessionEvents).items,
    [sessionEvents],
  );

  const turnIds = React.useMemo(() => {
    const ids = new Set<string>();
    for (const e of sessionEvents) {
      if (e.turnId) ids.add(e.turnId);
    }
    return ids.size;
  }, [sessionEvents]);

  const channelId = React.useMemo(
    () => sessionEvents.find((e) => e.channelId)?.channelId ?? null,
    [sessionEvents],
  );

  const fillPct =
    metrics?.lastInput != null && metrics.contextWindow > 0
      ? Math.round((metrics.lastInput / metrics.contextWindow) * 100)
      : null;

  return (
    <>
      <header className="flex flex-wrap items-center gap-x-4 gap-y-1 border-b border-border/60 px-4 py-3">
        <h3 className="min-w-0 truncate text-sm font-semibold">
          {agentName} ·{" "}
          <span className="font-mono">{sessionId.slice(0, 12)}</span>
        </h3>
        <span className="text-xs text-muted-foreground">
          {turnIds} turn{turnIds === 1 ? "" : "s"}
        </span>
        {metrics ? (
          <>
            <span className="text-xs text-muted-foreground">
              {metrics.model ?? "model unknown"}
            </span>
            {fillPct != null && metrics.lastInput != null ? (
              <span
                className={cn(
                  "text-xs font-medium",
                  fillPct > 85
                    ? "text-destructive"
                    : fillPct > 60
                      ? "text-amber-500"
                      : "text-muted-foreground",
                )}
              >
                {fillPct}% ctx · {formatTokenCount(metrics.lastInput)}/
                {formatTokenCount(metrics.contextWindow)}
              </span>
            ) : null}
            {metrics.cost > 0 ? (
              <span className="text-xs text-muted-foreground">
                ${metrics.cost.toFixed(4)}
              </span>
            ) : null}
          </>
        ) : (
          <span className="text-xs text-muted-foreground">
            no token metrics yet
          </span>
        )}
        <RotateSessionButton agentPubkey={agentPubkey} channelId={channelId} />
      </header>
      <div className="min-h-0 flex-1 overflow-hidden">
        <AgentSessionTranscriptList
          agentAvatarUrl={null}
          agentName={agentName}
          agentPubkey={agentPubkey}
          channelId={channelId}
          emptyDescription="No events recorded for this session yet."
          emptyState="idle"
          items={transcript}
          autoTail={false}
          scrollScopeKey={`agent-sessions:${agentPubkey}:${sessionId}`}
        />
      </div>
    </>
  );
}

/**
 * Kill/reset control for one session: publishes the harness `!rotate`
 * owner command (kind 9, content exactly "!rotate", agent p-tag mention)
 * into the session's channel. buzz-acp consumes it owner-side: an
 * in-flight turn is cancelled and the channel session invalidated; idle
 * channel sessions are dropped immediately — the next mention starts a
 * fresh session. This is the documented cleanup path for stuck/dead
 * sessions (see LOCAL_MODIFICATIONS BUZZ-ACP notes); rotation is
 * per-channel, matching the harness contract.
 */
function RotateSessionButton({
  agentPubkey,
  channelId,
}: {
  agentPubkey: string;
  channelId: string | null;
}) {
  const identity = useIdentityQuery();
  const relayAgents = useRelayAgentsQuery();
  const [pending, setPending] = React.useState(false);

  const authorized = isRotateSessionAuthorized(
    relayAgents.data,
    identity.data?.pubkey ?? null,
    agentPubkey,
  );

  const rotate = React.useCallback(async () => {
    if (!channelId) {
      toast.error("No channel known for this session — cannot reset it.");
      return;
    }
    const confirmed = window.confirm(
      "Reset this agent's channel session?\n\n" +
        "This sends !rotate to the channel: the harness cancels any in-flight turn and starts the next prompt with a fresh session. " +
        "Idle sessions are dropped immediately. Only the agent owner can do this.",
    );
    if (!confirmed) return;
    setPending(true);
    try {
      await sendChannelMessage(channelId, "!rotate", undefined, undefined, [
        agentPubkey,
      ]);
      toast.success("Reset sent — the session will rotate.");
    } catch (error) {
      toast.error(
        `Reset failed: ${error instanceof Error ? error.message : String(error)}`,
      );
    } finally {
      setPending(false);
    }
  }, [agentPubkey, channelId]);

  return (
    <button
      className={cn(
        "ml-auto flex items-center gap-1 rounded-md border border-border/60 px-2 py-1 text-xs text-muted-foreground hover:bg-accent hover:text-foreground",
        (!authorized || pending) && "opacity-50",
      )}
      disabled={!authorized || pending}
      onClick={rotate}
      title={
        authorized
          ? "Send !rotate: cancel in-flight turn and reset the channel session"
          : "Only the agent owner can rotate sessions"
      }
      type="button"
    >
      {pending ? (
        <Loader2 aria-hidden className="h-3 w-3 animate-spin" />
      ) : (
        <RotateCcw aria-hidden className="h-3 w-3" />
      )}
      Reset session
    </button>
  );
}
