#!/usr/bin/env bash
# Run local tests for the Nomad PR cleanup scripts (no cluster, no GitHub).
#
#   .github/actions/cleanup-pr-nomad-job/tests/run.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
ACTION="$(cd "${ROOT}/.." && pwd)"
export PATH="${ROOT}:${PATH}"
chmod +x "${ROOT}/nomad" "${ROOT}/gh" "${ACTION}/cleanup.sh" "${ACTION}/find-closed-pr.sh"

PASSES=0
FAILS=0

assert_eq() {
  local name="$1" expected="$2" actual="$3"
  if [ "${expected}" = "${actual}" ]; then
    echo "PASS  ${name}"
    PASSES=$((PASSES + 1))
  else
    echo "FAIL  ${name}"
    echo "      expected: ${expected}"
    echo "      actual:   ${actual}"
    FAILS=$((FAILS + 1))
  fi
}

assert_file_contains() {
  local name="$1" file="$2" needle="$3"
  if grep -Fq "${needle}" "${file}"; then
    echo "PASS  ${name}"
    PASSES=$((PASSES + 1))
  else
    echo "FAIL  ${name} (missing '${needle}' in ${file})"
    echo "----- file -----"
    cat "${file}"
    echo "----------------"
    FAILS=$((FAILS + 1))
  fi
}

run_cleanup() {
  local state="$1"
  shift
  local out
  out=$(mktemp)
  (
    export NOMAD_STUB_STATE="${state}"
    export NOMAD_STUB_NAMESPACE="${NOMAD_STUB_NAMESPACE:-ruthjoy}"
    export NOMAD_NAMESPACE="${NOMAD_NAMESPACE:-ruthjoy}"
    export SLEEP_SECONDS=0
    export KEEP_JOB_NAME="${KEEP_JOB_NAME:-}"
    export GITHUB_OUTPUT
    GITHUB_OUTPUT=$(mktemp)
    echo "${GITHUB_OUTPUT}" > "${out}.gho"
    set +e
    bash "${ACTION}/cleanup.sh" >"${out}" 2>&1
    echo $? > "${out}.exit"
    set -e
    cat "${GITHUB_OUTPUT}" > "${out}.output"
  )
  cat "${out}"
  EVAL_EXIT=$(cat "${out}.exit")
  EVAL_GHO=$(cat "${out}.output")
  EVAL_LOG="${out}"
}

seed_jobs() {
  local state="$1"
  shift
  : > "${state}"
  for job in "$@"; do
    printf '%s\n' "${job}" >> "${state}"
  done
}

echo "== cleanup.sh =="

# Exact ID: stop the one matching job, leave others.
STATE=$(mktemp)
seed_jobs "${STATE}" orca-pr-66-afa2e40 orca-pr-65-4685364
JOB_NAME=orca-pr-66-afa2e40 ALLOW_MISSING=false run_cleanup "${STATE}"
assert_eq "exact id exit 0" "0" "${EVAL_EXIT}"
assert_file_contains "exact id sets cleanup_success" "${EVAL_LOG}.output" "cleanup_success=true"
assert_eq "exact id removed target" "1" "$(grep -c . "${STATE}" || true)"
assert_file_contains "exact id left other PR job" "${STATE}" "orca-pr-65-4685364"

# Prefix: stop every job for that PR, not a sibling PR.
STATE=$(mktemp)
seed_jobs "${STATE}" orca-pr-66-aaa1111 orca-pr-66-bbb2222 orca-pr-65-4685364
JOB_NAME=orca-pr-66- ALLOW_MISSING=false run_cleanup "${STATE}"
assert_eq "prefix exit 0" "0" "${EVAL_EXIT}"
assert_eq "prefix removed both SHA jobs" "1" "$(grep -c . "${STATE}" || true)"
assert_file_contains "prefix did not stop PR 65" "${STATE}" "orca-pr-65-4685364"

# orca-pr-6- must not match orca-pr-65-...
STATE=$(mktemp)
seed_jobs "${STATE}" orca-pr-65-4685364 orca-pr-6-abc1234
JOB_NAME=orca-pr-6- ALLOW_MISSING=false run_cleanup "${STATE}"
assert_eq "short prefix exit 0" "0" "${EVAL_EXIT}"
assert_file_contains "short prefix kept pr-65" "${STATE}" "orca-pr-65-4685364"
assert_eq "short prefix removed only pr-6" "1" "$(grep -c . "${STATE}" || true)"

# Missing jobs fail unless allow_missing.
STATE=$(mktemp)
seed_jobs "${STATE}"
JOB_NAME=orca-pr-66- ALLOW_MISSING=false run_cleanup "${STATE}"
assert_eq "missing fails" "1" "${EVAL_EXIT}"
assert_file_contains "missing sets cleanup_success false" "${EVAL_LOG}.output" "cleanup_success=false"

STATE=$(mktemp)
seed_jobs "${STATE}"
JOB_NAME=orca-pr-66- ALLOW_MISSING=true run_cleanup "${STATE}"
assert_eq "missing allow_missing succeeds" "0" "${EVAL_EXIT}"
assert_file_contains "allow_missing sets cleanup_success" "${EVAL_LOG}.output" "cleanup_success=true"

# Wrong namespace looks empty (the production bug: CLI default vs ruthjoy).
STATE=$(mktemp)
seed_jobs "${STATE}" orca-pr-66-afa2e40
NOMAD_NAMESPACE=default NOMAD_STUB_NAMESPACE=ruthjoy JOB_NAME=orca-pr-66- ALLOW_MISSING=false run_cleanup "${STATE}"
assert_eq "wrong namespace fails" "1" "${EVAL_EXIT}"
assert_file_contains "wrong namespace left the job" "${STATE}" "orca-pr-66-afa2e40"

# Stop error other than not-found still fails.
STATE=$(mktemp)
seed_jobs "${STATE}" orca-pr-66-afa2e40
NOMAD_STUB_STOP_FAIL=1 JOB_NAME=orca-pr-66-afa2e40 ALLOW_MISSING=false run_cleanup "${STATE}"
assert_eq "stop error fails" "1" "${EVAL_EXIT}"
assert_file_contains "stop error left the job" "${STATE}" "orca-pr-66-afa2e40"

# keep_job_name: stop older SHA jobs for this PR, keep the current preview.
STATE=$(mktemp)
seed_jobs "${STATE}" orca-pr-66-oldsha1 orca-pr-66-newsha2 orca-pr-65-4685364
JOB_NAME=orca-pr-66- KEEP_JOB_NAME=orca-pr-66-newsha2 ALLOW_MISSING=false run_cleanup "${STATE}"
assert_eq "keep current exit 0" "0" "${EVAL_EXIT}"
assert_file_contains "keep current left new job" "${STATE}" "orca-pr-66-newsha2"
assert_file_contains "keep current left other PR" "${STATE}" "orca-pr-65-4685364"
assert_eq "keep current removed only old SHA" "2" "$(grep -c . "${STATE}" || true)"

# keep_job_name when only the current job exists (first preview / nothing older).
STATE=$(mktemp)
seed_jobs "${STATE}" orca-pr-66-newsha2
JOB_NAME=orca-pr-66- KEEP_JOB_NAME=orca-pr-66-newsha2 ALLOW_MISSING=false run_cleanup "${STATE}"
assert_eq "keep only current exit 0" "0" "${EVAL_EXIT}"
assert_file_contains "keep only current still there" "${STATE}" "orca-pr-66-newsha2"
assert_eq "keep only current did not remove it" "1" "$(grep -c . "${STATE}" || true)"

echo "== find-closed-pr.sh =="

run_find_pr() {
  local out
  out=$(mktemp)
  (
    export GITHUB_REPOSITORY=coastal-science/coastal-science.github.io
    export GITHUB_REPOSITORY_OWNER=coastal-science
    export DELETED_REF
    export GH_STUB_PAYLOAD
    export GITHUB_OUTPUT
    GITHUB_OUTPUT=$(mktemp)
    echo "${GITHUB_OUTPUT}" > "${out}.gho"
    set +e
    bash "${ACTION}/find-closed-pr.sh" >"${out}" 2>&1
    echo $? > "${out}.exit"
    set -e
    cat "${GITHUB_OUTPUT}" > "${out}.output"
  )
  cat "${out}"
  EVAL_EXIT=$(cat "${out}.exit")
  EVAL_LOG="${out}"
}

DELETED_REF=cms/research_publications/me-mani-fausto
GH_STUB_PAYLOAD='{"number":66}'
run_find_pr
assert_eq "find-pr exit 0" "0" "${EVAL_EXIT}"
assert_file_contains "find-pr writes number" "${EVAL_LOG}.output" "pr_number=66"

DELETED_REF=cms/does-not-exist
GH_STUB_PAYLOAD=''
run_find_pr
assert_eq "find-pr none exit 0" "0" "${EVAL_EXIT}"
assert_file_contains "find-pr empty number" "${EVAL_LOG}.output" "pr_number="

echo
echo "${PASSES} passed, ${FAILS} failed"
if [ "${FAILS}" -ne 0 ]; then
  exit 1
fi
