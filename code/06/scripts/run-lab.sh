#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

APP_PF_PID=""
ROUTER_PF_PID=""

stop_forwards() {
  for pid in "${APP_PF_PID}" "${ROUTER_PF_PID}"; do
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
      kill "${pid}"
      wait "${pid}" 2>/dev/null || true
    fi
  done
  APP_PF_PID=""
  ROUTER_PF_PID=""
}

start_forwards() {
  "${LAB_ROOT}/scripts/port-forward-app.sh" \
    >"${EVIDENCE_DIR}/port-forward-app.log" 2>&1 &
  APP_PF_PID=$!
  "${LAB_ROOT}/scripts/port-forward-router.sh" \
    >"${EVIDENCE_DIR}/port-forward-router.log" 2>&1 &
  ROUTER_PF_PID=$!
  wait_for_http "http://127.0.0.1:${APP_PORT}/healthz"
  wait_for_http "http://127.0.0.1:${ROUTER_PORT}/readyz"
}

cleanup() {
  stop_forwards
  "${LAB_ROOT}/scripts/cleanup.sh" >/dev/null 2>&1 || true
  "${CODE01_ROOT}/scripts/configure-upstream-package-sources.sh" restore >/dev/null 2>&1 || true
}
trap cleanup EXIT

exec > >(tee "${EVIDENCE_DIR}/transcript.log") 2>&1

printf 'KARS security and operations lab\n'
printf 'Run: %s\n' "${RUN_ID}"
printf 'Host: %s %s\n\n' "$(uname -s)" "$(uname -m)"

require_code05
"${CODE01_ROOT}/scripts/configure-upstream-package-sources.sh" apply
verify_microsoft_sources
"${LAB_ROOT}/scripts/test-unit.sh"

EVIDENCE_DIR="${EVIDENCE_DIR}" RUN_ID="${RUN_ID}" \
  "${CODE05_ROOT}/scripts/test-copilot-agent.sh"
pass "Host-side MAF Copilot canary remains healthy on GPT-5.6-Sol"

"${LAB_ROOT}/scripts/install-operations-guard.sh"
"${LAB_ROOT}/scripts/inspect.sh"
start_forwards
"${LAB_ROOT}/scripts/test-boundaries.sh"
"${LAB_ROOT}/scripts/test-audit.sh"
stop_forwards
"${LAB_ROOT}/scripts/test-budget-incident.sh"

"${LAB_ROOT}/scripts/restart-sandbox.sh"
start_forwards
"${LAB_ROOT}/scripts/test-recovery.sh"
"${LAB_ROOT}/scripts/release-record.sh"
"${LAB_ROOT}/scripts/cleanup.sh"

printf '\nAll security and operations checks passed.\n'
printf 'Evidence: %s\n' "${EVIDENCE_DIR}"
