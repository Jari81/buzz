import { CircleAlert, ChevronDown, ChevronUp, History } from "lucide-react";
import * as React from "react";

import type { ProjectIssue } from "@/features/projects/hooks";
import {
  formatExactTimestamp,
  pluralize,
  relativeTime,
} from "@/features/projects/lib/projectsViewHelpers";
import {
  resolveUserLabel,
  type UserProfileLookup,
} from "@/features/profile/lib/identity";
import { normalizePubkey } from "@/shared/lib/pubkey";
import { UserAvatar } from "@/shared/ui/UserAvatar";
import { ProfileAuthorName } from "./ProjectProfileIdentity";
import { ProjectRichContent } from "./ProjectRichContent";

const COLLAPSED_TECHNICAL_EVIDENCE_COUNT = 3;

export function ProjectIssueCommentTimeline({
  comments,
  profiles,
}: {
  comments: ProjectIssue["comments"];
  profiles?: UserProfileLookup;
}) {
  const [isCollapsed, setIsCollapsed] = React.useState(false);
  const [technicalEvidenceExpanded, setTechnicalEvidenceExpanded] =
    React.useState(false);
  const orderedComments = React.useMemo(
    () =>
      [...comments].sort(
        (left, right) =>
          left.createdAt - right.createdAt || left.id.localeCompare(right.id),
      ),
    [comments],
  );
  const actionComments = orderedComments.filter(
    (comment) => comment.actionRequired,
  );
  const technicalEvidence = orderedComments.filter(
    (comment) => !comment.actionRequired,
  );
  const earlierTechnicalEvidenceCount = Math.max(
    0,
    technicalEvidence.length - COLLAPSED_TECHNICAL_EVIDENCE_COUNT,
  );
  const visibleTechnicalEvidence = technicalEvidenceExpanded
    ? technicalEvidence
    : technicalEvidence.slice(-COLLAPSED_TECHNICAL_EVIDENCE_COUNT);
  const visibleCommentIds = new Set(
    [...actionComments, ...visibleTechnicalEvidence].map(
      (comment) => comment.id,
    ),
  );
  const displayedComments = isCollapsed
    ? []
    : orderedComments.filter((comment) => visibleCommentIds.has(comment.id));

  if (orderedComments.length === 0) {
    return null;
  }

  return (
    <div className="overflow-hidden px-px">
      <button
        aria-expanded={!isCollapsed}
        className="flex min-h-10 w-full items-center gap-2 py-2.5 text-sm font-semibold text-muted-foreground transition-colors hover:text-foreground"
        data-testid="project-issue-comment-history-toggle"
        onClick={() => setIsCollapsed((current) => !current)}
        type="button"
      >
        <span className="relative flex w-5 shrink-0 justify-center self-stretch">
          {!isCollapsed ? (
            <span className="absolute top-2.5 -bottom-[1.875rem] w-px bg-border/80" />
          ) : null}
          <span className="relative z-10 flex h-5 w-5 items-center justify-center rounded-full bg-primary/10 text-primary ring-1 ring-primary/35">
            <History className="h-3 w-3" />
          </span>
        </span>
        <span className="flex min-h-5 min-w-0 flex-1 items-center text-left">
          {isCollapsed
            ? `Show ${pluralize(orderedComments.length, "earlier comment")}`
            : "Collapse comment history"}
        </span>
        {isCollapsed ? (
          <ChevronDown className="mt-0.5 h-3.5 w-3.5" />
        ) : (
          <ChevronUp className="mt-0.5 h-3.5 w-3.5" />
        )}
      </button>

      {!isCollapsed &&
      (earlierTechnicalEvidenceCount > 0 || technicalEvidenceExpanded) ? (
        <button
          aria-expanded={technicalEvidenceExpanded}
          className="flex min-h-10 w-full items-center gap-2 py-2.5 text-sm font-semibold text-muted-foreground transition-colors hover:text-foreground"
          data-testid="project-issue-technical-evidence-toggle"
          onClick={() => setTechnicalEvidenceExpanded((current) => !current)}
          type="button"
        >
          <span className="relative flex w-5 shrink-0 justify-center self-stretch">
            <span className="absolute top-2.5 -bottom-[1.875rem] w-px bg-border/80" />
            <span className="relative z-10 flex h-5 w-5 items-center justify-center rounded-full bg-background ring-1 ring-border/70">
              {technicalEvidenceExpanded ? (
                <ChevronUp className="h-3 w-3" />
              ) : (
                <ChevronDown className="h-3 w-3" />
              )}
            </span>
          </span>
          <span className="min-w-0 flex-1 text-left">
            {technicalEvidenceExpanded
              ? "Show less technical evidence"
              : `Show ${pluralize(earlierTechnicalEvidenceCount, "earlier technical evidence comment")}`}
          </span>
        </button>
      ) : null}

      {displayedComments.map((comment, index) => {
        const authorLabel = resolveUserLabel({
          profiles,
          pubkey: comment.author,
        });
        return (
          <div
            className={`flex min-h-10 min-w-0 items-start gap-2 rounded-md py-2.5 text-sm text-muted-foreground ${
              comment.actionRequired
                ? "bg-primary/10 px-2 ring-1 ring-primary/30"
                : ""
            }`}
            data-testid="project-issue-comment-timeline-row"
            key={comment.id}
          >
            <div className="relative flex w-5 shrink-0 justify-center self-stretch">
              {index < displayedComments.length - 1 ? (
                <span className="absolute top-2.5 -bottom-[1.875rem] w-px bg-border/80" />
              ) : null}
              {/* bg-background keeps the connector line from showing through
                  while the avatar image (or delayed fallback) loads. */}
              <UserAvatar
                avatarUrl={
                  profiles?.[normalizePubkey(comment.author)]?.avatarUrl ?? null
                }
                className="relative z-10 bg-background ring-1 ring-border/70"
                displayName={authorLabel}
                size="xs"
              />
            </div>
            <div className="min-w-0 flex-1">
              {/* h-5 matches the avatar so the header line centers on it. */}
              <div className="flex h-5 min-w-0 items-center text-xs leading-4">
                <span className="min-w-0 flex-1 truncate">
                  <ProfileAuthorName pubkey={comment.author}>
                    {authorLabel}
                  </ProfileAuthorName>
                </span>
                {comment.actionRequired ? (
                  <span className="mr-2 inline-flex shrink-0 items-center gap-1 rounded-full bg-primary/15 px-1.5 py-0.5 text-2xs font-medium text-primary">
                    <CircleAlert className="h-3 w-3" />
                    Action required
                  </span>
                ) : null}
                <span
                  className="ml-auto w-20 shrink-0 text-right text-muted-foreground/70"
                  title={formatExactTimestamp(comment.createdAt)}
                >
                  {relativeTime(comment.createdAt)}
                </span>
              </div>
              <ProjectRichContent
                className="mt-1 text-sm text-foreground/90"
                content={comment.content}
                tags={comment.tags}
              />
            </div>
          </div>
        );
      })}
    </div>
  );
}
