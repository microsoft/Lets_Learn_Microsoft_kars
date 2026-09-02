#!/usr/bin/env bash
set -euo pipefail

LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "${LAB_ROOT}/../.." && pwd)"
CODE01_ROOT="${REPO_ROOT}/code/01"
EVIDENCE_ROOT="${LAB_ROOT}/.evidence"
RUN_ID="${RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
EVIDENCE_DIR="${EVIDENCE_DIR:-${EVIDENCE_ROOT}/${RUN_ID}}"

source "${CODE01_ROOT}/scripts/platform-env.sh"
KARS_KUBE_CONTEXT="${KARS_KUBE_CONTEXT:-kind-kars-dev}"

export npm_config_registry="https://packagefeedproxy.microsoft.io/npm/"
export pnpm_config_registry="https://packagefeedproxy.microsoft.io/npm/"
export npm_config_replace_registry_host="registry.npmjs.org"
export npm_config_omit_lockfile_registry_resolved="true"
export npm_config_allow_remote="all"
export npm_config_package_lock="false"
export PIP_INDEX_URL="https://packagefeedproxy.microsoft.io/pypi/simple/"
export NUGET_CONFIG_FILE="${CODE01_ROOT}/NuGet.Config"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 1
  fi
}

for command in kubectl jq curl; do
  require_command "${command}"
done

kubectl() {
  command kubectl --context "${KARS_KUBE_CONTEXT}" "$@"
}

mkdir -p "${EVIDENCE_DIR}"

pass() {
  printf 'PASS: %s\n' "$1"
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

forge_namespace() {
  kubectl -n kars-system get karssandbox forge -o jsonpath='{.status.namespace}'
}

forge_pod() {
  local namespace
  namespace="$(forge_namespace)"
  kubectl -n "${namespace}" get pod \
    -l kars.azure.com/sandbox=forge \
    -o jsonpath='{.items[0].metadata.name}'
}

require_forge() {
  local phase
  phase="$(kubectl -n kars-system get karssandbox forge -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  if [[ "${phase}" != "Running" ]]; then
    echo "Forge is not Running. Deploy code/01 first with 'make deploy'." >&2
    exit 1
  fi
}

verify_microsoft_sources() {
  grep -q 'https://packagefeedproxy.microsoft.io/npm/' "${CODE01_ROOT}/.npmrc"
  grep -q 'https://packagefeedproxy.microsoft.io/pypi/simple/' "${CODE01_ROOT}/pip.conf"
  grep -q 'https://packagefeedproxy.microsoft.io/nuget/v3/index.json' "${CODE01_ROOT}/NuGet.Config"
  "${CODE01_ROOT}/scripts/verify-npm-source.sh" >/dev/null
  pass "Microsoft npm, PyPI, and NuGet package sources are configured"
}
