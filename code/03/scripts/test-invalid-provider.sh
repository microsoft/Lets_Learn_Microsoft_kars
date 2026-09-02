#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

manifest="${LAB_ROOT}/manifests/invalid-provider.yaml"
name="forge-invalid-provider"

cleanup() {
  kubectl -n kars-system delete karssandbox "${name}" \
    --ignore-not-found --wait=true >/dev/null 2>&1 || true
  kubectl -n kars-system delete inferencepolicy forge-invalid-provider-inference \
    --ignore-not-found >/dev/null 2>&1 || true
}
trap cleanup EXIT

kubectl apply --server-side --field-manager="${FIELD_MANAGER}" -f "${manifest}" >/dev/null
wait_for_sandbox "${name}" Running
kubectl -n kars-system get karssandbox "${name}" -o json \
  >"${EVIDENCE_DIR}/invalid-provider-sandbox.json"
pass "Kubernetes schema and controller accept the opaque provider deployment name"

namespace="$(jq -r '.status.namespace' "${EVIDENCE_DIR}/invalid-provider-sandbox.json")"
kubectl -n "${namespace}" wait \
  --for=condition=Ready pod \
  -l kars.azure.com/sandbox="${name}" \
  --timeout=240s >/dev/null
pod="$(kubectl -n "${namespace}" get pod \
  -l kars.azure.com/sandbox="${name}" \
  -o jsonpath='{.items[0].metadata.name}')"

set +e
http_code="$(kubectl -n "${namespace}" exec "${pod}" -c inference-router -- \
  curl -sS --max-time 45 -o /dev/null -w "%{http_code}" \
  -H "content-type: application/json" \
  -H "x-kars-sandbox: forge-invalid-provider" \
  --data '{"model":"intentionally-invalid-model","messages":[{"role":"user","content":"Reply OK."}],"max_completion_tokens":16}' \
  http://127.0.0.1:8443/v1/chat/completions)"
request_rc=$?
set -e

printf 'kubectl_rc=%s\nhttp_code=%s\n' "${request_rc}" "${http_code}" \
  >"${EVIDENCE_DIR}/invalid-provider-request.txt"
[[ ${request_rc} -eq 0 ]] || fail "Router request could not be executed"
[[ "${http_code}" =~ ^[0-9]{3}$ ]] || fail "Router did not return an HTTP status"
if [[ "${http_code}" == "200" ]]; then
  fail "Invalid provider deployment unexpectedly returned HTTP 200"
fi
pass "Invalid provider deployment fails at request time, not CRD validation time"
