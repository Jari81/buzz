import assert from "node:assert/strict";
import test from "node:test";

import {
  fromRawPersona,
  listHiddenBuiltinPersonas,
  restoreBuiltinPersonas,
  setBuiltinPersonaHidden,
} from "./tauriPersonas.ts";

function rawPersona(overrides = {}) {
  return {
    id: "persona-1",
    display_name: "Team Analyst",
    avatar_url: null,
    system_prompt: "You are Team Analyst.",
    runtime: null,
    model: null,
    provider: null,
    name_pool: [],
    is_builtin: false,
    is_active: true,
    source_team: null,
    env_vars: {},
    created_at: "2026-01-01T00:00:00.000Z",
    updated_at: "2026-01-01T00:00:00.000Z",
    ...overrides,
  };
}

test("fromRawPersona maps source_team to sourceTeam", () => {
  const persona = fromRawPersona(rawPersona({ source_team: "team-research" }));

  assert.equal(persona.sourceTeam, "team-research");
});

test("built-in visibility APIs use dedicated non-destructive commands", async () => {
  const previousWindow = globalThis.window;
  const calls = [];
  globalThis.window = {
    __TAURI_INTERNALS__: {
      invoke(command, args) {
        calls.push({ command, args });
        if (command === "list_hidden_builtin_personas") {
          return Promise.resolve(["builtin:fizz"]);
        }
        if (command === "set_builtin_persona_hidden") {
          return Promise.resolve(["builtin:fizz", "builtin:honey"]);
        }
        if (command === "restore_builtin_personas") {
          return Promise.resolve([]);
        }
        throw new Error(`Unexpected command: ${command}`);
      },
    },
  };

  try {
    assert.deepEqual(await listHiddenBuiltinPersonas(), ["builtin:fizz"]);
    assert.deepEqual(await setBuiltinPersonaHidden("builtin:honey", true), [
      "builtin:fizz",
      "builtin:honey",
    ]);
    assert.deepEqual(await restoreBuiltinPersonas(), []);
    assert.deepEqual(calls, [
      { command: "list_hidden_builtin_personas", args: {} },
      {
        command: "set_builtin_persona_hidden",
        args: { id: "builtin:honey", hidden: true },
      },
      { command: "restore_builtin_personas", args: {} },
    ]);
  } finally {
    globalThis.window = previousWindow;
  }
});
