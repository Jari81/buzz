import assert from "node:assert/strict";
import test from "node:test";

import { resolveContextWindow } from "./modelContextLimits.ts";

test("exact model match resolves the table value", () => {
  assert.equal(resolveContextWindow("claude-sonnet-4-20250514"), 200_000);
  assert.equal(resolveContextWindow("gpt-4o"), 128_000);
});

test("match is case-insensitive and trims whitespace", () => {
  assert.equal(resolveContextWindow("  CLAUDE-SONNET-4-20250514 "), 200_000);
});

test("provider prefixes are stripped before lookup", () => {
  assert.equal(
    resolveContextWindow("anthropic/claude-sonnet-4-20250514"),
    200_000,
  );
  assert.equal(resolveContextWindow("openai/gpt-4o"), 128_000);
  assert.equal(resolveContextWindow("alibaba-token-plan/qwen3.8-max"), 131_072);
});

test("prefix match resolves dated model variants", () => {
  assert.equal(
    resolveContextWindow("qwen3-coder-480b-a35b-instruct-2025"),
    262_144,
  );
});

test("unknown models fall back to the default window", () => {
  assert.equal(resolveContextWindow("some-brand-new-model"), 200_000);
  assert.equal(resolveContextWindow(null), 200_000);
  assert.equal(resolveContextWindow(undefined), 200_000);
});

test("observed usage above the table value promotes to 1M", () => {
  // claude-sonnet-4 is 200k in the table; a turn that already used 250k
  // proves a larger window — promote.
  assert.equal(
    resolveContextWindow("claude-sonnet-4-20250514", 250_000),
    1_048_576,
  );
});

test("observed usage at or below the table value keeps the table value", () => {
  assert.equal(
    resolveContextWindow("claude-sonnet-4-20250514", 150_000),
    200_000,
  );
  assert.equal(
    resolveContextWindow("claude-sonnet-4-20250514", 200_000),
    200_000,
  );
});
