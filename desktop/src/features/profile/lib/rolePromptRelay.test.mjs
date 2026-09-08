import assert from "node:assert/strict";
import test from "node:test";

// These imports intentionally fail until the publish/readback contract exists.
const { buildRolePromptDraft, canEditRolePrompt } = await import(
  "./rolePromptRelay.ts"
);

test("owner-only role prompt drafts increment the verified head", async () => {
  assert.equal(canEditRolePrompt(true), true);
  assert.equal(canEditRolePrompt(false), false);

  const draft = await buildRolePromptDraft({
    prompt: "Write focused changes.",
    revision: 7,
    role: "writer",
  });
  assert.deepEqual(draft.tags, [["d", "writer"]]);
  assert.equal(draft.payload.revision, 8);
  assert.equal(draft.payload.role, "writer");
  assert.match(draft.payload.sha256, /^[0-9a-f]{64}$/);
});

test("role prompt drafts reject empty prompt text", async () => {
  await assert.rejects(
    () =>
      buildRolePromptDraft({
        prompt: "   ",
        revision: 1,
        role: "review",
      }),
    /prompt/i,
  );
});
