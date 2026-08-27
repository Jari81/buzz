#!/usr/bin/env bash
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

build16=1a3084e4d3a7a93492ac9a82ebdfffb40c2def39
build17=984bec51866fa750ae0dbea0a8ccd6f76c9d6d15
merged_tree=$(git merge-tree --write-tree "$build16" "$build17")
candidate_tree=$(git write-tree)

expect_failure() {
  local label=$1
  shift
  if "$@" >/dev/null 2>&1; then
    printf 'FAIL: %s unexpectedly passed\n' "$label" >&2
    exit 1
  fi
  printf 'PASS: %s rejected\n' "$label"
}

expect_success() {
  local label=$1
  shift
  if ! "$@"; then
    printf 'FAIL: %s unexpectedly failed\n' "$label" >&2
    exit 1
  fi
  printf 'PASS: %s accepted\n' "$label"
}

expect_failure \
  'Build 16 alone lacks the new cumulative client contract' \
  scripts/check-windows-client-contract.sh "$build16"
expect_failure \
  'Build 17 alone dropped the previous client contract' \
  scripts/check-windows-client-contract.sh "$build17"
stress_candidate_contract() {
  local iteration
  for iteration in {1..100}; do
    scripts/check-windows-client-contract.sh "$candidate_tree" >/dev/null
  done
}

expect_failure \
  'the raw Build 16 + Build 17 tree lacks the reviewed writer-consistency fix' \
  scripts/check-windows-client-contract.sh "$merged_tree"
expect_success \
  'the corrected cumulative candidate retains every contract repeatedly' \
  stress_candidate_contract

expect_failure \
  'a sibling candidate is not cumulative' \
  scripts/verify-windows-client-lineage.sh \
    "$build16" "$build17" windows-integration
expect_failure \
  'a build from a non-canonical branch is forbidden' \
  scripts/verify-windows-client-lineage.sh \
    "$build16" "$build16" fix/windows-client-batch-20260826
expect_success \
  'a descendant on the canonical branch is cumulative' \
  scripts/verify-windows-client-lineage.sh \
    "$build16" "$build16" windows-integration

workflow=.github/workflows/windows-fork-integration.yml
grep -Fq 'CANONICAL_WINDOWS_BRANCH: windows-integration' "$workflow"
grep -Fq \
  'WINDOWS_INTEGRATION_BOOTSTRAP_SHA: 1a3084e4d3a7a93492ac9a82ebdfffb40c2def39' \
  "$workflow"
grep -Fq 'branch=${CANONICAL_WINDOWS_BRANCH}' "$workflow"
grep -Fq 'scripts/verify-windows-client-lineage.sh' "$workflow"
grep -Fq 'scripts/check-windows-client-contract.sh' "$workflow"
printf 'PASS: GitHub workflow invokes both fail-closed gates\n'
