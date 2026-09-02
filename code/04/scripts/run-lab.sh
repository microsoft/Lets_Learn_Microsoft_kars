#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"
require_forge

transcript="${EVIDENCE_DIR}/transcript.log"
port_forward_pid=""

restore_sources() {
  "${CODE01_ROOT}/scripts/configure-upstream-package-sources.sh" restore >/dev/null 2>&1 || true
}

stop_port_forward() {
  if [[ -n "${port_forward_pid}" ]] && kill -0 "${port_forward_pid}" 2>/dev/null; then
    kill "${port_forward_pid}"
    wait "${port_forward_pid}" 2>/dev/null || true
  fi
}

cleanup() {
  stop_port_forward
  "${SCRIPT_DIR}/cleanup.sh" >/dev/null 2>&1 || true
  restore_sources
}
trap cleanup EXIT

{
  echo "KARS policy and tools lab"
  echo "Run: ${RUN_ID}"
  echo "Host: $(uname -s) $(uname -m)"
  echo

  "${CODE01_ROOT}/scripts/configure-upstream-package-sources.sh" apply >/dev/null
  verify_microsoft_sources

  EVIDENCE_DIR="${EVIDENCE_DIR}" RUN_ID="${RUN_ID}" "${SCRIPT_DIR}/inspect.sh"
  EVIDENCE_DIR="${EVIDENCE_DIR}" RUN_ID="${RUN_ID}" "${SCRIPT_DIR}/test-policy-state.sh"
  EVIDENCE_DIR="${EVIDENCE_DIR}" RUN_ID="${RUN_ID}" "${SCRIPT_DIR}/test-budget.sh"

  "${SCRIPT_DIR}/port-forward.sh" >"${EVIDENCE_DIR}/port-forward.log" 2>&1 &
  port_forward_pid=$!
  for _ in $(seq 1 30); do
    curl -fsS "http://127.0.0.1:${MCP_PORT}/healthz" >/dev/null 2>&1 && break
    sleep 1
  done
  curl -fsS "http://127.0.0.1:${MCP_PORT}/healthz" >/dev/null \
    || fail "Workspace MCP port-forward did not become ready"

  EVIDENCE_DIR="${EVIDENCE_DIR}" RUN_ID="${RUN_ID}" MCP_PORT="${MCP_PORT}" \
    "${SCRIPT_DIR}/test-mcp-tools.sh"
  stop_port_forward
  port_forward_pid=""

  EVIDENCE_DIR="${EVIDENCE_DIR}" RUN_ID="${RUN_ID}" "${SCRIPT_DIR}/test-mcp-outage.sh"

  kubectl -n kars-system logs deployment/kars-controller --tail=300 \
    >"${EVIDENCE_DIR}/controller.log"
  kubectl -n kars-forge logs \
    "$(kubectl -n kars-forge get pod -l kars.azure.com/sandbox=forge -o jsonpath='{.items[0].metadata.name}')" \
    -c inference-router --tail=300 >"${EVIDENCE_DIR}/router.log"

  echo
  echo "All policy and tool checks passed."
  echo "Evidence: ${EVIDENCE_DIR}"
} 2>&1 | tee "${transcript}"
