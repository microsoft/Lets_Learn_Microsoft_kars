#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"
require_forge

transcript="${EVIDENCE_DIR}/transcript.log"

restore_sources() {
  "${CODE01_ROOT}/scripts/configure-upstream-package-sources.sh" restore >/dev/null 2>&1 || true
}

cleanup_resources() {
  "${SCRIPT_DIR}/cleanup.sh" >/dev/null 2>&1 || true
}

trap 'cleanup_resources; restore_sources' EXIT

{
  echo "KARS Kubernetes API contract lab"
  echo "Run: ${RUN_ID}"
  echo "Host: $(uname -s) $(uname -m)"
  echo

  "${CODE01_ROOT}/scripts/configure-upstream-package-sources.sh" apply >/dev/null
  verify_microsoft_sources
  "${SCRIPT_DIR}/render.sh"

  kubectl explain karssandbox.spec --recursive \
    >"${EVIDENCE_DIR}/karssandbox-schema.txt"
  kubectl explain inferencepolicy.spec --recursive \
    >"${EVIDENCE_DIR}/inferencepolicy-schema.txt"
  kubectl get crd karssandboxes.kars.azure.com -o yaml \
    >"${EVIDENCE_DIR}/karssandbox-crd.yaml"

  EVIDENCE_DIR="${EVIDENCE_DIR}" RUN_ID="${RUN_ID}" "${SCRIPT_DIR}/validate-schema.sh"
  EVIDENCE_DIR="${EVIDENCE_DIR}" RUN_ID="${RUN_ID}" "${SCRIPT_DIR}/test-lifecycle.sh"
  EVIDENCE_DIR="${EVIDENCE_DIR}" RUN_ID="${RUN_ID}" "${SCRIPT_DIR}/test-cross-namespace.sh"
  EVIDENCE_DIR="${EVIDENCE_DIR}" RUN_ID="${RUN_ID}" "${SCRIPT_DIR}/test-invalid-provider.sh"

  kubectl -n kars-system get events --sort-by=.lastTimestamp \
    >"${EVIDENCE_DIR}/kars-system-events.txt"

  echo
  echo "All Kubernetes API contract checks passed."
  echo "Evidence: ${EVIDENCE_DIR}"
} 2>&1 | tee "${transcript}"
