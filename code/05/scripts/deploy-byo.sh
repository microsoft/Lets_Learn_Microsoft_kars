#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

docker build \
  --platform "${CONTAINER_PLATFORM}" \
  --build-arg PIP_INDEX_URL="${PIP_INDEX_URL}" \
  --tag "${IMAGE_NAME}" \
  "${LAB_ROOT}/byo_agent"
kind load docker-image --name kars-dev "${IMAGE_NAME}"

docker image inspect "${IMAGE_NAME}" |
  jq '.[0] | {
    imageId: .Id,
    architecture: .Architecture,
    user: .Config.User,
    contractLabel: .Config.Labels["org.kars.runtime.contract"]
  }' >"${EVIDENCE_DIR}/image-contract.json"
jq -e '
  .user == "1000"
  and .contractLabel == "v1"
' "${EVIDENCE_DIR}/image-contract.json" >/dev/null \
  || fail "BYO image does not satisfy the UID and OCI label contract"
pass "BYO image declares contract v1 and runs as UID 1000"

kubectl --context kind-kars-dev apply --dry-run=server \
  -f "${LAB_ROOT}/manifests/maf-python-valid.yaml" \
  >"${EVIDENCE_DIR}/maf-python-dry-run.txt"
pass "Live CRD accepts the MicrosoftAgentFramework Python runtime shape"

if kubectl --context kind-kars-dev apply --dry-run=server \
  -f "${LAB_ROOT}/manifests/maf-dotnet-invalid.yaml" \
  >"${EVIDENCE_DIR}/maf-dotnet-denial.txt" 2>&1; then
  fail "Live CRD unexpectedly accepted MicrosoftAgentFramework dotnet"
fi
grep -q 'Unsupported value: "dotnet"' "${EVIDENCE_DIR}/maf-dotnet-denial.txt" \
  || fail "MAF dotnet denial did not come from the language enum"
pass "Live CRD rejects the deferred MicrosoftAgentFramework dotnet shape"

if kubectl --context kind-kars-dev apply --dry-run=server \
  -f "${LAB_ROOT}/manifests/byo-contract-invalid.yaml" \
  >"${EVIDENCE_DIR}/byo-contract-denial.txt" 2>&1; then
  fail "Live CRD unexpectedly accepted BYO without contractVersion"
fi
grep -q 'contractVersion' "${EVIDENCE_DIR}/byo-contract-denial.txt" \
  || fail "BYO contract denial did not identify contractVersion"
pass "Live CRD requires an explicit BYO contractVersion"

kubectl --context kind-kars-dev apply -f "${LAB_ROOT}/manifests/byo.yaml"
kubectl --context kind-kars-dev -n "${SANDBOX_NAMESPACE}" rollout restart \
  "deployment/${SANDBOX_NAME}" 2>/dev/null || true
kubectl --context kind-kars-dev -n kars-system wait \
  --for=jsonpath='{.status.phase}'=Running \
  "karssandbox/${SANDBOX_NAME}" \
  --timeout=300s
kubectl --context kind-kars-dev -n "${SANDBOX_NAMESPACE}" rollout status \
  "deployment/${SANDBOX_NAME}" \
  --timeout=300s
pass "KARS reconciled the BYO runtime to Running"
