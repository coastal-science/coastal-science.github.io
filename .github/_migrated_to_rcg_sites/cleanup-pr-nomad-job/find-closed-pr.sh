#!/usr/bin/env bash
# Resolve a closed pull request number for a deleted head branch.
# Used by cleanup-pr-nomad-on-delete.yml. Runnable locally with a stub gh on PATH.
#
# Required env: DELETED_REF, GITHUB_REPOSITORY, GITHUB_REPOSITORY_OWNER, GITHUB_OUTPUT
set -euo pipefail

if [ -z "${DELETED_REF:-}" ] || [ -z "${GITHUB_REPOSITORY:-}" ] || [ -z "${GITHUB_REPOSITORY_OWNER:-}" ]; then
  echo "::error::DELETED_REF, GITHUB_REPOSITORY, and GITHUB_REPOSITORY_OWNER are required."
  exit 1
fi
if [ -z "${GITHUB_OUTPUT:-}" ]; then
  echo "::error::GITHUB_OUTPUT is required."
  exit 1
fi

# delete payload `ref` is the branch name (e.g. cms/collection/slug), not refs/heads/...
PAYLOAD=$(gh api \
  "repos/${GITHUB_REPOSITORY}/pulls" \
  -f head="${GITHUB_REPOSITORY_OWNER}:${DELETED_REF}" \
  -f state=closed \
  -F per_page=1 \
  --jq '.[0] // empty' 2>/dev/null || true)
PR_NUM=$(echo "$PAYLOAD" | jq -r '.number // empty' 2>/dev/null)

if [ -n "${PR_NUM}" ]; then
  echo "pr_number=${PR_NUM}" >> "$GITHUB_OUTPUT"
  echo "Found closed PR #${PR_NUM} for deleted branch ${DELETED_REF}"
else
  echo "pr_number=" >> "$GITHUB_OUTPUT"
  echo "No closed PR for deleted branch ${DELETED_REF}; skipping Nomad cleanup."
fi
