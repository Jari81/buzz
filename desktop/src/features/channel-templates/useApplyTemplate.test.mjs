import assert from "node:assert/strict";
import test from "node:test";

const applyTemplateModule = await import("./useApplyTemplate.ts");

function persona(id, { builtIn = false, active = true } = {}) {
  return {
    id,
    displayName: id,
    description: "",
    systemPrompt: "",
    tags: [],
    defaultBackend: null,
    defaultRuntime: null,
    defaultModel: null,
    defaultEffort: null,
    respondTo: "owner-only",
    allowedAuthorPubkeys: [],
    isBuiltIn: builtIn,
    isActive: active,
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

test("template execution excludes hidden personas and teams that reference them", () => {
  assert.equal(
    typeof applyTemplateModule.resolveTemplateAgentEntries,
    "function",
  );

  const hidden = persona("builtin:hidden", { builtIn: true });
  const direct = persona("custom:direct");
  const teamMember = persona("custom:team-member");
  const personas = [hidden, direct, teamMember];
  const teams = [
    team("team:mixed", [teamMember.id, hidden.id]),
    team("team:visible", [teamMember.id]),
  ];
  const templateAgents = {
    personas: [
      {
        personaId: hidden.id,
        runtime: null,
        model: null,
        effort: null,
        backend: null,
      },
      {
        personaId: direct.id,
        runtime: null,
        model: null,
        effort: null,
        backend: null,
      },
    ],
    teams: [
      {
        teamId: "team:mixed",
        runtime: null,
        model: null,
        effort: null,
        backend: null,
      },
      {
        teamId: "team:visible",
        runtime: null,
        model: null,
        effort: null,
        backend: null,
      },
    ],
  };

  const result = applyTemplateModule.resolveTemplateAgentEntries(
    templateAgents,
    personas,
    teams,
    new Set([hidden.id]),
  );

  assert.deepEqual(
    result.map((entry) => entry.persona.id),
    [direct.id, teamMember.id],
  );
});
