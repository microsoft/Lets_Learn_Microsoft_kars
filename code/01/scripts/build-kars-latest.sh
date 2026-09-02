#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE_DIR="${ROOT_DIR}/.cache/upstream"
KARS_DIR="${CACHE_DIR}/kars"
AGT_DIR="${CACHE_DIR}/agent-governance-toolkit"

source "${ROOT_DIR}/scripts/platform-env.sh"
export npm_config_registry="https://packagefeedproxy.microsoft.io/npm/"
export pnpm_config_registry="https://packagefeedproxy.microsoft.io/npm/"
export npm_config_replace_registry_host="registry.npmjs.org"
export npm_config_omit_lockfile_registry_resolved="true"
export npm_config_allow_remote="all"
export npm_config_package_lock="false"
export PIP_INDEX_URL="https://packagefeedproxy.microsoft.io/pypi/simple/"
export NUGET_CONFIG_FILE="${ROOT_DIR}/NuGet.Config"

update_checkout() {
  local url="$1"
  local directory="$2"

  if [[ ! -d "${directory}/.git" ]]; then
    git clone --filter=blob:none "${url}" "${directory}"
  else
    if [[ -n "$(git -C "${directory}" status --porcelain)" ]]; then
      echo "Refusing to update dirty checkout: ${directory}" >&2
      exit 1
    fi
    git -C "${directory}" fetch origin main
    git -C "${directory}" checkout main
    git -C "${directory}" merge --ff-only origin/main
  fi
}

mkdir -p "${CACHE_DIR}"
"${ROOT_DIR}/scripts/configure-upstream-package-sources.sh" restore 2>/dev/null || true
update_checkout https://github.com/Azure/kars.git "${KARS_DIR}"
update_checkout https://github.com/microsoft/agent-governance-toolkit.git "${AGT_DIR}"

pushd "${KARS_DIR}/cli" >/dev/null
npm ci
npm run build
npm link
popd >/dev/null

cat > "${ROOT_DIR}/.kars-source-version" <<EOF
KARS_COMMIT=$(git -C "${KARS_DIR}" rev-parse HEAD)
AGT_COMMIT=$(git -C "${AGT_DIR}" rev-parse HEAD)
BUILT_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
NODE_VERSION=$(node --version)
NPM_REGISTRY=${npm_config_registry}
PIP_INDEX_URL=${PIP_INDEX_URL}
NUGET_SOURCE=https://packagefeedproxy.microsoft.io/nuget/v3/index.json
EOF

echo "Built KARS $(git -C "${KARS_DIR}" rev-parse --short HEAD)"
echo "AGT source $(git -C "${AGT_DIR}" rev-parse --short HEAD)"
