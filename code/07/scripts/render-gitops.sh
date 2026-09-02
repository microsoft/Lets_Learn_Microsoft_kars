#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

[[ "${FORGE_IMAGE}" != *$'\n'* ]] || fail "FORGE_IMAGE must be one line"
[[ "${GITHUB_COPILOT_MODEL}" != *$'\n'* ]] || fail "Model must be one line"

sed \
  -e "s|__IMAGE__|${FORGE_IMAGE}|g" \
  -e "s|__MODEL__|${GITHUB_COPILOT_MODEL}|g" \
  "${LAB_ROOT}/gitops/base/multi-agent.yaml.template" \
  >"${RENDERED_DIR}/multi-agent.yaml"

pass "Builder and Reviewer GitOps resources rendered"
