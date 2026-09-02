#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

kubectl --context kind-kars-dev -n kars-system get \
  "karssandbox/${SANDBOX_NAME}" -o json \
  >"${EVIDENCE_DIR}/byo-sandbox.json"
kubectl --context kind-kars-dev -n kars-system get \
  inferencepolicy/forge-byo-inference -o json \
  >"${EVIDENCE_DIR}/byo-inference-policy.json"
kubectl --context kind-kars-dev -n "${SANDBOX_NAMESPACE}" get \
  "deployment/${SANDBOX_NAME}" -o json |
  jq '{
    metadata: {name: .metadata.name, namespace: .metadata.namespace},
    replicas: .status,
    podSecurityContext: .spec.template.spec.securityContext,
    initContainers: [.spec.template.spec.initContainers[] | {
      name, image, securityContext
    }],
    containers: [.spec.template.spec.containers[] | {
      name, image, securityContext,
      envNames: [(.env // [])[] | .name],
      envFrom: (.envFrom // []),
      volumeMounts
    }],
    volumes: .spec.template.spec.volumes
  }' >"${EVIDENCE_DIR}/byo-deployment-sanitized.json"

kubectl --context kind-kars-dev -n kars-system get karssandbox/forge -o json |
  jq '{name:.metadata.name,runtime:.spec.runtime.kind,sandbox:.spec.sandbox}' \
  >"${EVIDENCE_DIR}/openclaw-shape.json"
jq '{name:.metadata.name,runtime:.spec.runtime.kind,sandbox:.spec.sandbox}' \
  "${EVIDENCE_DIR}/byo-sandbox.json" \
  >"${EVIDENCE_DIR}/byo-shape.json"
pass "Sanitized OpenClaw and BYO runtime evidence was captured"
