#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPENCLAW_DIR="${ROOT_DIR}/.cache/upstream/openclaw"
OPENCLAW_TAG="v2026.5.27"
OPENCLAW_COMMIT="27ae826f65256c7fbd1d78475fca87b674a53e7b"

source "${ROOT_DIR}/scripts/platform-env.sh"

if docker image inspect openclaw-source:dev >/dev/null 2>&1; then
  exit 0
fi

if [[ ! -d "${OPENCLAW_DIR}/.git" ]]; then
  git clone --depth 1 --branch "${OPENCLAW_TAG}" \
    https://github.com/openclaw/openclaw.git "${OPENCLAW_DIR}"
fi

if [[ "$(git -C "${OPENCLAW_DIR}" rev-parse HEAD)" != "${OPENCLAW_COMMIT}" ]]; then
  echo "OpenClaw checkout does not match ${OPENCLAW_TAG} (${OPENCLAW_COMMIT})." >&2
  exit 1
fi

"${ROOT_DIR}/scripts/configure-upstream-package-sources.sh" apply
"${ROOT_DIR}/scripts/verify-npm-source.sh"

docker build \
  --platform "${CONTAINER_PLATFORM}" \
  --target build \
  --build-arg OPENCLAW_EXTENSIONS="" \
  -t openclaw-source:dev \
  -f "${OPENCLAW_DIR}/Dockerfile" \
  "${OPENCLAW_DIR}"
