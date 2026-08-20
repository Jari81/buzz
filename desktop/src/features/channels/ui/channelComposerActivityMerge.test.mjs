import assert from "node:assert/strict";
import test from "node:test";

import { mergeThreadComposerActivityPubkeys } from "./channelComposerActivityMerge.ts";

test("returns thread typing when no channel-level working set exists", () => {
  assert.deepEqual(mergeThreadComposerActivityPubkeys(["aaaa"], []), ["aaaa"]);
});

test("adds channel-level working pubkeys so threads get the activity bar", () => {
  assert.deepEqual(mergeThreadComposerActivityPubkeys([], ["bbbb"]), ["bbbb"]);
});

test("merges both sources and dedupes case-insensitively, thread order first", () => {
  assert.deepEqual(
    mergeThreadComposerActivityPubkeys(["AAAA"], ["aaaa", "cccc"]),
    ["AAAA", "cccc"],
  );
});

test("empty inputs yield an empty list", () => {
  assert.deepEqual(mergeThreadComposerActivityPubkeys([], []), []);
});
