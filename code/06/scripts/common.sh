#!/usr/bin/env bash
set -euo pipefail

LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "${LAB_ROOT}/../.." && pwd)"
CODE01_ROOT="${REPO_ROOT}/code/01"
CODE05_ROOT="${REPO_ROOT}/code/05"
EVIDENCE_ROOT="${LAB_ROOT}/.evidence"
RUN_ID="${RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
EVIDENCE_DIR="${EVIDENCE_DIR:-${EVIDENCE_ROOT}/${RUN_ID}}"
SANDBOX_NAME="forge-byo-copilot-claw"
SANDBOX_NAMESPACE="kars-${SANDBOX_NAME}"
POLICY_NAME="forge-byo-inference"
APP_PORT="${APP_PORT:-18086}"
ROUTER_PORT="${ROUTER_PORT:-18444}"

export RUN_ID EVIDENCE_DIR
export npm_config_registry="https://packagefeedproxy.microsoft.io/npm/"
export pnpm_config_registry="https://packagefeedproxy.microsoft.io/npm/"
export npm_config_replace_registry_host="registry.npmjs.org"
export npm_config_omit_lockfile_registry_resolved="true"
export npm_config_allow_remote="all"
export npm_config_package_lock="false"
export PIP_INDEX_URL="https://packagefeedproxy.microsoft.io/pypi/simple/"
export NUGET_CONFIG_FILE="${CODE01_ROOT}/NuGet.Config"
export GITHUB_COPILOT_MODEL="gpt-5.6-sol"

source "${CODE01_ROOT}/scripts/platform-env.sh"

for command in kubectl jq curl python3 git; do
  command -v "${command}" >/dev/null 2>&1 \
    || { echo "Required command not found: ${command}" >&2; exit 1; }
done

mkdir -p "${EVIDENCE_DIR}"

pass() {
  printf 'PASS: %s\n' "$1"
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

require_code05() {
  [[ "$(kubectl --context kind-kars-dev -n kars-system get \
    "karssandbox/${SANDBOX_NAME}" -o jsonpath='{.status.phase}' 2>/dev/null || true)" == "Running" ]] \
    || fail "Run code/05 before code/06"
  kubectl --context kind-kars-dev -n "${SANDBOX_NAMESPACE}" rollout status \
    "deployment/${SANDBOX_NAME}" --timeout=120s >/dev/null
}

verify_microsoft_sources() {
  grep -q 'https://packagefeedproxy.microsoft.io/npm/' "${CODE01_ROOT}/.npmrc"
  grep -q 'https://packagefeedproxy.microsoft.io/pypi/simple/' "${CODE01_ROOT}/pip.conf"
  grep -q 'https://packagefeedproxy.microsoft.io/nuget/v3/index.json' "${CODE01_ROOT}/NuGet.Config"
  "${CODE01_ROOT}/scripts/verify-npm-source.sh" >/dev/null
  pass "Microsoft npm, PyPI, and NuGet package sources are configured"
}

wait_for_http() {
  local url="$1"
  for _ in $(seq 1 90); do
    curl -fsS "${url}" >/dev/null 2>&1 && return
    sleep 1
  done
  fail "Timed out waiting for ${url}"
}

wait_for_policy() {
  local expected_tokens="$1"
  for _ in $(seq 1 90); do
    local values
    values="$(kubectl --context kind-kars-dev -n kars-system get \
      "inferencepolicy/${POLICY_NAME}" -o json |
      jq -r '[
        .spec.tokenBudget.perRequestTokens,
        .metadata.generation,
        .status.observedGeneration,
        (.status.compiledDigest == .status.loadedDigest),
        .status.phase
      ] | @tsv')"
    if [[ "${values}" == "${expected_tokens}"$'\t'*$'\t'"true"$'\t'"Ready" ]]; then
      local generation observed
      generation="$(cut -f2 <<<"${values}")"
      observed="$(cut -f3 <<<"${values}")"
      [[ "${generation}" == "${observed}" ]] && return
    fi
    sleep 2
  done
  fail "InferencePolicy did not converge with perRequestTokens=${expected_tokens}"
}
