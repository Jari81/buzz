import assert from "node:assert/strict";
import test from "node:test";

import { oaOwnerQueryKey } from "./hooks.ts";

const TARGET = "a".repeat(64);
const FIRST_VIEWER = "b".repeat(64);
const SECOND_VIEWER = "c".repeat(64);

test("OA owner cache key changes with the viewer identity", () => {
  const first = oaOwnerQueryKey(
    TARGET.toUpperCase(),
    FIRST_VIEWER.toUpperCase(),
  );
  const second = oaOwnerQueryKey(TARGET, SECOND_VIEWER);

  assert.deepEqual(first, ["oaOwner", TARGET, FIRST_VIEWER]);
  assert.deepEqual(second, ["oaOwner", TARGET, SECOND_VIEWER]);
  assert.notDeepEqual(first, second);
});
