#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

curl -fsS "http://127.0.0.1:${APP_PORT}/contract" |
  jq . >"${EVIDENCE_DIR}/runtime-contract.json"
curl -fsS "http://127.0.0.1:${APP_PORT}/direct-egress" |
  jq . >"${EVIDENCE_DIR}/direct-egress.json"

jq -e '
  .model == "gpt-5.6-sol"
  and .providerCredentialNames == []
  and .workflow[-1] == "STOP_FOR_HUMAN_REVIEW"
' "${EVIDENCE_DIR}/runtime-contract.json" >/dev/null \
  || fail "Runtime contract or credential boundary changed"
jq -e '.blocked == true' "${EVIDENCE_DIR}/direct-egress.json" >/dev/null \
  || fail "Direct agent egress unexpectedly succeeded"

pod="$(kubectl --context kind-kars-dev -n "${SANDBOX_NAMESPACE}" get pod \
  -o jsonpath='{.items[0].metadata.name}')"
if kubectl --context kind-kars-dev -n "${SANDBOX_NAMESPACE}" exec \
  "${pod}" -c agent -- true >"${EVIDENCE_DIR}/exec-denial.txt" 2>&1; then
  fail "kubectl exec unexpectedly succeeded without break-glass"
fi
grep -Eqi 'denied|forbidden|break-glass' "${EVIDENCE_DIR}/exec-denial.txt" \
  || fail "Exec failed for an unexpected reason"
pass "Credential isolation, direct-egress denial, and the BYO exec admission guard remain enforced"
