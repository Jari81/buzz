import { useMutation } from "@tanstack/react-query";

import { signProjectIssueStatus } from "@/shared/api/projectGit";
import { relayClient } from "@/shared/api/relayClient";
import { signRelayEvent } from "@/shared/api/tauri";
import {
  KIND_GIT_STATUS_CLOSED,
  KIND_GIT_STATUS_DRAFT,
  KIND_GIT_STATUS_MERGED,
  KIND_GIT_STATUS_OPEN,
} from "@/shared/constants/kinds";
import type { Repository as Project } from "./hooks";
import { useProjectIssueWriteInvalidation } from "./issueAssignments";
import {
  nextProjectIssueStatusCreatedAt,
  PROJECT_ISSUE_STATUS,
  type ProjectIssue,
  type ProjectIssueStatus,
} from "./projectIssues.mjs";

/** NIP-34 lifecycle states the desktop can publish for an issue.
 *
 * "In Progress" and "In Review" are deliberately absent: they are label
 * heuristics in `statusFromEvent`, not protocol states, so there is no status
 * event that could express them. */
export type ProjectIssueLifecycleStatus =
  | "open"
  | "resolved"
  | "closed"
  | "draft";

const ISSUE_STATUS_KIND_BY_LIFECYCLE: Record<
  ProjectIssueLifecycleStatus,
  number
> = {
  open: KIND_GIT_STATUS_OPEN,
  resolved: KIND_GIT_STATUS_MERGED,
  closed: KIND_GIT_STATUS_CLOSED,
  draft: KIND_GIT_STATUS_DRAFT,
};

/** Display label for each publishable lifecycle state, matching the labels
 * `statusFromEvent` derives when the event is read back. */
export const ISSUE_LIFECYCLE_STATUS_LABEL: Record<
  ProjectIssueLifecycleStatus,
  ProjectIssueStatus
> = {
  open: PROJECT_ISSUE_STATUS.BACKLOG,
  draft: PROJECT_ISSUE_STATUS.TRIAGE,
  resolved: PROJECT_ISSUE_STATUS.DONE,
  closed: PROJECT_ISSUE_STATUS.CLOSED,
};

/** The publishable states, in the order the picker offers them. */
export const ISSUE_LIFECYCLE_STATUSES: ProjectIssueLifecycleStatus[] = [
  "draft",
  "open",
  "resolved",
  "closed",
];

/** The issue author, the repo owner, and anyone assigned to the issue are
 * trusted for status changes. A managed-agent owner counts as the owner
 * because the desktop can sign on its behalf. Assignees are the ticket's
 * handlers ("Bearbeiter"): whoever works the issue must be able to move it,
 * not just whoever opened it. The read path applies the same rule in
 * `latestStatusForIssue`, so a status event published by an assignee is
 * honored instead of silently discarded. */
export function canChangeProjectIssueStatus({
  isManagedAgentOwner,
  issueAssignees,
  issueAuthor,
  projectOwner,
  viewer,
}: {
  isManagedAgentOwner: boolean;
  issueAssignees: readonly string[];
  issueAuthor: string;
  projectOwner: string;
  viewer: string | null;
}): boolean {
  if (!viewer) return false;
  return (
    viewer === issueAuthor.toLowerCase() ||
    viewer === projectOwner.toLowerCase() ||
    isManagedAgentOwner ||
    issueAssignees.some((assignee) => viewer === assignee.toLowerCase())
  );
}

// Same shape as `buzz issues status` (buzz-sdk build_git_status) and
// `buildGitStatusTags`: root `e` tag, repo `a` tag, and `p` tags for the repo
// owner + issue author. The `a` tag is load-bearing — `fetchProjectIssues`
// reads status events with an `#a` filter, so an event without it is invisible
// to the desktop and the issue silently falls back to Backlog.
async function updateProjectIssueStatus({
  issue,
  project,
  signAsManagedOwner,
  status,
}: {
  issue: ProjectIssue;
  project: Project;
  signAsManagedOwner: boolean;
  status: ProjectIssueLifecycleStatus;
}): Promise<void> {
  const createdAt = nextProjectIssueStatusCreatedAt(
    issue,
    Math.floor(Date.now() / 1_000),
  );
  if (signAsManagedOwner) {
    await signProjectIssueStatus({
      targetOwner: project.owner,
      repoAddress: project.repoAddress,
      issueId: issue.id,
      issueAuthor: issue.author,
      status,
      createdAt,
    });
    return;
  }
  const recipients = new Set([
    project.owner.toLowerCase(),
    issue.author.toLowerCase(),
  ]);
  const event = await signRelayEvent({
    kind: ISSUE_STATUS_KIND_BY_LIFECYCLE[status],
    content: "",
    createdAt,
    tags: [
      ["e", issue.id, "", "root"],
      ["a", project.repoAddress],
      ...[...recipients].map((recipient) => ["p", recipient]),
    ],
  });

  await relayClient.publishEvent(
    event,
    "Timed out updating issue status.",
    "Failed to update issue status.",
  );
}

export function useUpdateProjectIssueStatusMutation(
  project: Project | null | undefined,
) {
  const invalidate = useProjectIssueWriteInvalidation(project);

  return useMutation({
    mutationFn: (input: {
      issue: ProjectIssue;
      signAsManagedOwner: boolean;
      status: ProjectIssueLifecycleStatus;
    }) => {
      if (!project) throw new Error("No project selected.");
      return updateProjectIssueStatus({ ...input, project });
    },
    onSuccess: invalidate,
  });
}
