import assert from "node:assert/strict";
import test from "node:test";

import {
  awaitRelayModelCatalog,
  presentRelayModelCatalog,
} from "./relayModelCatalog.ts";

test("presentRelayModelCatalog turns unavailable catalogs into an explicit message", () => {
  assert.deepEqual(
    presentRelayModelCatalog({
      type: "list_models",
      requestId: "request-1",
      status: "catalog_unavailable",
      models: [],
    }),
    {
      currentModelId: null,
      models: [],
      message: "Model catalog is not available for this agent yet.",
      truncated: false,
    },
  );
});

test("awaitRelayModelCatalog returns an explicit timeout outcome", async () => {
  let onTimeout = () => {};
  const resultPromise = awaitRelayModelCatalog({
    requestId: "request-timeout",
    subscribe: () => () => {},
    sendRequest: async () => {},
    scheduleTimeout: (listener) => {
      onTimeout = listener;
      return () => {};
    },
  });

  onTimeout();
  const result = await resultPromise;
  assert.equal(result.status, "timeout");
  assert.deepEqual(result.models, undefined);
});

test("awaitRelayModelCatalog resolves only the matching list_models request", async () => {
  const listeners = new Set();
  let unsubscribed = false;
  let timeoutCancelled = false;
  const resultPromise = awaitRelayModelCatalog({
    requestId: "request-1",
    subscribe: (listener) => {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
        unsubscribed = true;
      };
    },
    sendRequest: async () => {},
    scheduleTimeout: () => () => {
      timeoutCancelled = true;
    },
  });

  for (const listener of listeners) {
    listener({
      type: "list_models",
      requestId: "another-request",
      status: "ok",
      models: ["wrong"],
    });
    listener({
      type: "list_models",
      requestId: "request-1",
      status: "ok",
      models: ["anthropic/claude-sonnet-4-5"],
      currentModelId: "anthropic/claude-sonnet-4-5",
      desiredModelId: null,
      totalCount: 1,
      truncated: false,
    });
  }

  const result = await resultPromise;
  assert.equal(result.status, "ok");
  assert.deepEqual(result.models, ["anthropic/claude-sonnet-4-5"]);
  assert.equal(unsubscribed, true);
  assert.equal(timeoutCancelled, true);
});
