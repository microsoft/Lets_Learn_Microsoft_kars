#!/usr/bin/env bash
set -euo pipefail

LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "${LAB_ROOT}/../.." && pwd)"
CODE01_ROOT="${REPO_ROOT}/code/01"
GENERATED_DIR="${LAB_ROOT}/.generated"
EVIDENCE_ROOT="${LAB_ROOT}/.evidence"
RUN_ID="${RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
EVIDENCE_DIR="${EVIDENCE_DIR:-${EVIDENCE_ROOT}/${RUN_ID}}"
FIELD_MANAGER="code03-lab"

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

for command in kubectl jq sed curl; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "Required command not found: ${command}" >&2
    exit 1
  fi
done

kubectl() {
  command kubectl --context "${KARS_KUBE_CONTEXT}" "$@"
}

mkdir -p "${GENERATED_DIR}" "${EVIDENCE_DIR}"

pass() {
  printf 'PASS: %s\n' "$1"
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

require_forge() {
  local phase
  phase="$(kubectl -n kars-system get karssandbox forge -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  [[ "${phase}" == "Running" ]] || fail "Deploy code/01 before running code/03"
}

model_name() {
  local configured
  configured="$(kubectl -n kars-system get karssandbox forge \
    -o jsonpath='{.spec.runtime.openclaw.config.agent.model}')"
  printf '%s\n' "${configured#azure/}"
}

wait_for_sandbox() {
  local name="$1"
  local expected_phase="$2"
  local timeout_seconds="${3:-240}"
  local deadline=$((SECONDS + timeout_seconds))

  while (( SECONDS < deadline )); do
    local object phase generation observed
    object="$(kubectl -n kars-system get karssandbox "${name}" -o json 2>/dev/null || true)"
    if [[ -n "${object}" ]]; then
      phase="$(jq -r '.status.phase // ""' <<<"${object}")"
      generation="$(jq -r '.metadata.generation // 0' <<<"${object}")"
      observed="$(jq -r '.status.observedGeneration // 0' <<<"${object}")"
      if [[ "${phase}" == "${expected_phase}" && "${generation}" == "${observed}" ]]; then
        return 0
      fi
    fi
    sleep 2
  done

  kubectl -n kars-system get karssandbox "${name}" -o yaml >&2 || true
  fail "${name} did not reach ${expected_phase} with current observedGeneration"
}

verify_microsoft_sources() {
  grep -q 'https://packagefeedproxy.microsoft.io/npm/' "${CODE01_ROOT}/.npmrc"
  grep -q 'https://packagefeedproxy.microsoft.io/pypi/simple/' "${CODE01_ROOT}/pip.conf"
  grep -q 'https://packagefeedproxy.microsoft.io/nuget/v3/index.json' "${CODE01_ROOT}/NuGet.Config"
  "${CODE01_ROOT}/scripts/verify-npm-source.sh" >/dev/null
  pass "Microsoft npm, PyPI, and NuGet package sources are configured"
}
