import assert from "node:assert/strict";
import test from "node:test";

import {
  filterIssueRowsByRepository,
  issueRepositoryScopeOptions,
  normalizeIssueRepositoryScope,
} from "./issueRepositoryScope.ts";

const CONTROL_ROOM = "30617:aaaa:control-room";
const PATTERNDY = "30617:bbbb:patterndy";

const rows = [
  {
    project: { name: "Buzz Workflow" },
    repository: { name: "Control Room", repoAddress: CONTROL_ROOM },
    issue: { id: "control" },
  },
  {
    project: { name: "PatternDY" },
    repository: { name: "PatternDY", repoAddress: PATTERNDY },
    issue: { id: "pattern" },
  },
];

test("repository filter keeps all issue rows for the all-repositories scope", () => {
  assert.deepEqual(filterIssueRowsByRepository(rows, "all"), rows);
});

test("repository filter keeps only the selected repository's issue rows", () => {
  assert.deepEqual(filterIssueRowsByRepository(rows, PATTERNDY), [rows[1]]);
});

test("repository selector offers all repositories plus disambiguated project labels", () => {
  assert.deepEqual(issueRepositoryScopeOptions(rows), [
    { label: "All repositories", value: "all" },
    { label: "Buzz Workflow / Control Room", value: CONTROL_ROOM },
    { label: "PatternDY / PatternDY", value: PATTERNDY },
  ]);
});

test("repository scope resets to all when its repository is no longer available", () => {
  const options = issueRepositoryScopeOptions([rows[0]]);
  assert.equal(normalizeIssueRepositoryScope(PATTERNDY, options), "all");
  assert.equal(
    normalizeIssueRepositoryScope(CONTROL_ROOM, options),
    CONTROL_ROOM,
  );
});
