import assert from "node:assert/strict";
import { afterEach, test } from "node:test";

import {
  _testNotifySessionConfigCaptured,
  _testProcessLiveObserverEvents,
  resetAgentObserverStore,
  subscribeControlResults,
  subscribeSessionConfigCaptured,
} from "./observerRelayStore.ts";

const AGENT = "a".repeat(64);

function controlResultEvent(overrides = {}) {
  return {
    seq: 1,
    timestamp: "2026-08-28T12:00:00.000Z",
    kind: "control_result",
    agentIndex: 0,
    channelId: "channel-1",
    sessionId: null,
    turnId: null,
    payload: {
      type: "switch_model",
      status: "switched",
      modelId: "model-1",
      requestId: "switch-1",
    },
    ...overrides,
  };
}

afterEach(() => resetAgentObserverStore());

test("session config capture notifies both subscribers and preserves one after the other unsubscribes", () => {
  let firstCalls = 0;
  let secondCalls = 0;
  const unsubscribeFirst = subscribeSessionConfigCaptured(() => {
    firstCalls += 1;
  });
  const unsubscribeSecond = subscribeSessionConfigCaptured(() => {
    secondCalls += 1;
  });

  _testNotifySessionConfigCaptured(AGENT);
  assert.deepEqual([firstCalls, secondCalls], [1, 1]);

  unsubscribeFirst();
  _testNotifySessionConfigCaptured(AGENT);
  unsubscribeSecond();

  assert.deepEqual([firstCalls, secondCalls], [1, 2]);
});

test("live replay dispatches a deduplicated control result only once", () => {
  const received = [];
  const unsubscribe = subscribeControlResults(AGENT, (frame) =>
    received.push(frame),
  );
  const event = controlResultEvent();

  _testProcessLiveObserverEvents(AGENT, [event]);
  _testProcessLiveObserverEvents(AGENT, [event]);

  unsubscribe();
  assert.equal(received.length, 1);
  assert.equal(received[0].requestId, "switch-1");
});
