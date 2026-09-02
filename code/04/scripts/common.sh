#!/usr/bin/env bash
set -euo pipefail

LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "${LAB_ROOT}/../.." && pwd)"
CODE01_ROOT="${REPO_ROOT}/code/01"
EVIDENCE_ROOT="${LAB_ROOT}/.evidence"
RUN_ID="${RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
EVIDENCE_DIR="${EVIDENCE_DIR:-${EVIDENCE_ROOT}/${RUN_ID}}"
MCP_PORT="${MCP_PORT:-18931}"
MCP_URL="http://127.0.0.1:${MCP_PORT}/mcp"

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

for command in kubectl jq curl sed; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "Required command not found: ${command}" >&2
    exit 1
  fi
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

require_forge() {
  [[ "$(kubectl -n kars-system get karssandbox forge -o jsonpath='{.status.phase}' 2>/dev/null || true)" == "Running" ]] \
    || fail "Deploy code/01 before running code/04"
  kubectl -n kars-mcp rollout status deployment/forge-workspace-mcp \
    --timeout=120s >/dev/null
}

verify_microsoft_sources() {
  grep -q 'https://packagefeedproxy.microsoft.io/npm/' "${CODE01_ROOT}/.npmrc"
  grep -q 'https://packagefeedproxy.microsoft.io/pypi/simple/' "${CODE01_ROOT}/pip.conf"
  grep -q 'https://packagefeedproxy.microsoft.io/nuget/v3/index.json' "${CODE01_ROOT}/NuGet.Config"
  "${CODE01_ROOT}/scripts/verify-npm-source.sh" >/dev/null
  pass "Microsoft npm, PyPI, and NuGet package sources are configured"
}

mcp_request() {
  local id="$1"
  local method="$2"
  local params="$3"

  curl -sS \
    -H 'content-type: application/json' \
    -H 'accept: application/json, text/event-stream' \
    --data "$(jq -cn \
      --argjson id "${id}" \
      --arg method "${method}" \
      --argjson params "${params}" \
      '{jsonrpc:"2.0",id:$id,method:$method,params:$params}')" \
    "${MCP_URL}" |
    sed -n 's/^data: //p'
}

mcp_tool() {
  local id="$1"
  local name="$2"
  local arguments="$3"
  mcp_request "${id}" tools/call "$(jq -cn \
    --arg name "${name}" \
    --argjson arguments "${arguments}" \
    '{name:$name,arguments:$arguments}')"
}
