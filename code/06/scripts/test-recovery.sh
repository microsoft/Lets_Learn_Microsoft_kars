#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

curl -fsS "http://127.0.0.1:${ROUTER_PORT}/agt/audit" |
  jq . >"${EVIDENCE_DIR}/audit-after-restart-before-smoke.json"
after_restart_count="$(jq -r '.count' "${EVIDENCE_DIR}/audit-after-restart-before-smoke.json")"
old_count="$(jq -r '.oldAuditCount' "${EVIDENCE_DIR}/restart.json")"

curl -fsS \
  -H 'content-type: application/json' \
  --data '{"issue_id":"FORMAT-482"}' \
  "http://127.0.0.1:${APP_PORT}/run" |
  jq . >"${EVIDENCE_DIR}/post-restart-model-response.json"
curl -fsS "http://127.0.0.1:${ROUTER_PORT}/agt/audit/verify" |
  jq . >"${EVIDENCE_DIR}/audit-verify-after-restart.json"

jq -e '
  .model == "gpt-5.6-sol"
  and (.reply | contains("KARS_BYO_GPT_5_6_SOL_OK"))
' "${EVIDENCE_DIR}/post-restart-model-response.json" >/dev/null \
  || fail "GPT-5.6-Sol smoke test failed after Pod replacement"
jq -e '.integrity == "valid" and .entries > 0' \
  "${EVIDENCE_DIR}/audit-verify-after-restart.json" >/dev/null \
  || fail "Audit chain failed after Pod replacement"

jq -n \
  --argjson before "${old_count}" \
  --argjson afterRestart "${after_restart_count}" \
  '{
    beforeRestart:$before,
    immediatelyAfterRestart:$afterRestart,
    persisted:($afterRestart >= $before)
  }' >"${EVIDENCE_DIR}/audit-persistence.json"

if [[ "${after_restart_count}" -lt "${old_count}" ]]; then
  pass "Local in-memory audit entries reset on Pod replacement; external export is required"
else
  pass "Audit entries persisted across Pod replacement"
fi
pass "Replacement Pod serves GPT-5.6-Sol and starts a valid audit chain"
