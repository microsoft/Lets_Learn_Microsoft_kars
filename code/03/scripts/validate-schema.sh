#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

"${LAB_ROOT}/scripts/render.sh" >/dev/null

kubectl apply --server-side --dry-run=server \
  --field-manager="${FIELD_MANAGER}" \
  -f "${GENERATED_DIR}/contract-v1.yaml" >/dev/null
kubectl apply --server-side --dry-run=server \
  --field-manager="${FIELD_MANAGER}" \
  -f "${GENERATED_DIR}/contract-v2.yaml" >/dev/null
kubectl apply --server-side --dry-run=server \
  --field-manager="${FIELD_MANAGER}" \
  -f "${LAB_ROOT}/manifests/invalid-provider.yaml" >/dev/null
pass "Valid KARS contracts pass server-side schema validation"

set +e
runtime_error="$(kubectl apply --server-side --dry-run=server \
  -f "${LAB_ROOT}/manifests/invalid-runtime.yaml" 2>&1)"
runtime_rc=$?
kind_error="$(kubectl apply --server-side --dry-run=server \
  -f "${LAB_ROOT}/manifests/invalid-kind-case.yaml" 2>&1)"
kind_rc=$?
set -e

[[ ${runtime_rc} -ne 0 ]] || fail "Unsupported runtime passed CRD validation"
[[ "${runtime_error}" == *"UnsupportedRuntime"* ]] \
  || fail "Unsupported runtime failed for an unexpected reason"
pass "CRD schema rejects an unsupported runtime"

[[ ${kind_rc} -ne 0 ]] || fail "Incorrect KarsSandbox kind casing was accepted"
[[ "${kind_error}" == *"no matches for kind"* ]] \
  || fail "Incorrect kind casing failed for an unexpected reason"
pass "Kubernetes API rejects incorrect kind casing"

printf '%s\n' "${runtime_error}" >"${EVIDENCE_DIR}/invalid-runtime.txt"
printf '%s\n' "${kind_error}" >"${EVIDENCE_DIR}/invalid-kind-case.txt"
