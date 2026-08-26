import assert from "node:assert/strict";
import test from "node:test";

import React from "react";
import { renderToStaticMarkup } from "react-dom/server";

const issuesPanelModule = await import("./ChannelIssuesAuxiliaryPanel.tsx");
const channelHeaderModule = await import("./ChannelScreenHeader.tsx");

test("issue panel instance identity follows the active channel", () => {
  assert.equal(
    issuesPanelModule.channelIssuesPanelInstanceKey?.("channel-one"),
    "channel-issues-panel:channel-one",
  );
  assert.notEqual(
    issuesPanelModule.channelIssuesPanelInstanceKey?.("channel-one"),
    issuesPanelModule.channelIssuesPanelInstanceKey?.("channel-two"),
  );
});

test("selected issue header exposes a visible back action", () => {
  const Header = issuesPanelModule.ChannelIssuesPanelHeader;
  assert.equal(typeof Header, "function");

  const html = renderToStaticMarkup(
    React.createElement(Header, {
      onBack() {},
      onClose() {},
      repositoryName: "Control Room",
      selectedIssueId: "issue-one",
    }),
  );

  assert.match(html, /Back to issues/);
  assert.match(html, /aria-label="Back to issues"/);
  assert.match(
    html,
    /class="[^"]*\brelative\b[^"]*\bz-40\b/,
    "panel header must stay above the shared z-30 channel backdrop",
  );
});

test("channel issues action appears before Buzz Terminal", () => {
  const Actions = channelHeaderModule.ChannelHeaderPrimaryActions;
  assert.equal(typeof Actions, "function");

  const html = renderToStaticMarkup(
    React.createElement(Actions, {
      channelActions: React.createElement(
        "button",
        { type: "button" },
        "Members",
      ),
      issuesPanelOpen: false,
      onToggleIssues() {},
      terminalButton: React.createElement(
        "button",
        { "aria-label": "Open Buzz Term", type: "button" },
        "Terminal",
      ),
    }),
  );

  assert.ok(
    html.indexOf("Open channel issues") < html.indexOf("Open Buzz Term"),
    "issues action must render before Buzz Terminal",
  );
});
