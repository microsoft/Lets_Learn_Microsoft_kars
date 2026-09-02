#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

old_pod="$(kubectl --context kind-kars-dev -n "${SANDBOX_NAMESPACE}" get pod \
  -o json | jq -r '.items[] | select(.metadata.deletionTimestamp == null) | .metadata.name' |
  head -1)"
old_uid="$(kubectl --context kind-kars-dev -n "${SANDBOX_NAMESPACE}" get pod \
  "${old_pod}" -o jsonpath='{.metadata.uid}')"
old_audit_count="$(jq -r '.count' "${EVIDENCE_DIR}/audit-before-restart.json")"

kubectl --context kind-kars-dev -n "${SANDBOX_NAMESPACE}" delete pod \
  "${old_pod}" --wait=false >/dev/null
kubectl --context kind-kars-dev -n "${SANDBOX_NAMESPACE}" rollout status \
  "deployment/${SANDBOX_NAME}" --timeout=300s >/dev/null

for _ in $(seq 1 60); do
  new_pod="$(kubectl --context kind-kars-dev -n "${SANDBOX_NAMESPACE}" get pod \
    -o json | jq -r '.items[] | select(.metadata.deletionTimestamp == null) | .metadata.name' |
    head -1)"
  new_uid="$(kubectl --context kind-kars-dev -n "${SANDBOX_NAMESPACE}" get pod \
    "${new_pod}" -o jsonpath='{.metadata.uid}')"
  [[ "${new_uid}" != "${old_uid}" ]] && break
  sleep 1
done
[[ "${new_uid}" != "${old_uid}" ]] || fail "Deployment did not replace the Pod"

jq -n \
  --arg oldPod "${old_pod}" \
  --arg oldUid "${old_uid}" \
  --arg newPod "${new_pod}" \
  --arg newUid "${new_uid}" \
  --argjson oldAuditCount "${old_audit_count}" \
  '{
    oldPod:$oldPod,
    oldUid:$oldUid,
    newPod:$newPod,
    newUid:$newUid,
    oldAuditCount:$oldAuditCount
  }' >"${EVIDENCE_DIR}/restart.json"
pass "Deployment replaced the failed Pod and reached Ready"
