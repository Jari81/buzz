import assert from "node:assert/strict";
import test from "node:test";

const visibilityModule = await import("./builtinVisibility.ts");

function persona(id, isBuiltIn) {
  return { id, isBuiltIn };
}

test("hidden starter agents disappear while custom agents stay visible", () => {
  const personas = [
    persona("builtin:fizz", true),
    persona("builtin:honey", true),
    persona("custom:writer", false),
  ];

  const visible = visibilityModule.visibleLibraryPersonas(
    personas,
    new Set(["builtin:fizz", "builtin:honey", "custom:writer"]),
  );

  assert.deepEqual(
    visible.map((entry) => entry.id),
    ["custom:writer"],
  );
});

test("persona visibility is authoritative only after both queries succeed", () => {
  assert.equal(
    typeof visibilityModule.isPersonaVisibilityAuthoritative,
    "function",
  );

  const authoritative = visibilityModule.isPersonaVisibilityAuthoritative;
  assert.equal(authoritative([], [], null, null), true);
  assert.equal(authoritative(undefined, [], null, null), false);
  assert.equal(authoritative([], undefined, null, null), false);
  assert.equal(authoritative([], [], new Error("personas"), null), false);
  assert.equal(authoritative([], [], null, new Error("visibility")), false);
});
