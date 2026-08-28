import assert from "node:assert/strict";
import test from "node:test";
import React from "react";
import { renderToStaticMarkup } from "react-dom/server";

import { RelayAgentModelPicker } from "./RelayAgentModelPicker.tsx";
import {
  filterBotActivityTranscript,
  relayAgentModelPickerKey,
} from "../../channels/ui/BotActivityBar.tsx";

test("relay model picker remount key changes with agent and conversation context", () => {
  const base = relayAgentModelPickerKey("agent-a", "channel-1", "thread-1");
  assert.notEqual(
    base,
    relayAgentModelPickerKey("agent-b", "channel-1", "thread-1"),
  );
  assert.notEqual(
    base,
    relayAgentModelPickerKey("agent-a", "channel-2", "thread-1"),
  );
  assert.notEqual(
    base,
    relayAgentModelPickerKey("agent-a", "channel-1", "thread-2"),
  );
  assert.equal(
    relayAgentModelPickerKey("agent-a", "channel-1", null),
    relayAgentModelPickerKey("agent-a", "channel-1", null),
  );
});

test("thread activity transcript excludes siblings and keeps rootless legacy fallback", () => {
  const transcript = [
    { id: "thread-a", channelId: "channel-1", conversationRoot: "thread-a" },
    { id: "thread-b", channelId: "channel-1", conversationRoot: "thread-b" },
    { id: "legacy", channelId: "channel-1", conversationRoot: null },
    {
      id: "other-channel",
      channelId: "channel-2",
      conversationRoot: "thread-a",
    },
  ];

  assert.deepEqual(
    filterBotActivityTranscript(transcript, "channel-1", "thread-a").map(
      (item) => item.id,
    ),
    ["thread-a", "legacy"],
  );
  assert.deepEqual(
    filterBotActivityTranscript(transcript, "channel-1", null).map(
      (item) => item.id,
    ),
    ["thread-a", "thread-b", "legacy"],
  );
});

test("RelayAgentModelPicker renders an explicit accessible model control", () => {
  const html = renderToStaticMarkup(
    React.createElement(RelayAgentModelPicker, {
      agentPubkey: "a".repeat(64),
      channelId: "channel-1",
      conversationRoot: "thread-1",
    }),
  );

  assert.match(html, /aria-label="Change model for this agent"/);
  assert.match(html, />Model</);
});
