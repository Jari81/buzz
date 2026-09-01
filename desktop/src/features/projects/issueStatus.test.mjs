import assert from "node:assert/strict";
import test from "node:test";

import {
  availableProjectIssueLifecycleStatuses,
  buildProjectIssueVerdict,
  canSubmitProjectIssueVerdict,
  canChangeProjectIssueStatus,
  ISSUE_LIFECYCLE_STATUS_LABEL,
  ISSUE_LIFECYCLE_STATUSES,
  MAX_REJECTION_REASON_LENGTH,
} from "./issueStatus.ts";

const OWNER = "a".repeat(64);
const AUTHOR = "b".repeat(64);
const ASSIGNEE = "d".repeat(64);
const OA_OWNER = "e".repeat(64);
const STRANGER = "c".repeat(64);

test("every publishable lifecycle state maps to the label the read path derives", () => {
  assert.deepEqual(ISSUE_LIFECYCLE_STATUSES, [
    "draft",
    "open",
    "resolved",
    "closed",
  ]);
  assert.deepEqual(
    ISSUE_LIFECYCLE_STATUSES.map(
      (status) => ISSUE_LIFECYCLE_STATUS_LABEL[status],
    ),
    ["Triage", "Backlog", "Done", "Closed"],
  );
});

test("current review removes generic resolved from the lifecycle picker", () => {
  assert.deepEqual(availableProjectIssueLifecycleStatuses(true), [
    "draft",
    "open",
    "closed",
  ]);
  assert.deepEqual(availableProjectIssueLifecycleStatuses(false), [
    "draft",
    "open",
    "resolved",
    "closed",
  ]);
});

test("label-driven states are not offered as publishable statuses", () => {
  const labels = ISSUE_LIFECYCLE_STATUSES.map(
    (status) => ISSUE_LIFECYCLE_STATUS_LABEL[status],
  );
  assert.equal(labels.includes("In Progress"), false);
  assert.equal(labels.includes("In Review"), false);
});

test("builds exact personal-signed human verdict contracts", () => {
  const reviewId = "9".repeat(64);
  const issue = {
    author: AUTHOR,
    currentReview: { id: reviewId },
    id: "f".repeat(64),
  };
  const project = { owner: OWNER, repoAddress: `30617:${OWNER}:demo` };

  assert.deepEqual(
    buildProjectIssueVerdict({ issue, project, verdict: "accepted" }),
    {
      content: "",
      kind: 1631,
      tags: [
        ["e", issue.id, "", "root"],
        ["a", project.repoAddress],
        ["p", OWNER],
        ["p", AUTHOR],
        ["t", "human-verdict"],
        ["verdict", "accepted"],
        ["review", reviewId],
      ],
    },
  );
  assert.deepEqual(
    buildProjectIssueVerdict({
      issue,
      project,
      reason: "The target does not load.",
      verdict: "rejected",
    }),
    {
      content: "The target does not load.",
      kind: 1630,
      tags: [
        ["e", issue.id, "", "root"],
        ["a", project.repoAddress],
        ["p", OWNER],
        ["p", AUTHOR],
        ["t", "human-verdict"],
        ["verdict", "rejected"],
        ["review", reviewId],
      ],
    },
  );
  assert.throws(
    () =>
      buildProjectIssueVerdict({
        issue,
        project,
        reason: "bad\nreason",
        verdict: "rejected",
      }),
    /reason/i,
  );
});

test("human verdict recipients are the deduped exact owner and author set", () => {
  const issue = {
    author: OWNER,
    currentReview: { id: "9".repeat(64) },
    id: "f".repeat(64),
  };
  const project = { owner: OWNER, repoAddress: `30617:${OWNER}:demo` };

  const verdict = buildProjectIssueVerdict({
    issue,
    project,
    verdict: "accepted",
  });
  assert.deepEqual(
    verdict.tags.filter((tag) => tag[0] === "p"),
    [["p", OWNER]],
  );
  assert.equal(verdict.content, "");
});

test("rejection reasons enforce the exact 500-character contract", () => {
  assert.equal(MAX_REJECTION_REASON_LENGTH, 500);
  const issue = {
    author: AUTHOR,
    currentReview: { id: "9".repeat(64) },
    id: "f".repeat(64),
  };
  const project = { owner: OWNER, repoAddress: `30617:${OWNER}:demo` };

  assert.equal(
    buildProjectIssueVerdict({
      issue,
      project,
      reason: "x".repeat(500),
      verdict: "rejected",
    }).content.length,
    500,
  );
  assert.throws(
    () =>
      buildProjectIssueVerdict({
        issue,
        project,
        reason: "x".repeat(501),
        verdict: "rejected",
      }),
    /500/,
  );
});

test("only configured human verdict actors may submit a current review", () => {
  const issue = {
    currentReview: { authorizedHumanPubkeys: [OWNER, OA_OWNER] },
  };
  assert.equal(canSubmitProjectIssueVerdict(issue, OWNER), true);
  assert.equal(
    canSubmitProjectIssueVerdict(issue, OA_OWNER.toUpperCase()),
    true,
  );
  assert.equal(canSubmitProjectIssueVerdict(issue, ASSIGNEE), false);
  assert.equal(canSubmitProjectIssueVerdict(issue, null), false);
  assert.equal(
    canSubmitProjectIssueVerdict({ currentReview: null }, OWNER),
    false,
  );
});

test("issue author and repo owner may change status", () => {
  for (const viewer of [AUTHOR, OWNER]) {
    assert.equal(
      canChangeProjectIssueStatus({
        isManagedAgentOwner: false,
        isOaOwner: false,
        issueAssignees: [],
        issueAuthor: AUTHOR,
        projectOwner: OWNER,
        viewer,
      }),
      true,
    );
  }
});

test("an assignee may change status", () => {
  assert.equal(
    canChangeProjectIssueStatus({
      isManagedAgentOwner: false,
      isOaOwner: false,
      issueAssignees: [ASSIGNEE],
      issueAuthor: AUTHOR,
      projectOwner: OWNER,
      viewer: ASSIGNEE,
    }),
    true,
  );
});

test("a third party may not change status", () => {
  assert.equal(
    canChangeProjectIssueStatus({
      isManagedAgentOwner: false,
      isOaOwner: false,
      issueAssignees: [ASSIGNEE],
      issueAuthor: AUTHOR,
      projectOwner: OWNER,
      viewer: STRANGER,
    }),
    false,
  );
});

test("a signed-out viewer may not change status", () => {
  assert.equal(
    canChangeProjectIssueStatus({
      isManagedAgentOwner: true,
      isOaOwner: false,
      issueAssignees: [],
      issueAuthor: AUTHOR,
      projectOwner: OWNER,
      viewer: null,
    }),
    false,
  );
});

test("the human owner of a managed-agent repo owner may change status", () => {
  assert.equal(
    canChangeProjectIssueStatus({
      isManagedAgentOwner: true,
      isOaOwner: false,
      issueAssignees: [],
      issueAuthor: AUTHOR,
      projectOwner: OWNER,
      viewer: STRANGER,
    }),
    true,
  );
});

test("the verified NIP-OA owner of an external repo-owner agent may change status", () => {
  assert.equal(
    canChangeProjectIssueStatus({
      isManagedAgentOwner: false,
      isOaOwner: true,
      issueAssignees: [],
      issueAuthor: AUTHOR,
      projectOwner: OWNER,
      viewer: OA_OWNER,
    }),
    true,
  );
});
