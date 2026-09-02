#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

limit="$(jq -r '.spec.tokenBudget.perRequestTokens' "${EVIDENCE_DIR}/inference-policy.json")"
requested=$((limit + 1))
pod="$(kubectl -n kars-forge get pod \
  -l kars.azure.com/sandbox=forge \
  -o jsonpath='{.items[0].metadata.name}')"

http_code="$(kubectl -n kars-forge exec "${pod}" -c inference-router -- \
  curl -sS -o /dev/null -w '%{http_code}' \
  -H 'content-type: application/json' \
  -H 'x-kars-sandbox: forge' \
  --data "$(jq -cn \
    --arg model "$(jq -r '.spec.modelPreference.primary.deployment' "${EVIDENCE_DIR}/inference-policy.json")" \
    --argjson requested "${requested}" \
    '{model:$model,messages:[{role:"user",content:"Reply OK."}],max_completion_tokens:$requested}')" \
  http://127.0.0.1:8443/v1/chat/completions)"

cat >"${EVIDENCE_DIR}/budget-denial.json" <<EOF
{
  "perRequestLimit": ${limit},
  "requestedTokens": ${requested},
  "httpStatus": ${http_code}
}
EOF

[[ "${http_code}" == "429" ]] \
  || fail "Over-budget inference returned HTTP ${http_code}, expected 429"
pass "Router rejects a request above the per-request token budget with HTTP 429"
