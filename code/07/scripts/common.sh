#!/usr/bin/env bash
set -euo pipefail

LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "${LAB_ROOT}/../.." && pwd)"
CODE01_ROOT="${REPO_ROOT}/code/01"
CODE05_ROOT="${REPO_ROOT}/code/05"
CODE06_ROOT="${REPO_ROOT}/code/06"
EVIDENCE_ROOT="${LAB_ROOT}/.evidence"
RUN_ID="${RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
EVIDENCE_DIR="${EVIDENCE_DIR:-${EVIDENCE_ROOT}/${RUN_ID}}"
RENDERED_DIR="${LAB_ROOT}/rendered"

if [[ -f "${LAB_ROOT}/config/aks.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "${LAB_ROOT}/config/aks.env"
  set +a
fi

AZURE_RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-your-resource-group}"
AKS_NAME="${AKS_NAME:-your-aks-cluster}"
KARS_ACR_NAME="${KARS_ACR_NAME:-yourkarsregistry}"
LOG_ANALYTICS_WORKSPACE="${LOG_ANALYTICS_WORKSPACE:-your-log-analytics-workspace}"
AZURE_LOCATION="${AZURE_LOCATION:-}"
KARS_SANDBOX_NAME="${KARS_SANDBOX_NAME:-forge-intake}"
KARS_RELEASE="${KARS_RELEASE:-v0.1.25}"
KARS_ISOLATION="${KARS_ISOLATION:-enhanced}"
KARS_MESH_TRUST="${KARS_MESH_TRUST:-anonymous}"
GITHUB_COPILOT_MODEL="${GITHUB_COPILOT_MODEL:-gpt-5.6-sol}"
DEPLOY_AKS="${DEPLOY_AKS:-false}"
FORGE_IMAGE="${FORGE_IMAGE:-forge-byo-copilot-claw:dev}"
KARS_SOURCE_ROOT="${KARS_SOURCE_ROOT:-${REPO_ROOT}/../../kars}"

export RUN_ID EVIDENCE_DIR
export AZURE_RESOURCE_GROUP AKS_NAME KARS_ACR_NAME LOG_ANALYTICS_WORKSPACE
export AZURE_LOCATION KARS_SOURCE_ROOT
export KARS_SANDBOX_NAME KARS_RELEASE KARS_ISOLATION KARS_MESH_TRUST
export GITHUB_COPILOT_MODEL DEPLOY_AKS FORGE_IMAGE
export npm_config_registry="https://packagefeedproxy.microsoft.io/npm/"
export pnpm_config_registry="https://packagefeedproxy.microsoft.io/npm/"
export npm_config_replace_registry_host="registry.npmjs.org"
export npm_config_omit_lockfile_registry_resolved="true"
export npm_config_allow_remote="all"
export npm_config_package_lock="false"
export PIP_INDEX_URL="https://packagefeedproxy.microsoft.io/pypi/simple/"
export NUGET_CONFIG_FILE="${CODE01_ROOT}/NuGet.Config"

mkdir -p "${EVIDENCE_DIR}" "${RENDERED_DIR}"

pass() {
  printf 'PASS: %s\n' "$1"
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

resolve_location() {
  if [[ -n "${AZURE_LOCATION}" ]]; then
    printf '%s\n' "${AZURE_LOCATION}"
    return
  fi

  local resource_group_location
  resource_group_location="$(az group show \
    --name "${AZURE_RESOURCE_GROUP}" \
    --query location -o tsv 2>/dev/null || true)"
  if [[ -n "${resource_group_location}" ]]; then
    printf '%s\n' "${resource_group_location}"
  else
    printf 'eastus2\n'
  fi
}

require_predecessors() {
  local phase tokens generation observed
  phase="$(kubectl --context kind-kars-dev -n kars-system get \
    karssandbox/forge-byo-copilot-claw \
    -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  [[ "${phase}" == "Running" ]] || fail "Run code/05 before code/07"

  tokens="$(kubectl --context kind-kars-dev -n kars-system get \
    inferencepolicy/forge-byo-inference \
    -o jsonpath='{.spec.tokenBudget.perRequestTokens}')"
  generation="$(kubectl --context kind-kars-dev -n kars-system get \
    inferencepolicy/forge-byo-inference \
    -o jsonpath='{.metadata.generation}')"
  observed="$(kubectl --context kind-kars-dev -n kars-system get \
    inferencepolicy/forge-byo-inference \
    -o jsonpath='{.status.observedGeneration}')"
  [[ "${tokens}" == "1024" && "${generation}" == "${observed}" ]] \
    || fail "Run code/06 recovery before code/07"

  kubectl --context kind-kars-dev get \
    validatingadmissionpolicy/kars-byo-agent-exec-ban >/dev/null 2>&1 \
    || fail "Run code/06 before code/07"
}

verify_microsoft_sources() {
  grep -q 'https://packagefeedproxy.microsoft.io/npm/' "${CODE01_ROOT}/.npmrc"
  grep -q 'https://packagefeedproxy.microsoft.io/pypi/simple/' "${CODE01_ROOT}/pip.conf"
  grep -q 'https://packagefeedproxy.microsoft.io/nuget/v3/index.json' "${CODE01_ROOT}/NuGet.Config"
  "${CODE01_ROOT}/scripts/verify-npm-source.sh" >/dev/null
  pass "Microsoft npm, PyPI, and NuGet package sources are configured"
}

for command in az kars kubectl jq python3 git; do
  command -v "${command}" >/dev/null 2>&1 \
    || fail "Required command not found: ${command}"
done
