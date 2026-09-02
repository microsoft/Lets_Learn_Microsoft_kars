#!/usr/bin/env bash
set -euo pipefail

LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "${LAB_ROOT}/../.." && pwd)"
EVIDENCE_ROOT="${LAB_ROOT}/.evidence"
RUN_ID="${RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
EVIDENCE_DIR="${EVIDENCE_DIR:-${EVIDENCE_ROOT}/${RUN_ID}}"
RENDERED_DIR="${LAB_ROOT}/rendered"
STATE_DIR="${LAB_ROOT}/.state"

if [[ -f "${LAB_ROOT}/config/azure.env" ]]; then
  set -a
  source "${LAB_ROOT}/config/azure.env"
  set +a
fi

AZURE_RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-your-resource-group}"
AKS_NAME="${AKS_NAME:-your-aks-cluster}"
KARS_ACR_NAME="${KARS_ACR_NAME:-yourkarsregistry}"
AZURE_LOCATION="${AZURE_LOCATION:-}"
KARS_SANDBOX_NAME="${KARS_SANDBOX_NAME:-fabrikam-release-pilot}"
GITHUB_COPILOT_MODEL="${GITHUB_COPILOT_MODEL:-gpt-5.6-sol}"
KARS_RELEASE="${KARS_RELEASE:-v0.1.25}"
SUPPORT_OWNER="${SUPPORT_OWNER:-forge-operations}"
TASK_CONCURRENCY_LIMIT="${TASK_CONCURRENCY_LIMIT:-2}"
DAILY_TASK_LIMIT="${DAILY_TASK_LIMIT:-20}"
DEPLOY_AZURE="${DEPLOY_AZURE:-false}"
ROLLBACK_IMAGE="${ROLLBACK_IMAGE:-}"
if [[ -z "${KARS_KUBE_CONTEXT:-}" ]]; then
  if [[ "${DEPLOY_AZURE}" == "true" ]]; then
    KARS_KUBE_CONTEXT="${AKS_NAME}"
  else
    KARS_KUBE_CONTEXT="kind-kars-dev"
  fi
fi

export PIP_INDEX_URL="https://packagefeedproxy.microsoft.io/pypi/simple/"
export npm_config_registry="https://packagefeedproxy.microsoft.io/npm/"
export NUGET_CONFIG_FILE="${LAB_ROOT}/config/NuGet.Config"

mkdir -p "${EVIDENCE_DIR}" "${RENDERED_DIR}" "${STATE_DIR}"

pass() {
  printf 'PASS: %s\n' "$1"
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}
