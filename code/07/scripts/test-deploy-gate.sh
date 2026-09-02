#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

if DEPLOY_AKS=false "${LAB_ROOT}/scripts/deploy-aks.sh" \
  >"${EVIDENCE_DIR}/deploy-opt-in-denial.txt" 2>&1; then
  fail "AKS deployment unexpectedly ran without explicit opt-in"
fi
grep -q "DEPLOY_AKS=true" "${EVIDENCE_DIR}/deploy-opt-in-denial.txt" \
  || fail "Deployment opt-in denial was not explicit"

if DEPLOY_AKS=true KARS_SOURCE_ROOT="${LAB_ROOT}/missing-kars-source" \
  "${LAB_ROOT}/scripts/deploy-aks.sh" \
  >"${EVIDENCE_DIR}/deploy-source-denial.txt" 2>&1; then
  fail "AKS deployment unexpectedly accepted a missing KARS source checkout"
fi
grep -q "KARS_SOURCE_ROOT" "${EVIDENCE_DIR}/deploy-source-denial.txt" \
  || fail "Missing KARS source denial was not explicit"

pass "Real AKS deployment requires explicit opt-in and an upstream KARS source checkout"
