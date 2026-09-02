#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

restore_sources() {
  "${CODE01_ROOT}/scripts/configure-upstream-package-sources.sh" restore \
    >/dev/null 2>&1 || true
}
trap restore_sources EXIT

exec > >(tee "${EVIDENCE_DIR}/transcript.log") 2>&1

printf 'KARS AKS and multi-agent promotion lab\n'
printf 'Run: %s\n' "${RUN_ID}"
printf 'Host: %s %s\n\n' "$(uname -s)" "$(uname -m)"

require_predecessors
"${CODE01_ROOT}/scripts/configure-upstream-package-sources.sh" apply
verify_microsoft_sources
"${LAB_ROOT}/scripts/setup-python.sh"
"${LAB_ROOT}/scripts/test-unit.sh"

EVIDENCE_DIR="${EVIDENCE_DIR}" RUN_ID="${RUN_ID}" \
  "${CODE05_ROOT}/scripts/test-copilot-agent.sh"
pass "MAF GitHub Copilot canary used GPT-5.6-Sol before promotion"

"${LAB_ROOT}/scripts/render-gitops.sh"
"${LAB_ROOT}/scripts/validate-gitops.sh"
"${LAB_ROOT}/scripts/plan-aks.sh"
"${LAB_ROOT}/scripts/test-deploy-gate.sh"
"${LAB_ROOT}/scripts/release-record.sh"

printf '\nAll plan-only AKS and multi-agent checks passed.\n'
printf 'No Azure resources were created.\n'
printf 'Evidence: %s\n' "${EVIDENCE_DIR}"
