import assert from "node:assert/strict";
import test from "node:test";

import {
  canChangeProjectIssueStatus,
  ISSUE_LIFECYCLE_STATUS_LABEL,
  ISSUE_LIFECYCLE_STATUSES,
} from "./issueStatus.ts";

const OWNER = "a".repeat(64);
const AUTHOR = "b".repeat(64);
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

test("label-driven states are not offered as publishable statuses", () => {
  const labels = ISSUE_LIFECYCLE_STATUSES.map(
    (status) => ISSUE_LIFECYCLE_STATUS_LABEL[status],
  );
  assert.equal(labels.includes("In Progress"), false);
  assert.equal(labels.includes("In Review"), false);
});

test("issue author and repo owner may change status", () => {
  for (const viewer of [AUTHOR, OWNER]) {
    assert.equal(
      canChangeProjectIssueStatus({
        isManagedAgentOwner: false,
        issueAuthor: AUTHOR,
        projectOwner: OWNER,
        viewer,
      }),
      true,
    );
  }
});

test("a third party may not change status", () => {
  assert.equal(
    canChangeProjectIssueStatus({
      isManagedAgentOwner: false,
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
      issueAuthor: AUTHOR,
      projectOwner: OWNER,
      viewer: STRANGER,
    }),
    true,
  );
});
