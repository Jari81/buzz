import assert from "node:assert/strict";
import test from "node:test";

import {
  buildListModelsControl,
  buildSwitchModelControl,
} from "./agentControl.ts";

test("buildListModelsControl carries the request correlation id", () => {
  assert.deepEqual(buildListModelsControl("catalog-1"), {
    type: "list_models",
    requestId: "catalog-1",
  });
});

test("buildSwitchModelControl scopes the switch to one conversation", () => {
  assert.deepEqual(
    buildSwitchModelControl(
      [{ channelId: "channel-1", conversationRoot: "thread-root-1" }],
      "anthropic/claude-sonnet-4-5",
      "switch-1",
    ),
    {
      type: "switch_model",
      modelId: "anthropic/claude-sonnet-4-5",
      requestId: "switch-1",
      targets: [
        {
          channelId: "channel-1",
          conversationRoot: "thread-root-1",
        },
      ],
    },
  );
});

test("multi-turn model switch builds and sends one atomic control frame", async () => {
  const targets = [
    { channelId: "channel-1", conversationRoot: "thread-root-1" },
    { channelId: "channel-2", conversationRoot: null },
  ];
  const expected = {
    type: "switch_model",
    modelId: "anthropic/claude-sonnet-4-5",
    requestId: "switch-aggregate-1",
    targets: [
      { channelId: "channel-1", conversationRoot: "thread-root-1" },
      { channelId: "channel-2" },
    ],
  };

  assert.deepEqual(
    buildSwitchModelControl(
      targets,
      "anthropic/claude-sonnet-4-5",
      "switch-aggregate-1",
    ),
    expected,
  );

  const api = await import("./agentControl.ts");
  assert.equal(
    typeof api.sendSwitchModelControl,
    "function",
    "the caller must have one send seam for the aggregate frame",
  );
  const sends = [];
  await api.sendSwitchModelControl(
    async (pubkey, payload) => sends.push({ pubkey, payload }),
    "agent-pubkey",
    targets,
    "anthropic/claude-sonnet-4-5",
    "switch-aggregate-1",
  );
  assert.deepEqual(sends, [{ pubkey: "agent-pubkey", payload: expected }]);
});
