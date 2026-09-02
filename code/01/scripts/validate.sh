#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${ROOT_DIR}/scripts/platform-env.sh"
export npm_config_registry="https://packagefeedproxy.microsoft.io/npm/"
export pnpm_config_registry="https://packagefeedproxy.microsoft.io/npm/"
export npm_config_replace_registry_host="registry.npmjs.org"
export npm_config_omit_lockfile_registry_resolved="true"
export npm_config_allow_remote="all"
export npm_config_package_lock="false"
export PIP_INDEX_URL="https://packagefeedproxy.microsoft.io/pypi/simple/"
export NUGET_CONFIG_FILE="${ROOT_DIR}/NuGet.Config"

trap '"${ROOT_DIR}/scripts/configure-upstream-package-sources.sh" restore >/dev/null' EXIT
"${ROOT_DIR}/scripts/configure-upstream-package-sources.sh" apply
"${ROOT_DIR}/scripts/verify-npm-source.sh"

cd "${ROOT_DIR}/workspace-mcp"
npm test

cd "${ROOT_DIR}"
docker build \
  --build-arg NPM_CONFIG_REGISTRY="${npm_config_registry}" \
  -t forge-workspace-mcp:dev workspace-mcp

kubectl apply --server-side --dry-run=server -f k8s/workspace-mcp.yaml >/dev/null
kubectl apply --server-side --dry-run=server -f .generated/policies.yaml >/dev/null
kubectl apply --server-side --dry-run=server -f .generated/forge.yaml >/dev/null
kubectl apply --server-side --dry-run=server \
  -f .generated/forge-spawn-networkpolicy.yaml >/dev/null

kubectl -n kars-mcp rollout status deployment/forge-workspace-mcp --timeout=120s
kubectl -n kars-system wait \
  --for=jsonpath='{.status.phase}'=Running \
  karssandbox/forge \
  --timeout=180s

OPENCLAW_ENV_NAMES="$(
  kubectl -n kars-forge get pod -l kars.azure.com/sandbox=forge \
    -o jsonpath='{range .items[0].spec.containers[?(@.name=="openclaw")].env[*]}{.name}{"\n"}{end}'
)"
if grep -Eq '(^|_)(COPILOT|GITHUB).*(TOKEN|KEY)|^(GH_TOKEN|GITHUB_TOKEN)$' \
  <<<"${OPENCLAW_ENV_NAMES}"; then
  echo "A GitHub Copilot credential reference is present in the openclaw container." >&2
  exit 1
fi

kubectl -n kars-forge get networkpolicy -o name | grep -q .
kubectl -n kars-forge get networkpolicy/forge-spawn-apiserver >/dev/null
kubectl -n kars-system get \
  mcpserver/forge-workspace \
  toolpolicy/forge-workspace-tools \
  toolpolicy/forge-toolpolicy \
  inferencepolicy/forge-inference >/dev/null

FORGE_POD="$(
  kubectl -n kars-forge get pod -l kars.azure.com/sandbox=forge \
    -o jsonpath='{.items[0].metadata.name}'
)"
KUBE_API_IP="$(kubectl get service kubernetes -o jsonpath='{.spec.clusterIP}')"
KUBE_API_STATUS="$(
  kubectl -n kars-forge exec "${FORGE_POD}" -c inference-router -- \
    curl -ksS --connect-timeout 5 -o /dev/null -w '%{http_code}' \
    "https://${KUBE_API_IP}:443/"
)"
if [[ "${KUBE_API_STATUS}" == "000" ]]; then
  echo "The inference router cannot reach the Kubernetes API." >&2
  exit 1
fi

FALLBACK_STATUS="$(
  kubectl -n kars-forge exec "${FORGE_POD}" -c inference-router -- \
    curl -sS -o /dev/null -w '%{http_code}' \
    -H "content-type: application/json" \
    -H "x-kars-sandbox: forge" \
    --data '{"model":"gpt-5.6-sol","messages":[{"role":"user","content":"Reply with OK only."}],"max_completion_tokens":32}' \
    http://127.0.0.1:8443/v1/chat/completions
)"
if [[ "${FALLBACK_STATUS}" != "200" ]]; then
  echo "GPT-5.6-Sol chat-to-Responses fallback returned HTTP ${FALLBACK_STATUS}." >&2
  exit 1
fi

echo "Local KARS deployment validation passed."
