import assert from "node:assert/strict";
import test from "node:test";

function createStorage() {
  const store = new Map();
  return {
    getItem: (key) => (store.has(key) ? store.get(key) : null),
    setItem: (key, value) => store.set(key, String(value)),
    removeItem: (key) => store.delete(key),
  };
}

let loadSequence = 0;

async function loadModule() {
  globalThis.window = { localStorage: createStorage() };
  loadSequence += 1;
  return import(`./killedAgentSessions.ts?test=${Date.now()}-${loadSequence}`);
}

const IDENTITY_A = "1".repeat(64);
const IDENTITY_B = "2".repeat(64);
const SESSION_1 = "s".repeat(64);
const SESSION_2 = "t".repeat(64);

test("nothing is killed by default", async () => {
  const { readKilledAgentSessions } = await loadModule();
  assert.equal(readKilledAgentSessions(IDENTITY_A).size, 0);
});

test("a killed session is recorded and read back", async () => {
  const { readKilledAgentSessions, recordKilledAgentSession } =
    await loadModule();
  recordKilledAgentSession(IDENTITY_A, SESSION_1);
  assert.deepEqual([...readKilledAgentSessions(IDENTITY_A)], [SESSION_1]);
});

test("recording the same session twice keeps a single entry", async () => {
  const { readKilledAgentSessions, recordKilledAgentSession } =
    await loadModule();
  recordKilledAgentSession(IDENTITY_A, SESSION_1);
  recordKilledAgentSession(IDENTITY_A, SESSION_1);
  assert.equal(readKilledAgentSessions(IDENTITY_A).size, 1);
});

test("kills are scoped per identity", async () => {
  const { readKilledAgentSessions, recordKilledAgentSession } =
    await loadModule();
  recordKilledAgentSession(IDENTITY_A, SESSION_1);
  recordKilledAgentSession(IDENTITY_B, SESSION_2);
  assert.deepEqual([...readKilledAgentSessions(IDENTITY_A)], [SESSION_1]);
  assert.deepEqual([...readKilledAgentSessions(IDENTITY_B)], [SESSION_2]);
});

test("a missing identity reads as nothing killed", async () => {
  const { readKilledAgentSessions, recordKilledAgentSession } =
    await loadModule();
  recordKilledAgentSession(IDENTITY_A, SESSION_1);
  assert.equal(readKilledAgentSessions(null).size, 0);
  // Recording without an identity is a no-op, never a crash.
  recordKilledAgentSession(null, SESSION_1);
  assert.equal(readKilledAgentSessions(IDENTITY_A).size, 1);
});

test("corrupt storage reads as nothing killed", async () => {
  const { readKilledAgentSessions } = await loadModule();
  window.localStorage.setItem(
    `buzz:killed-agent-sessions:${IDENTITY_A}`,
    "{not json",
  );
  assert.equal(readKilledAgentSessions(IDENTITY_A).size, 0);
});
