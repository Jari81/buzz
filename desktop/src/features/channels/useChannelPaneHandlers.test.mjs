import assert from "node:assert/strict";
import test from "node:test";
import * as React from "react";
import { JSDOM } from "jsdom";

import { useChannelPaneHandlers } from "./useChannelPaneHandlers.ts";

function useThreadHarness(initialOpenThreadHeadId) {
  const [openThreadHeadId, commitOpenThreadHeadId] = React.useState(
    initialOpenThreadHeadId,
  );
  const openThreadCommitsRef = React.useRef([]);
  const setOpenThreadHeadId = React.useCallback((value) => {
    openThreadCommitsRef.current.push(value);
    commitOpenThreadHeadId(value);
  }, []);
  const [optimisticOpenThreadHeadId, setOptimisticOpenThreadHeadId] =
    React.useState(undefined);
  const [threadReplyTargetId, setThreadReplyTargetId] = React.useState(null);
  const [, setThreadScrollTargetId] = React.useState(null);
  const [expandedThreadReplyIds, setExpandedThreadReplyIds] = React.useState(
    new Set(),
  );
  const [editTargetId, setEditTargetId] = React.useState(null);

  const handlers = useChannelPaneHandlers({
    deleteMessageMutation: { mutateAsync: async () => {} },
    editMessageMutation: { mutateAsync: async () => {} },
    editTargetId,
    expandedThreadReplyIds,
    getFirstReplyIdForMessage: () => null,
    getReplyDescendantIdsForMessage: () => [],
    markRevealedRepliesRead: () => {},
    profiles: undefined,
    recordThreadInteraction: () => {},
    onOptimisticOpenThreadHeadIdChange: setOptimisticOpenThreadHeadId,
    onRequestEmptyEditDelete: () => {},
    openThreadHeadId,
    sendMessageMutation: { mutateAsync: async () => {} },
    setExpandedThreadReplyIds,
    setEditTargetId,
    setOpenThreadHeadId,
    setThreadReplyTargetId,
    setThreadScrollTargetId,
    threadReplyTargetId,
    toggleReactionMutation: { mutateAsync: async () => {} },
  });

  return {
    handlers,
    openThreadHeadId,
    openThreadCommits: openThreadCommitsRef.current,
    optimisticOpenThreadHeadId,
  };
}

async function withRenderedHarness(initialOpenThreadHeadId, assertion) {
  const dom = new JSDOM("<!doctype html><html><body></body></html>", {
    url: "http://localhost",
  });
  Object.assign(globalThis, {
    document: dom.window.document,
    HTMLElement: dom.window.HTMLElement,
    IS_REACT_ACT_ENVIRONMENT: true,
    window: dom.window,
  });
  const { act, cleanup, renderHook } = await import("@testing-library/react");

  try {
    const hook = renderHook(() => useThreadHarness(initialOpenThreadHeadId));
    await assertion({ act, hook });
  } finally {
    cleanup();
    dom.window.close();
  }
}

test("clicking the already open thread keeps it open", async () => {
  await withRenderedHarness("thread-a", async ({ act, hook }) => {
    await act(async () => {
      hook.result.current.handlers.handleOpenThread({ id: "thread-a" });
      await new Promise((resolve) => setTimeout(resolve, 0));
    });

    assert.equal(hook.result.current.openThreadHeadId, "thread-a");
    assert.equal(hook.result.current.optimisticOpenThreadHeadId, "thread-a");
  });
});

test("clicking a different thread switches the open sidepanel", async () => {
  await withRenderedHarness("thread-a", async ({ act, hook }) => {
    await act(async () => {
      hook.result.current.handlers.handleOpenThread({ id: "thread-b" });
      await new Promise((resolve) => setTimeout(resolve, 0));
    });

    assert.equal(hook.result.current.openThreadHeadId, "thread-b");
    assert.equal(hook.result.current.optimisticOpenThreadHeadId, "thread-b");
  });
});

test("rapid thread clicks commit only the latest sidepanel", async () => {
  await withRenderedHarness("thread-a", async ({ act, hook }) => {
    await act(async () => {
      hook.result.current.handlers.handleOpenThread({ id: "thread-b" });
      hook.result.current.handlers.handleOpenThread({ id: "thread-c" });
      await new Promise((resolve) => setTimeout(resolve, 0));
    });

    assert.deepEqual(hook.result.current.openThreadCommits, ["thread-c"]);
    assert.equal(hook.result.current.openThreadHeadId, "thread-c");
  });
});
