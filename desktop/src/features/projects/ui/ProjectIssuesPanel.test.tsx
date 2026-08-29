// @ts-nocheck
import assert from "node:assert/strict";
import test from "node:test";

import { reviewSectionState } from "./ProjectIssuesPanel.tsx";

const OWNER = "a".repeat(64);
const TESTER = "b".repeat(64);
const OTHER = "c".repeat(64);

function issueWithVerdict(verdict = null) {
  return {
    currentReview: {
      authorizedHumanPubkeys: [OWNER, TESTER],
      evidence: "focused tests",
      id: "review-42",
      limitations: "none",
      rootId: "1".repeat(64),
      target: "immutable target",
      test: "open the issue",
      verdict,
    },
  };
}

test("review section is read-only except for configured human verdict actors", () => {
  const issue = issueWithVerdict();

  assert.equal(reviewSectionState(issue, OWNER).canSubmit, true);
  assert.equal(reviewSectionState(issue, TESTER).canSubmit, true);
  assert.equal(reviewSectionState(issue, OTHER).canSubmit, false);
  assert.equal(reviewSectionState({ currentReview: null }, OWNER), null);
});

test("pending raw verdict shows awaiting confirmation and disables repeat actions", () => {
  const pending = reviewSectionState(
    issueWithVerdict({
      actorPubkey: OWNER,
      confirmation: null,
      createdAt: 300,
      eventId: "2".repeat(64),
      kind: "accepted",
      reason: null,
    }),
    OWNER,
  );

  assert.equal(pending.canSubmit, false);
  assert.equal(
    pending.message,
    "Urteil gesendet – Workflow-Bestätigung ausstehend",
  );
});

test("trusted confirmations expose accepted and rejected success semantics", () => {
  const accepted = reviewSectionState(
    issueWithVerdict({
      actorPubkey: OWNER,
      confirmation: {
        createdAt: 350,
        eventId: "3".repeat(64),
        kanbanStatus: "done",
      },
      createdAt: 300,
      eventId: "2".repeat(64),
      kind: "accepted",
      reason: null,
    }),
    OWNER,
  );
  const rejected = reviewSectionState(
    issueWithVerdict({
      actorPubkey: OWNER,
      confirmation: {
        createdAt: 350,
        eventId: "4".repeat(64),
        kanbanStatus: "ready",
      },
      createdAt: 300,
      eventId: "2".repeat(64),
      kind: "rejected",
      reason: "Needs changes",
    }),
    OWNER,
  );

  assert.equal(accepted.canSubmit, false);
  assert.equal(accepted.message, "Abnahme übernommen");
  assert.equal(rejected.canSubmit, false);
  assert.equal(rejected.message, "Zur Nacharbeit zurückgegeben");
});

test("send failure reports failure but re-enables actions for retry", () => {
  const failed = reviewSectionState(issueWithVerdict(), OWNER, "failed");

  assert.equal(failed.canSubmit, true);
  assert.equal(
    failed.message,
    "Urteil konnte nicht gesendet werden. Bitte erneut versuchen.",
  );
});
