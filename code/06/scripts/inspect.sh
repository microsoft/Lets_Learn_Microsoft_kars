#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

pod="$(kubectl --context kind-kars-dev -n "${SANDBOX_NAMESPACE}" get pod \
  -l "app.kubernetes.io/name=${SANDBOX_NAME}" \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
if [[ -z "${pod}" ]]; then
  pod="$(kubectl --context kind-kars-dev -n "${SANDBOX_NAMESPACE}" get pod \
    -o jsonpath='{.items[0].metadata.name}')"
fi

kubectl --context kind-kars-dev -n kars-system get \
  "karssandbox/${SANDBOX_NAME}" -o json \
  >"${EVIDENCE_DIR}/sandbox.json"
kubectl --context kind-kars-dev -n kars-system get \
  "inferencepolicy/${POLICY_NAME}" -o json \
  >"${EVIDENCE_DIR}/inference-policy.json"
kubectl --context kind-kars-dev -n "${SANDBOX_NAMESPACE}" get \
  "deployment/${SANDBOX_NAME}" -o json |
  jq '{
    metadata:{name:.metadata.name,namespace:.metadata.namespace,generation:.metadata.generation},
    status:.status,
    podSecurityContext:.spec.template.spec.securityContext,
    initContainers:[.spec.template.spec.initContainers[] | {name,image,securityContext}],
    containers:[.spec.template.spec.containers[] | {
      name,image,securityContext,envNames:[(.env // [])[] | .name],volumeMounts
    }]
  }' >"${EVIDENCE_DIR}/deployment-sanitized.json"
kubectl --context kind-kars-dev -n "${SANDBOX_NAMESPACE}" get pod "${pod}" -o json |
  jq '{
    metadata:{name:.metadata.name,uid:.metadata.uid,creationTimestamp:.metadata.creationTimestamp},
    phase:.status.phase,
    containerStatuses:[.status.containerStatuses[] | {
      name,ready,restartCount,image,imageID
    }]
  }' >"${EVIDENCE_DIR}/pod-sanitized.json"
kubectl --context kind-kars-dev -n "${SANDBOX_NAMESPACE}" get events \
  --sort-by=.lastTimestamp -o json |
  jq '[.items[] | {
    type:.type,
    reason:.reason,
    message:.message,
    count:.count,
    firstTimestamp:.firstTimestamp,
    lastTimestamp:.lastTimestamp
  }]' >"${EVIDENCE_DIR}/events.json"
kubectl --context kind-kars-dev get validatingadmissionpolicy \
  kars-sandbox-exec-ban kars-byo-agent-exec-ban -o json |
  jq '[.items[] | {
    name:.metadata.name,
    observedGeneration:.status.observedGeneration,
    namespaceSelector:.spec.matchConstraints.namespaceSelector,
    matchConditions:.spec.matchConditions,
    validations:.spec.validations
  }]' >"${EVIDENCE_DIR}/exec-admission-policies.json"

can_get_secrets="$(kubectl --context kind-kars-dev auth can-i get secrets \
  --as "system:serviceaccount:${SANDBOX_NAMESPACE}:sandbox" \
  -n "${SANDBOX_NAMESPACE}" || true)"
can_create_pods="$(kubectl --context kind-kars-dev auth can-i create pods \
  --as "system:serviceaccount:${SANDBOX_NAMESPACE}:sandbox" \
  -n "${SANDBOX_NAMESPACE}" || true)"
jq -n \
  --arg canGetSecrets "${can_get_secrets}" \
  --arg canCreatePods "${can_create_pods}" \
  '{canGetSecrets:$canGetSecrets,canCreatePods:$canCreatePods}' \
  >"${EVIDENCE_DIR}/sandbox-rbac.json"

jq -e '.canGetSecrets == "no" and .canCreatePods == "no"' \
  "${EVIDENCE_DIR}/sandbox-rbac.json" >/dev/null \
  || fail "Sandbox ServiceAccount has unexpected write or secret access"
pass "Sanitized incident inventory and least-privilege RBAC evidence captured"
