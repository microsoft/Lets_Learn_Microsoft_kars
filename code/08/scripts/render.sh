#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

: "${FORGE_IMAGE:?Set FORGE_IMAGE to a sha256-pinned image reference}"
[[ "${FORGE_IMAGE}" == *.azurecr.io/*@sha256:* ]] \
  || fail "FORGE_IMAGE must be an ACR sha256 digest reference"

sed \
  -e "s|__SANDBOX__|${KARS_SANDBOX_NAME}|g" \
  -e "s|__MODEL__|${GITHUB_COPILOT_MODEL}|g" \
  -e "s|__IMAGE__|${FORGE_IMAGE}|g" \
  -e "s|__SUPPORT_OWNER__|${SUPPORT_OWNER}|g" \
  -e "s|__CONCURRENCY__|${TASK_CONCURRENCY_LIMIT}|g" \
  -e "s|__DAILY_LIMIT__|${DAILY_TASK_LIMIT}|g" \
  "${LAB_ROOT}/manifests/release-pilot.yaml.template" \
  >"${RENDERED_DIR}/release-pilot.yaml"
sed \
  -e "s|__SANDBOX__|${KARS_SANDBOX_NAME}|g" \
  "${LAB_ROOT}/manifests/mcp-and-eval.yaml.template" \
  >"${RENDERED_DIR}/mcp-and-eval.yaml"
pass "Release Pilot resources rendered"
