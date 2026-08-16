import assert from "node:assert/strict";
import test from "node:test";

import {
  getWorkflowCardLabel,
  getWorkflowDisplayStatus,
  withWorkflowEnabled,
} from "./workflowDefinition.ts";

test("builds restrained plain-language workflow card labels", () => {
  assert.equal(
    getWorkflowCardLabel({
      trigger: { on: "message_posted" },
      steps: [{ action: "send_message", text: "Deploying now" }],
    }),
    "When a message is posted, send a channel message",
  );
  assert.equal(
    getWorkflowCardLabel({
      trigger: { on: "reaction_added", emoji: "🔥" },
      steps: [
        { action: "delay", duration: "5m" },
        { action: "add_reaction", emoji: "✅" },
      ],
    }),
    "When someone reacts with 🔥, wait 5m, then 1 more step",
  );
  assert.equal(
    getWorkflowCardLabel({
      trigger: { on: "schedule", cron: "30 9 * * *" },
      steps: [{ action: "call_webhook" }],
    }),
    "On a schedule, call a webhook",
  );
  assert.equal(getWorkflowCardLabel({}), "When this workflow starts");
});

test("updates enabled state without mutating the workflow definition", () => {
  const definition = {
    name: "deploy",
    trigger: { on: "message_posted" },
  };
  const disabled = withWorkflowEnabled(definition, false);

  assert.deepEqual(disabled, { ...definition, enabled: false });
  assert.deepEqual(definition, {
    name: "deploy",
    trigger: { on: "message_posted" },
  });
  assert.deepEqual(withWorkflowEnabled(disabled, true), definition);
});

test("shows a disabled definition as disabled while preserving other statuses", () => {
  const workflow = {
    id: "workflow-id",
    name: "deploy",
    channelId: "channel-id",
    definition: { enabled: false },
    status: "active",
    createdAt: 1,
    updatedAt: 1,
  };

  assert.equal(getWorkflowDisplayStatus(workflow), "disabled");
  assert.equal(
    getWorkflowDisplayStatus({ ...workflow, status: "archived" }),
    "archived",
  );
});
