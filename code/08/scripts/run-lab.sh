#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

exec > >(tee "${EVIDENCE_DIR}/transcript.log") 2>&1
printf 'OpenClaw-first KARS applied release project\n'
printf 'Run: %s\n\n' "${RUN_ID}"

"${LAB_ROOT}/scripts/setup.sh"
FORGE_IMAGE="${KARS_ACR_NAME}.azurecr.io/fabrikam-release-pilot@sha256:$(printf validation | shasum -a 256 | awk '{print $1}')" \
  "${LAB_ROOT}/scripts/render.sh"
"${LAB_ROOT}/scripts/validate.sh"

printf '\nAll local applied-project checks passed.\n'
printf 'No Azure resources were changed.\n'
