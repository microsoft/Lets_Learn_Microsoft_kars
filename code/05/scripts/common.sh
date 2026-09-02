#!/usr/bin/env bash
set -euo pipefail

LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "${LAB_ROOT}/../.." && pwd)"
CODE01_ROOT="${REPO_ROOT}/code/01"
VENV_DIR="${LAB_ROOT}/.venv"
EVIDENCE_ROOT="${LAB_ROOT}/.evidence"
RUN_ID="${RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
EVIDENCE_DIR="${EVIDENCE_DIR:-${EVIDENCE_ROOT}/${RUN_ID}}"
SANDBOX_NAME="forge-byo-copilot-claw"
SANDBOX_NAMESPACE="kars-${SANDBOX_NAME}"
IMAGE_NAME="forge-byo-copilot-claw:dev"
LOCAL_PORT="${LOCAL_PORT:-18085}"

export RUN_ID EVIDENCE_DIR

source "${CODE01_ROOT}/scripts/platform-env.sh"

export npm_config_registry="https://packagefeedproxy.microsoft.io/npm/"
export pnpm_config_registry="https://packagefeedproxy.microsoft.io/npm/"
export npm_config_replace_registry_host="registry.npmjs.org"
export npm_config_omit_lockfile_registry_resolved="true"
export npm_config_allow_remote="all"
export npm_config_package_lock="false"
export PIP_INDEX_URL="https://packagefeedproxy.microsoft.io/pypi/simple/"
export NUGET_CONFIG_FILE="${CODE01_ROOT}/NuGet.Config"
export GITHUB_COPILOT_MODEL="gpt-5.6-sol"
export GITHUB_COPILOT_CLI_PATH="${GITHUB_COPILOT_CLI_PATH:-$(command -v copilot || true)}"

for command in docker kind kubectl jq curl python3; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "Required command not found: ${command}" >&2
    exit 1
  fi
done

mkdir -p "${EVIDENCE_DIR}"

pass() {
  printf 'PASS: %s\n' "$1"
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

require_forge() {
  [[ "$(kubectl --context kind-kars-dev -n kars-system get karssandbox forge \
    -o jsonpath='{.status.phase}' 2>/dev/null || true)" == "Running" ]] \
    || fail "Deploy code/01 before running code/05"
  [[ "$(jq -r '.provider // empty' "${HOME}/.kars/config.json" 2>/dev/null)" == "github-copilot" ]] \
    || fail "KARS must use the github-copilot provider"
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
  for _ in $(seq 1 60); do
    if curl -fsS "${url}" >/dev/null 2>&1; then
      return
    fi
    sleep 1
  done
  fail "Timed out waiting for ${url}"
}
