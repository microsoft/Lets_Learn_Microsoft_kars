#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

transcript="${EVIDENCE_DIR}/transcript.log"

restore_sources() {
  "${CODE01_ROOT}/scripts/configure-upstream-package-sources.sh" restore >/dev/null 2>&1 || true
}
trap restore_sources EXIT

{
  echo "Forge sandbox boundary lab"
  echo "Run: ${RUN_ID}"
  echo "Host: $(uname -s) $(uname -m)"
  echo

  "${CODE01_ROOT}/scripts/configure-upstream-package-sources.sh" apply >/dev/null
  verify_microsoft_sources
  EVIDENCE_DIR="${EVIDENCE_DIR}" RUN_ID="${RUN_ID}" "${SCRIPT_DIR}/inspect.sh"
  EVIDENCE_DIR="${EVIDENCE_DIR}" RUN_ID="${RUN_ID}" "${SCRIPT_DIR}/test-static.sh"
  EVIDENCE_DIR="${EVIDENCE_DIR}" RUN_ID="${RUN_ID}" "${SCRIPT_DIR}/test-break-glass.sh"
  EVIDENCE_DIR="${EVIDENCE_DIR}" RUN_ID="${RUN_ID}" "${SCRIPT_DIR}/test-degraded.sh"
  EVIDENCE_DIR="${EVIDENCE_DIR}" RUN_ID="${RUN_ID}" "${SCRIPT_DIR}/test-reconcile.sh"

  echo
  echo "All requested sandbox boundary checks passed."
  echo "Evidence: ${EVIDENCE_DIR}"
} 2>&1 | tee "${transcript}"
