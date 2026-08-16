import {
  CalendarClock,
  Clock3,
  GitPullRequest,
  MessageSquare,
  SmilePlus,
  Webhook,
  Zap,
} from "lucide-react";
import type { LucideIcon } from "lucide-react";

import type { Workflow } from "@/shared/api/types";
import { cn } from "@/shared/lib/cn";
import { WorkflowActionsMenu } from "./WorkflowActionsMenu";
import {
  getWorkflowDescription,
  getWorkflowDisplayStatus,
  getWorkflowEnabled,
  getWorkflowTriggerSummary,
} from "./workflowDefinition";

type WorkflowCardProps = {
  workflow: Workflow;
  channelName?: string;
  isActive?: boolean;
  isTogglingEnabled?: boolean;
  onSelect: (workflowId: string) => void;
  onTrigger: (workflowId: string) => void;
  onToggleEnabled: (workflow: Workflow) => void;
  onEdit: (workflow: Workflow) => void;
  onDuplicate: (workflow: Workflow) => void;
  onDelete: (workflow: Workflow) => void;
};

const TRIGGER_ICONS: Record<string, LucideIcon> = {
  diff_posted: GitPullRequest,
  message_posted: MessageSquare,
  reaction_added: SmilePlus,
  schedule: CalendarClock,
  webhook: Webhook,
};

function getTriggerType(definition: Record<string, unknown>): string | null {
  const trigger = definition.trigger;
  if (!trigger || typeof trigger !== "object" || Array.isArray(trigger)) {
    return null;
  }
  const on = (trigger as Record<string, unknown>).on;
  return typeof on === "string" ? on : null;
}

function StatusBadge({ status }: { status: Workflow["status"] }) {
  return (
    <span
      className={cn(
        "rounded-full border border-border/65 bg-background/80 px-2 py-1 text-2xs font-semibold uppercase tracking-wider shadow-xs",
        status === "active" ? "text-foreground" : "text-muted-foreground",
      )}
    >
      {status}
    </span>
  );
}

export function WorkflowCard({
  workflow,
  channelName,
  isActive = false,
  isTogglingEnabled = false,
  onSelect,
  onTrigger,
  onToggleEnabled,
  onEdit,
  onDuplicate,
  onDelete,
}: WorkflowCardProps) {
  const displayStatus = getWorkflowDisplayStatus(workflow);
  const description = getWorkflowDescription(workflow.definition);
  const triggerSummary = getWorkflowTriggerSummary(workflow.definition);
  const triggerType = getTriggerType(workflow.definition);
  const TriggerIcon = triggerType ? TRIGGER_ICONS[triggerType] : undefined;

  return (
    <div
      className={cn(
        "group relative min-h-60 w-full overflow-hidden rounded-2xl border border-border/70 bg-muted/50 p-5 text-left text-foreground shadow-xs transition-colors hover:border-border hover:bg-muted/65",
        isActive && "border-primary/50 bg-primary/5 ring-1 ring-primary/30",
      )}
      data-testid={`workflow-card-${workflow.id}`}
    >
      <button
        className="absolute inset-0 z-0 rounded-2xl focus-visible:outline-hidden focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring"
        onClick={() => onSelect(workflow.id)}
        type="button"
      >
        <span className="sr-only">View {workflow.name}</span>
      </button>

      <div className="pointer-events-none relative z-10 flex h-full min-h-48 flex-col">
        <div className="flex items-start justify-between gap-3">
          <span className="flex h-9 w-9 items-center justify-center rounded-xl border border-border/65 bg-background/80 text-muted-foreground shadow-xs">
            {TriggerIcon ? (
              <TriggerIcon className="h-5 w-5" />
            ) : (
              <Zap className="h-5 w-5" />
            )}
          </span>
          <div className="pointer-events-auto flex items-center gap-1.5">
            <StatusBadge status={displayStatus} />
            <WorkflowActionsMenu
              isEnabled={getWorkflowEnabled(workflow.definition)}
              isTogglingEnabled={isTogglingEnabled}
              onDelete={() => onDelete(workflow)}
              onDuplicate={() => onDuplicate(workflow)}
              onEdit={() => onEdit(workflow)}
              onToggleEnabled={() => onToggleEnabled(workflow)}
              onTrigger={() => onTrigger(workflow.id)}
            />
          </div>
        </div>

        <h3 className="mt-5 line-clamp-2 text-lg font-semibold tracking-tight">
          {workflow.name}
        </h3>
        {triggerSummary ? (
          <p className="mt-2 line-clamp-2 text-xs font-medium text-muted-foreground">
            {triggerSummary}
          </p>
        ) : null}
        {description ? (
          <p className="mt-2 line-clamp-3 text-sm leading-relaxed text-muted-foreground">
            {description}
          </p>
        ) : null}

        <div className="mt-auto flex min-w-0 items-end justify-between gap-3 pt-5 text-muted-foreground">
          <p className="min-w-0 truncate text-xs font-medium">
            {channelName ? `#${channelName}` : "Channel workflow"}
          </p>
          <span className="flex shrink-0 items-center gap-1 text-2xs">
            <Clock3 className="h-3.5 w-3.5" />
            {new Date(workflow.updatedAt * 1000).toLocaleDateString()}
          </span>
        </div>
      </div>
    </div>
  );
}
