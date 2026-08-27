import assert from "node:assert/strict";
import test from "node:test";

import { buildUnifiedGroups } from "./unifiedAgentGroups.ts";

function persona(id) {
  return { id };
}

function agent(pubkey, personaId) {
  return { pubkey, personaId };
}

test("hidden starter-agent instances stay persisted but leave the normal agent groups", () => {
  const result = buildUnifiedGroups(
    [persona("custom:writer")],
    [
      agent("fizz-pubkey", "builtin:fizz"),
      agent("writer-pubkey", "custom:writer"),
    ],
    new Set(["builtin:fizz"]),
  );

  assert.deepEqual(
    result.groups.map((group) => ({
      personaId: group.persona.id,
      agentPubkeys: group.agents.map((entry) => entry.pubkey),
    })),
    [{ personaId: "custom:writer", agentPubkeys: ["writer-pubkey"] }],
  );
  assert.deepEqual(result.unknown, []);
  assert.deepEqual(result.ungrouped, []);
});
