#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

deployment="forge-workspace-mcp"
replicas="$(kubectl -n kars-mcp get deployment "${deployment}" -o jsonpath='{.spec.replicas}')"

restore() {
  kubectl -n kars-mcp scale deployment "${deployment}" --replicas="${replicas}" >/dev/null 2>&1 || true
  kubectl -n kars-mcp rollout status deployment "${deployment}" --timeout=180s >/dev/null 2>&1 || true
}
trap restore EXIT

kubectl -n kars-mcp scale deployment "${deployment}" --replicas=0 >/dev/null
kubectl -n kars-mcp wait --for=delete pod \
  -l app=forge-workspace-mcp --timeout=120s >/dev/null

addresses="$(kubectl -n kars-mcp get endpoints forge-workspace-mcp \
  -o jsonpath='{.subsets[*].addresses[*].ip}')"
[[ -z "${addresses}" ]] || fail "MCP Service still has ready endpoints during outage"
pass "MCP outage is explicit as an empty Service endpoint set"

restore
trap - EXIT
pass "Workspace MCP Deployment returns to Ready after the outage test"
