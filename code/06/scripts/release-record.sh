#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

pod="$(kubectl --context kind-kars-dev -n "${SANDBOX_NAMESPACE}" get pod \
  -o jsonpath='{.items[0].metadata.name}')"
image_id="$(kubectl --context kind-kars-dev -n "${SANDBOX_NAMESPACE}" get pod \
  "${pod}" -o json |
  jq -r '.status.containerStatuses[] | select(.name=="agent") | .imageID')"
policy_digest="$(kubectl --context kind-kars-dev -n kars-system get \
  "inferencepolicy/${POLICY_NAME}" -o jsonpath='{.status.loadedDigest}')"
kars_version="$(kars --version 2>/dev/null | head -1 || printf unknown)"

jq -n \
  --arg recordedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg repositoryCommit "$(git -C "${REPO_ROOT}" rev-parse HEAD)" \
  --arg karsVersion "${kars_version}" \
  --arg model "gpt-5.6-sol" \
  --arg runtime "BYO" \
  --arg imageId "${image_id}" \
  --arg inferencePolicyDigest "${policy_digest}" \
  '{
    recordedAt:$recordedAt,
    repositoryCommit:$repositoryCommit,
    karsVersion:$karsVersion,
    model:$model,
    runtime:$runtime,
    imageId:$imageId,
    inferencePolicyDigest:$inferencePolicyDigest
  }' >"${EVIDENCE_DIR}/release-record.json"
pass "Release record pins repository, KARS, model, runtime, image, and policy digest"
