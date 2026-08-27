import assert from "node:assert/strict";
import test from "node:test";

import { visibleLibraryPersonas } from "./builtinVisibility.ts";

function persona(id, isBuiltIn) {
  return { id, isBuiltIn };
}

test("hidden starter agents disappear while custom and managed agents stay visible", () => {
  const personas = [
    persona("builtin:fizz", true),
    persona("builtin:honey", true),
    persona("custom:writer", false),
  ];
  const agents = [{ personaId: "builtin:honey" }];

  const visible = visibleLibraryPersonas(
    personas,
    agents,
    new Set(["builtin:fizz", "builtin:honey", "custom:writer"]),
  );

  assert.deepEqual(
    visible.map((entry) => entry.id),
    ["builtin:honey", "custom:writer"],
  );
});
