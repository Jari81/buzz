#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'usage: %s <candidate-treeish>\n' "$0" >&2
  exit 2
fi

candidate=$1

require_path() {
  local path=$1
  if ! git cat-file -e "${candidate}:${path}" 2>/dev/null; then
    printf 'windows client contract missing path: %s\n' "$path" >&2
    exit 1
  fi
}

require_text() {
  local path=$1
  local marker=$2
  require_path "$path"
  if ! git show "${candidate}:${path}" | grep -F "$marker" >/dev/null; then
    printf 'windows client contract missing marker %q in %s\n' \
      "$marker" "$path" >&2
    exit 1
  fi
}

# Cumulative surfaces already delivered to the Windows owner client.
require_path 'desktop/src/features/agent-sessions'
require_text \
  'desktop/src/features/channels/ui/ChannelScreenHeader.tsx' \
  'data-testid="channel-issues-trigger"'
require_text \
  'desktop/src/features/channels/ui/ChannelIssuesAuxiliaryPanel.tsx' \
  'testId="channel-issues-auxiliary-pane"'
require_text \
  'desktop/src/features/channels/ui/ChannelIssuesAuxiliaryPanel.test.mjs' \
  'channel issues action appears before Buzz Terminal'
require_path 'desktop/src/features/projects/issueRepositoryScope.ts'
require_text \
  'desktop/src/features/projects/ui/ProjectIssuesPanel.tsx' \
  'aria-label="Change issue status"'
require_text \
  'desktop/src/features/agents/ui/PersonaActionsMenu.tsx' \
  'Hide starter agent'
require_text \
  'desktop/src/features/channels/useChannelPaneHandlers.test.mjs' \
  'clicking the already open thread keeps it open'
require_text \
  'crates/buzz-cli/src/commands/issues.rs' \
  'writer_consistent'
require_text \
  'crates/buzz-cli/src/commands/issues.rs' \
  'assignment_context_queries_are_writer_consistent'
require_text \
  'crates/buzz-relay/src/handlers/req.rs' \
  'issue_comment_reads_that_feed_assignment_causality_require_writer'

printf 'windows client cumulative contract: OK (%s)\n' "$candidate"
