import assert from "node:assert/strict";
import test from "node:test";

const dialogModule = await import("./AddChannelBotDialog.tsx");

function persona(id, { builtIn = false, active = true } = {}) {
  return {
    id,
    displayName: id,
    avatarUrl: null,
    systemPrompt: `${id} prompt`,
    runtime: null,
    model: null,
    namePool: [],
    isBuiltIn: builtIn,
    isActive: active,
    createdAt: "2026-01-01T00:00:00Z",
    updatedAt: "2026-01-01T00:00:00Z",
  };
}

function team(id, personaIds) {
  return {
    id,
    name: id,
    description: null,
    instructions: null,
    personaIds,
    createdAt: "2026-01-01T00:00:00Z",
    updatedAt: "2026-01-01T00:00:00Z",
  };
}

test("add-channel options exclude hidden built-ins from direct persona selection", () => {
  assert.equal(typeof dialogModule.getAddChannelBotOptions, "function");

  const result = dialogModule.getAddChannelBotOptions(
    [
      persona("builtin:fizz", { builtIn: true }),
      persona("custom:writer"),
      persona("custom:inactive", { active: false }),
    ],
    [],
    new Set(["builtin:fizz"]),
  );

  assert.deepEqual(
    result.personas.map((entry) => entry.id),
    ["custom:writer"],
  );
});

test("add-channel options exclude teams that reference hidden built-ins", () => {
  assert.equal(typeof dialogModule.getAddChannelBotOptions, "function");

  const result = dialogModule.getAddChannelBotOptions(
    [persona("builtin:fizz", { builtIn: true }), persona("custom:writer")],
    [
      team("team:hidden", ["builtin:fizz"]),
      team("team:mixed", ["builtin:fizz", "custom:writer"]),
      team("team:visible", ["custom:writer"]),
    ],
    new Set(["builtin:fizz"]),
  );

  assert.deepEqual(
    result.teams.map((entry) => entry.id),
    ["team:visible"],
  );
});

test("add-channel options fail closed while tombstones are unavailable", () => {
  assert.equal(
    typeof dialogModule.getAddChannelBotOptionsForQueryState,
    "function",
  );

  const personas = [persona("builtin:fizz", { builtIn: true })];
  assert.deepEqual(
    dialogModule.getAddChannelBotOptionsForQueryState(
      personas,
      [],
      undefined,
      null,
      null,
    ),
    { personas: [], teams: [] },
  );
});

test("add-channel options fail closed after a tombstone query error", () => {
  assert.equal(
    typeof dialogModule.getAddChannelBotOptionsForQueryState,
    "function",
  );

  const personas = [persona("builtin:fizz", { builtIn: true })];
  assert.deepEqual(
    dialogModule.getAddChannelBotOptionsForQueryState(
      personas,
      [],
      [],
      null,
      new Error("visibility unavailable"),
    ),
    { personas: [], teams: [] },
  );
});
