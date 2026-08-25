import { ArrowLeft, X } from "lucide-react";
import * as React from "react";

import { useProjectsQuery } from "@/features/projects/hooks";
import { ProjectIssuesPanel } from "@/features/projects/ui/ProjectIssuesPanel";
import { RightAuxiliaryPane } from "@/features/channels/ui/RightAuxiliaryPane";
import type { Channel } from "@/shared/api/types";
import { Button } from "@/shared/ui/button";
import type { UserProfileLookup } from "@/features/profile/lib/identity";

type ChannelIssuesAuxiliaryPanelProps = {
  activeChannel: Channel;
  canResetWidth: boolean;
  onClose: () => void;
  onResetWidth: () => void;
  onResizeStart: (event: React.PointerEvent<HTMLButtonElement>) => void;
  profiles?: UserProfileLookup;
  widthPx: number;
};

/**
 * Channel-scoped issue surface. The channel binding on a repository is the
 * authority for scope: no binding means no issue list, never a global fallback.
 */
export function ChannelIssuesAuxiliaryPanel({
  activeChannel,
  canResetWidth,
  onClose,
  onResetWidth,
  onResizeStart,
  profiles,
  widthPx,
}: ChannelIssuesAuxiliaryPanelProps) {
  const projectsQuery = useProjectsQuery();
  const repository = projectsQuery.data
    ?.flatMap((project) => project.repositories)
    .find((candidate) => candidate.channelId === activeChannel.id);
  const [selectedIssueId, setSelectedIssueId] = React.useState<string | null>(
    null,
  );

  return (
    <RightAuxiliaryPane
      canResetWidth={canResetWidth}
      onResetWidth={onResetWidth}
      onResizeStart={onResizeStart}
      testId="channel-issues-auxiliary-pane"
      widthPx={widthPx}
    >
      <div className="flex min-h-0 flex-1 flex-col">
        <header className="flex shrink-0 items-center justify-between border-b border-border/60 px-4 py-3">
          <div className="flex min-w-0 items-center gap-2">
            {selectedIssueId ? (
              <Button
                aria-label="Back to issues"
                onClick={() => setSelectedIssueId(null)}
                size="icon"
                title="Back to issues"
                type="button"
                variant="ghost"
              >
                <ArrowLeft className="h-4 w-4" />
              </Button>
            ) : null}
            <div className="min-w-0">
              <h2 className="text-sm font-semibold">Issues</h2>
              <p className="truncate text-xs text-muted-foreground">
                {repository?.name ?? "No repository linked to this channel"}
              </p>
            </div>
          </div>
          <Button
            aria-label="Close issues"
            onClick={onClose}
            size="icon"
            title="Close issues"
            type="button"
            variant="ghost"
          >
            <X className="h-4 w-4" />
          </Button>
        </header>
        <div className="min-h-0 flex-1 overflow-y-auto">
          {projectsQuery.isLoading ? (
            <p className="p-4 text-sm text-muted-foreground">Loading issues…</p>
          ) : repository ? (
            <ProjectIssuesPanel
              onSelectedIssueIdChange={setSelectedIssueId}
              profiles={profiles}
              project={repository}
              selectedIssueId={selectedIssueId}
            />
          ) : (
            <p className="p-4 text-sm text-muted-foreground">
              Link a repository to this channel to keep its issue work here.
            </p>
          )}
        </div>
      </div>
    </RightAuxiliaryPane>
  );
}
