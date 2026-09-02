#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

APP_PF_PID=""
ROUTER_PF_PID=""
original_tokens="$(kubectl --context kind-kars-dev -n kars-system get \
  "inferencepolicy/${POLICY_NAME}" \
  -o jsonpath='{.spec.tokenBudget.perRequestTokens}')"

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

restart_for_policy_reload() {
  kubectl --context kind-kars-dev -n "${SANDBOX_NAMESPACE}" rollout restart \
    "deployment/${SANDBOX_NAME}" >/dev/null
  kubectl --context kind-kars-dev -n "${SANDBOX_NAMESPACE}" rollout status \
    "deployment/${SANDBOX_NAME}" --timeout=300s >/dev/null
}

start_router_forward() {
  "${LAB_ROOT}/scripts/port-forward-router.sh" \
    >"${EVIDENCE_DIR}/budget-port-forward-router.log" 2>&1 &
  ROUTER_PF_PID=$!
  wait_for_http "http://127.0.0.1:${ROUTER_PORT}/readyz"
}

start_app_forward() {
  "${LAB_ROOT}/scripts/port-forward-app.sh" \
    >"${EVIDENCE_DIR}/budget-port-forward-app.log" 2>&1 &
  APP_PF_PID=$!
  wait_for_http "http://127.0.0.1:${APP_PORT}/healthz"
}

restore_policy() {
  stop_forwards
  kubectl --context kind-kars-dev -n kars-system patch \
    "inferencepolicy/${POLICY_NAME}" \
    --type=merge \
    -p "{\"spec\":{\"tokenBudget\":{\"perRequestTokens\":${original_tokens}}}}" \
    >/dev/null 2>&1 || true
  restart_for_policy_reload >/dev/null 2>&1 || true
  wait_for_policy "${original_tokens}" >/dev/null 2>&1 || true
}
trap restore_policy EXIT

kubectl --context kind-kars-dev -n kars-system patch \
  "inferencepolicy/${POLICY_NAME}" \
  --type=merge \
  -p '{"spec":{"tokenBudget":{"perRequestTokens":16}}}' >/dev/null
restart_for_policy_reload
wait_for_policy 16
start_router_forward

status="$(curl -sS \
  -o "${EVIDENCE_DIR}/budget-denial.json" \
  -w '%{http_code}' \
  -H 'content-type: application/json' \
  --data '{
    "model":"gpt-5.6-sol",
    "messages":[{"role":"user","content":"Reply with a short incident marker."}],
    "max_tokens":17,
    "stream":false
  }' \
  "http://127.0.0.1:${ROUTER_PORT}/v1/chat/completions")"
[[ "${status}" == "429" ]] || fail "Expected budget HTTP 429, received ${status}"
pass "Temporary 16-token incident policy rejects a 17-token Chat Completions request with HTTP 429"

restore_policy
trap - EXIT
start_app_forward

curl -fsS \
  -H 'content-type: application/json' \
  --data '{"issue_id":"FORMAT-482"}' \
  "http://127.0.0.1:${APP_PORT}/run" |
  jq . >"${EVIDENCE_DIR}/post-policy-restore-response.json"
jq -e '.model == "gpt-5.6-sol" and (.reply | contains("KARS_BYO_GPT_5_6_SOL_OK"))' \
  "${EVIDENCE_DIR}/post-policy-restore-response.json" >/dev/null \
  || fail "Model smoke test failed after policy restoration"
stop_forwards
pass "InferencePolicy returned to its original limit and GPT-5.6-Sol recovered"
