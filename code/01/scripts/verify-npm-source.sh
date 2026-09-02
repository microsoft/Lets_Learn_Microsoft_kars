#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXPECTED_REGISTRY="https://packagefeedproxy.microsoft.io/npm/"

if [[ "$(npm config get registry)" != "${EXPECTED_REGISTRY}" ]]; then
  echo "npm registry must be ${EXPECTED_REGISTRY}" >&2
  exit 1
fi

BLOCKED_REFERENCES="$(grep -RIn \
  --include='package-lock.json' \
  --include='npm-shrinkwrap.json' \
  --include='pnpm-lock.yaml' \
  --include='Dockerfile*' \
  --exclude-dir=node_modules \
  --exclude-dir=.git \
  'registry.npmjs.org' \
  "${ROOT_DIR}/workspace-mcp" \
  "${ROOT_DIR}/.cache/upstream/kars" \
  "${ROOT_DIR}/.cache/upstream/openclaw" 2>/dev/null |
  grep -v 'NPM_CONFIG_REPLACE_REGISTRY_HOST=registry.npmjs.org' || true)"
if [[ -n "${BLOCKED_REFERENCES}" ]]; then
  echo "Blocked npm source registry.npmjs.org remains in an active build input." >&2
  echo "${BLOCKED_REFERENCES}" >&2
  exit 1
fi

if ! grep -qx 'registry=https://packagefeedproxy.microsoft.io/npm/' \
  "${ROOT_DIR}/.cache/upstream/openclaw/.npmrc"; then
  echo "OpenClaw pnpm registry is not pinned to the Microsoft package proxy." >&2
  exit 1
fi

if ! grep -q '^ENV PNPM_CONFIG_REGISTRY=https://packagefeedproxy.microsoft.io/npm/$' \
  "${ROOT_DIR}/.cache/upstream/openclaw/Dockerfile"; then
  echo "OpenClaw Docker build is missing PNPM_CONFIG_REGISTRY." >&2
  exit 1
fi

echo "npm source verified: ${EXPECTED_REGISTRY}"
