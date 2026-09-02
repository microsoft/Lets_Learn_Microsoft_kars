#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGT_DIR="${ROOT_DIR}/.cache/upstream/agent-governance-toolkit"
KARS_DIR="${ROOT_DIR}/.cache/upstream/kars"
GENERATED_DIR="${ROOT_DIR}/.generated"

source "${ROOT_DIR}/scripts/platform-env.sh"
export npm_config_registry="https://packagefeedproxy.microsoft.io/npm/"
export pnpm_config_registry="https://packagefeedproxy.microsoft.io/npm/"
export npm_config_replace_registry_host="registry.npmjs.org"
export npm_config_omit_lockfile_registry_resolved="true"
export npm_config_allow_remote="all"
export npm_config_package_lock="false"
export PIP_INDEX_URL="https://packagefeedproxy.microsoft.io/pypi/simple/"
export NUGET_CONFIG_FILE="${ROOT_DIR}/NuGet.Config"

if ! command -v kars >/dev/null 2>&1; then
  echo "KARS CLI is not linked. Run make build-kars first." >&2
  exit 1
fi
if [[ ! -d "${AGT_DIR}/.git" ]]; then
  echo "AGT checkout is missing. Run make build-kars first." >&2
  exit 1
fi

trap '"${ROOT_DIR}/scripts/configure-upstream-package-sources.sh" restore >/dev/null' EXIT
"${ROOT_DIR}/scripts/build-openclaw-source.sh"
"${ROOT_DIR}/scripts/configure-upstream-package-sources.sh" apply
"${ROOT_DIR}/scripts/verify-npm-source.sh"

if ! kind get clusters 2>/dev/null | grep -qx "kars-dev" ||
  ! kubectl get crd karssandboxes.kars.azure.com >/dev/null 2>&1; then
  (
    cd "${KARS_DIR}"
    kars dev --target local-k8s --build --cluster-name kars-dev \
      --name bootstrap-agent --agt-repo "${AGT_DIR}"
  )
else
  echo "Reusing ready KARS kind cluster kars-dev"
fi

PROVIDER="$(node -e 'const fs=require("fs");const p=JSON.parse(fs.readFileSync(process.env.HOME+"/.kars/config.json","utf8"));process.stdout.write(p.provider||"")')"
MODEL="${FORGE_MODEL:-gpt-5.6-sol}"
if [[ "${PROVIDER}" != "github-copilot" ]]; then
  echo "Expected KARS provider github-copilot, found '${PROVIDER}'. Run 'kars credentials' and select GitHub Copilot." >&2
  exit 1
fi

docker build \
  --build-arg NPM_CONFIG_REGISTRY="${npm_config_registry}" \
  -t forge-workspace-mcp:dev "${ROOT_DIR}/workspace-mcp"
kind load docker-image --name kars-dev forge-workspace-mcp:dev

mkdir -p "${GENERATED_DIR}"
sed "s/__FORGE_MODEL__/${MODEL//\//\\/}/g" "${ROOT_DIR}/k8s/policies.yaml" > "${GENERATED_DIR}/policies.yaml"
sed "s/__FORGE_MODEL__/${MODEL//\//\\/}/g" "${ROOT_DIR}/k8s/forge.yaml" > "${GENERATED_DIR}/forge.yaml"
KUBE_API_IP="$(kubectl get service kubernetes -o jsonpath='{.spec.clusterIP}')"
KUBE_API_ENDPOINT_IP="$(kubectl get endpointslice \
  -l kubernetes.io/service-name=kubernetes \
  -o jsonpath='{.items[0].endpoints[0].addresses[0]}')"
KUBE_API_ENDPOINT_PORT="$(kubectl get endpointslice \
  -l kubernetes.io/service-name=kubernetes \
  -o jsonpath='{.items[0].ports[0].port}')"
sed \
  -e "s/__KUBE_API_IP__/${KUBE_API_IP}/g" \
  -e "s/__KUBE_API_ENDPOINT_IP__/${KUBE_API_ENDPOINT_IP}/g" \
  -e "s/__KUBE_API_ENDPOINT_PORT__/${KUBE_API_ENDPOINT_PORT}/g" \
  "${ROOT_DIR}/k8s/forge-spawn-networkpolicy.yaml" \
  > "${GENERATED_DIR}/forge-spawn-networkpolicy.yaml"

kubectl apply -f "${ROOT_DIR}/k8s/workspace-mcp.yaml"
kubectl -n kars-mcp rollout status deployment/forge-workspace-mcp --timeout=180s
kubectl apply -f "${GENERATED_DIR}/policies.yaml"
kubectl apply -f "${GENERATED_DIR}/forge.yaml"
kubectl -n kars-system wait \
  --for=jsonpath='{.status.phase}'=Running \
  karssandbox/forge \
  --timeout=300s
kubectl apply -f "${GENERATED_DIR}/forge-spawn-networkpolicy.yaml"

echo "Forge is running with GitHub Copilot model ${MODEL}."
echo "Connect with: kars connect forge"
