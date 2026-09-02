#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

curl -fsS \
  -H 'content-type: application/json' \
  --data '{"issue_id":"FORMAT-482"}' \
  "http://127.0.0.1:${APP_PORT}/run" |
  jq . >"${EVIDENCE_DIR}/baseline-model-response.json"
jq -e '
  .model == "gpt-5.6-sol"
  and (.reply | contains("KARS_BYO_GPT_5_6_SOL_OK"))
  and (.reply | contains("STOP_FOR_HUMAN_REVIEW"))
' "${EVIDENCE_DIR}/baseline-model-response.json" >/dev/null \
  || fail "Baseline GPT-5.6-Sol smoke test failed"

curl -fsS "http://127.0.0.1:${ROUTER_PORT}/agt/audit" |
  jq . >"${EVIDENCE_DIR}/audit-before-restart.json"
curl -fsS "http://127.0.0.1:${ROUTER_PORT}/agt/audit/verify" |
  jq . >"${EVIDENCE_DIR}/audit-verify-before-restart.json"
curl -fsS "http://127.0.0.1:${ROUTER_PORT}/agt/status" |
  jq . >"${EVIDENCE_DIR}/governance-status-before-restart.json"
curl -fsS "http://127.0.0.1:${ROUTER_PORT}/metrics" |
  grep -E '^kars_(agt_audit|inference|budget|governance|egress|http)' \
  >"${EVIDENCE_DIR}/metrics-before-restart.txt" || true

jq -e '
  .integrity == "valid"
  and .entries > 0
  and .message == "Hash chain verified"
' "${EVIDENCE_DIR}/audit-verify-before-restart.json" >/dev/null \
  || fail "Router audit chain verification failed"
jq -e '
  .enabled == true
  and .governance_mode == "native"
  and .audit_integrity == true
  and .policy_loaded == true
' "${EVIDENCE_DIR}/governance-status-before-restart.json" >/dev/null \
  || fail "Router governance status is not healthy"
pass "GPT-5.6-Sol smoke, live audit-chain verification, and metrics capture succeeded"
