#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

PORT_FORWARD_PID=""
cleanup() {
  if [[ -n "${PORT_FORWARD_PID}" ]] && kill -0 "${PORT_FORWARD_PID}" 2>/dev/null; then
    kill "${PORT_FORWARD_PID}"
    wait "${PORT_FORWARD_PID}" 2>/dev/null || true
  fi
  "${CODE01_ROOT}/scripts/configure-upstream-package-sources.sh" restore >/dev/null 2>&1 || true
}
trap cleanup EXIT

exec > >(tee "${EVIDENCE_DIR}/transcript.log") 2>&1

printf 'KARS runtimes and BYO lab\n'
printf 'Run: %s\n' "${RUN_ID}"
printf 'Host: %s %s\n\n' "$(uname -s)" "$(uname -m)"

require_forge
"${CODE01_ROOT}/scripts/configure-upstream-package-sources.sh" apply
verify_microsoft_sources
"${LAB_ROOT}/scripts/test-unit.sh"
"${LAB_ROOT}/scripts/test-copilot-agent.sh"
"${LAB_ROOT}/scripts/deploy-byo.sh"
"${LAB_ROOT}/scripts/inspect.sh"

"${LAB_ROOT}/scripts/port-forward.sh" \
  >"${EVIDENCE_DIR}/port-forward.log" 2>&1 &
PORT_FORWARD_PID=$!
wait_for_http "http://127.0.0.1:${LOCAL_PORT}/healthz"
"${LAB_ROOT}/scripts/test-byo-runtime.sh"

printf '\nAll runtime and BYO checks passed.\n'
printf 'Evidence: %s\n' "${EVIDENCE_DIR}"
