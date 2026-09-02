#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

"${LAB_ROOT}/.venv/bin/python" "${LAB_ROOT}/scripts/validate_gitops.py" \
  "${RENDERED_DIR}/multi-agent.yaml"

kubectl --context kind-kars-dev apply \
  --dry-run=server \
  -f "${RENDERED_DIR}/multi-agent.yaml" \
  >"${EVIDENCE_DIR}/gitops-server-dry-run.txt"

pass "Live KARS CRDs accepted the Builder and Reviewer resources in server dry-run"
