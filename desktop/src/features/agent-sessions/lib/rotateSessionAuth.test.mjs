import assert from "node:assert/strict";
import test from "node:test";

import { isRotateSessionAuthorized } from "./rotateSessionAuth.ts";

const OWNER = "dd57c78422bccf568feb2a7ae5bcf4d7ebefc2c6c54bf56a26faeb9e0b08d36b";
const SIBLING = "1af26bb78ad6313ca562eed7bec2c72f69ceacce968fb06b92de0aad26901ada";
const STRANGER = "0000000000000000000000000000000000000000000000000000000000000001";
const AGENT = "8df15208c09bccecce4d77cbf73874fbaf1441f4a7747925e5e62e422d9f0a1b";

const directory = [
  { pubkey: AGENT, respondToAllowlist: [OWNER, SIBLING] },
];

test("owner in the allowlist is authorized", () => {
  assert.equal(isRotateSessionAuthorized(directory, OWNER, AGENT), true);
});

test("allowlisted sibling is authorized", () => {
  assert.equal(isRotateSessionAuthorized(directory, SIBLING, AGENT), true);
});

test("stranger outside the allowlist is denied", () => {
  assert.equal(isRotateSessionAuthorized(directory, STRANGER, AGENT), false);
});

test("no current identity is denied", () => {
  assert.equal(isRotateSessionAuthorized(directory, null, AGENT), false);
});

test("agent without a directory record stays ungated", () => {
  assert.equal(isRotateSessionAuthorized(directory, STRANGER, STRANGER), true);
});

test("missing directory query stays ungated (local managed agents)", () => {
  assert.equal(isRotateSessionAuthorized(undefined, STRANGER, AGENT), true);
});

test("pubkey comparison is case-insensitive", () => {
  assert.equal(
    isRotateSessionAuthorized(directory, OWNER.toUpperCase(), AGENT.toUpperCase()),
    true,
  );
});

test("empty allowlist denies everyone (harness stays owner-authoritative)", () => {
  const empty = [{ pubkey: AGENT, respondToAllowlist: [] }];
  assert.equal(isRotateSessionAuthorized(empty, OWNER, AGENT), false);
});
