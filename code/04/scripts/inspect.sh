#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
require_forge

kubectl -n kars-system get inferencepolicy forge-inference -o json \
  >"${EVIDENCE_DIR}/inference-policy.json"
kubectl -n kars-system get toolpolicy forge-workspace-tools -o json \
  >"${EVIDENCE_DIR}/coordinator-tool-policy.json"
kubectl -n kars-system get toolpolicy forge-toolpolicy -o json \
  >"${EVIDENCE_DIR}/specialist-tool-policy.json"
kubectl -n kars-system get mcpserver forge-workspace -o json \
  >"${EVIDENCE_DIR}/mcp-server.json"
kubectl -n kars-system get configmap toolpolicy-forge-workspace-tools-profile -o json \
  >"${EVIDENCE_DIR}/compiled-tool-profile.json"
kubectl -n kars-system get configmap inferencepolicy-forge-inference-profile -o json \
  >"${EVIDENCE_DIR}/compiled-inference-profile.json"
kubectl -n kars-mcp get deployment forge-workspace-mcp -o yaml \
  >"${EVIDENCE_DIR}/workspace-mcp-deployment.yaml"

printf 'Governance resources captured in %s\n' "${EVIDENCE_DIR}"
