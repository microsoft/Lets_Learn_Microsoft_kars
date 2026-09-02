#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
require_forge

namespace="$(forge_namespace)"
pod="$(forge_pod)"

kubectl -n kars-system get karssandbox forge -o yaml \
  >"${EVIDENCE_DIR}/forge-sandbox.yaml"
kubectl -n "${namespace}" get pod "${pod}" -o json \
  >"${EVIDENCE_DIR}/forge-pod.json"
kubectl -n "${namespace}" get networkpolicy -o yaml \
  >"${EVIDENCE_DIR}/network-policies.yaml"
kubectl -n kars-mcp get deployment forge-workspace-mcp -o yaml \
  >"${EVIDENCE_DIR}/workspace-deployment.yaml"
kubectl get validatingadmissionpolicy kars-sandbox-exec-ban -o yaml \
  >"${EVIDENCE_DIR}/exec-admission-policy.yaml"
kubectl -n kars-system logs deployment/kars-controller --tail=200 \
  >"${EVIDENCE_DIR}/controller.log"
kubectl -n "${namespace}" logs "${pod}" -c inference-router --tail=200 \
  >"${EVIDENCE_DIR}/router.log"

jq '{
  pod: .metadata.name,
  initContainers: [.spec.initContainers[] | {
    name,
    runAsUser: .securityContext.runAsUser,
    capabilities: .securityContext.capabilities
  }],
  containers: [.spec.containers[] | {
    name,
    runAsUser: .securityContext.runAsUser,
    readOnlyRootFilesystem: .securityContext.readOnlyRootFilesystem,
    allowPrivilegeEscalation: .securityContext.allowPrivilegeEscalation,
    envNames: [.env[]?.name],
    mounts: [.volumeMounts[]?.mountPath]
  }],
  volumes: [.spec.volumes[] | {
    name,
    type: (if .emptyDir then "emptyDir"
      elif .secret then "secret"
      elif .configMap then "configMap"
      elif .projected then "projected"
      elif .hostPath then "hostPath"
      else "other" end)
  }]
}' "${EVIDENCE_DIR}/forge-pod.json" >"${EVIDENCE_DIR}/pod-summary.json"

cat >"${EVIDENCE_DIR}/README.md" <<EOF
# Forge sandbox evidence

- Captured: ${RUN_ID}
- Sandbox: \`forge\`
- Namespace: \`${namespace}\`
- Pod: \`${pod}\`
- Host architecture: \`$(uname -m)\`
- Container platform: \`${CONTAINER_PLATFORM}\`

The evidence is stored outside the sandbox so it remains available after the
Forge Pod is reconciled or its disposable workspace is removed.
EOF

printf 'Evidence captured in %s\n' "${EVIDENCE_DIR}"
