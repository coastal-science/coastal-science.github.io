#!/usr/bin/env bash
# Stop and purge Nomad jobs whose IDs start with JOB_NAME (full ID or prefix).
# Invoked by action.yml. Runnable locally with a stub nomad on PATH.
#
# Required env: JOB_NAME, NOMAD_NAMESPACE, GITHUB_OUTPUT
# Optional env: SLEEP_SECONDS (default 5), ALLOW_MISSING (default false)
# Nomad CLI uses: NOMAD_TOKEN, NOMAD_ADDR, NOMAD_NAMESPACE
set -euo pipefail

SLEEP_SECONDS="${SLEEP_SECONDS:-5}"
ALLOW_MISSING="${ALLOW_MISSING:-false}"

if [ -z "${JOB_NAME:-}" ]; then
  echo "::error::JOB_NAME is required."
  exit 1
fi
if [ -z "${NOMAD_NAMESPACE:-}" ]; then
  echo "::error::NOMAD_NAMESPACE is required."
  exit 1
fi
if [ -z "${GITHUB_OUTPUT:-}" ]; then
  echo "::error::GITHUB_OUTPUT is required."
  exit 1
fi

stop_one() {
  local job="$1"
  echo "Stopping Nomad job: ${job} (namespace: ${NOMAD_NAMESPACE})"
  set +e
  STOP_OUTPUT=$(nomad job stop -purge -verbose "${job}" 2>&1)
  STOP_EXIT=$?
  set -e
  printf '%s\n' "${STOP_OUTPUT}"

  # "Job not found" is a failure. "Already gone" is success only after stop
  # succeeded in this namespace (the job existed and was purged).
  if [ "${STOP_EXIT}" -ne 0 ]; then
    if printf '%s\n' "${STOP_OUTPUT}" | grep -qiE 'No job\(s\) with prefix or ID'; then
      echo "::error::Nomad job ${job} was not found in namespace ${NOMAD_NAMESPACE}. Cleanup did not stop a running preview."
    else
      echo "::error::nomad job stop failed for ${job} in namespace ${NOMAD_NAMESPACE} (exit ${STOP_EXIT})."
    fi
    return 1
  fi

  sleep "${SLEEP_SECONDS}"
  if nomad job status "${job}" 2>/dev/null; then
    echo "::error::Job ${job} still exists in namespace ${NOMAD_NAMESPACE} after stop -purge."
    return 1
  fi
  echo "✓ Successfully cleaned up job: ${job}"
  return 0
}

echo "Looking for jobs with prefix: ${JOB_NAME} (namespace: ${NOMAD_NAMESPACE})"
JOBS=$(nomad job status 2>/dev/null \
  | awk -v p="${JOB_NAME}" 'NR>1 && index($1, p) == 1 {print $1}' || true)

TOTAL=$(printf '%s\n' "${JOBS}" | sed '/^$/d' | wc -l | tr -d ' ')
echo "Found ${TOTAL} matching job(s):"
echo "${JOBS}"

if [ "${TOTAL}" -eq 0 ]; then
  if [ "${ALLOW_MISSING}" = "true" ]; then
    echo "cleanup_success=true" >> "$GITHUB_OUTPUT"
    echo "No Nomad jobs with prefix ${JOB_NAME} in namespace ${NOMAD_NAMESPACE} (already gone)."
    exit 0
  fi
  echo "cleanup_success=false" >> "$GITHUB_OUTPUT"
  echo "::error::No Nomad jobs with prefix ${JOB_NAME} in namespace ${NOMAD_NAMESPACE}."
  exit 1
fi

FAILED=0
for job in ${JOBS}; do
  [ -z "${job}" ] && continue
  if ! stop_one "${job}"; then
    FAILED=$((FAILED + 1))
  fi
done

if [ "${FAILED}" -ne 0 ]; then
  echo "cleanup_success=false" >> "$GITHUB_OUTPUT"
  echo "::error::Failed to clean up ${FAILED} Nomad job(s) for prefix ${JOB_NAME}."
  exit 1
fi
echo "cleanup_success=true" >> "$GITHUB_OUTPUT"
echo "Cleaned up ${TOTAL} Nomad job(s) with prefix ${JOB_NAME}."
