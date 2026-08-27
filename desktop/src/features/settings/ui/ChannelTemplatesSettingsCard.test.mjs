import assert from "node:assert/strict";
import test from "node:test";

const settingsModule = await import("./ChannelTemplatesSettingsCard.tsx");

function persona(id, { builtIn = false } = {}) {
  return {
    id,
    displayName: id,
    description: "",
    systemPrompt: "",
    tags: [],
    respondTo: "owner-only",
    allowedAuthorPubkeys: [],
    isBuiltIn: builtIn,
    isActive: true,
    createdAt: 1,
    updatedAt: 1,
  };
}

function team(id, personaIds) {
  return {
    id,
    name: id,
    description: "",
    instructions: null,
    personaIds,
    createdAt: 1,
    updatedAt: 1,
  };
}

test("channel template options exclude hidden personas and teams that reference them", () => {
  assert.equal(
    typeof settingsModule.getChannelTemplateAgentOptions,
    "function",
  );

  const hidden = persona("builtin:hidden", { builtIn: true });
  const visible = persona("custom:visible");
  const options = settingsModule.getChannelTemplateAgentOptions(
    [hidden, visible],
    [
      team("team:mixed", [visible.id, hidden.id]),
      team("team:visible", [visible.id]),
    ],
    new Set([hidden.id]),
  );

  assert.deepEqual(
    options.personas.map((entry) => entry.id),
    [visible.id],
  );
  assert.deepEqual(
    options.teams.map((entry) => entry.id),
    ["team:visible"],
  );
});

test("channel template options fail closed after a tombstone query error", () => {
  assert.equal(
    typeof settingsModule.getChannelTemplateAgentOptionsForQueryState,
    "function",
  );

  const hidden = persona("builtin:hidden", { builtIn: true });
  assert.deepEqual(
    settingsModule.getChannelTemplateAgentOptionsForQueryState(
      [hidden],
      [],
      [],
      null,
      new Error("visibility unavailable"),
    ),
    { personas: [], teams: [] },
  );
});
