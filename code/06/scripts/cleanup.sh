#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

current="$(kubectl --context kind-kars-dev -n kars-system get \
  "inferencepolicy/${POLICY_NAME}" \
  -o jsonpath='{.spec.tokenBudget.perRequestTokens}' 2>/dev/null || true)"
if [[ -n "${current}" && "${current}" != "1024" ]]; then
  kubectl --context kind-kars-dev -n kars-system patch \
    "inferencepolicy/${POLICY_NAME}" \
    --type=merge \
    -p '{"spec":{"tokenBudget":{"perRequestTokens":1024}}}' >/dev/null
  wait_for_policy 1024
fi
kubectl --context kind-kars-dev -n "${SANDBOX_NAMESPACE}" rollout status \
  "deployment/${SANDBOX_NAME}" --timeout=180s >/dev/null
pass "Code/05 BYO runtime and original inference budget are healthy"
