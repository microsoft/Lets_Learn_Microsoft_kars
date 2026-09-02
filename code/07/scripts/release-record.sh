#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

location="$(resolve_location)"
pod="$(kubectl --context kind-kars-dev -n kars-forge-byo-copilot-claw get pod \
  -o jsonpath='{.items[0].metadata.name}')"
image_id="$(kubectl --context kind-kars-dev -n kars-forge-byo-copilot-claw \
  get pod "${pod}" -o json |
  jq -r '.status.containerStatuses[] | select(.name=="agent") | .imageID')"
policy_digest="$(kubectl --context kind-kars-dev -n kars-system get \
  inferencepolicy/forge-byo-inference -o jsonpath='{.status.loadedDigest}')"

jq -n \
  --arg recordedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg repositoryCommit "$(git -C "${REPO_ROOT}" rev-parse HEAD)" \
  --arg karsVersion "$(kars --version | head -1)" \
  --arg model "${GITHUB_COPILOT_MODEL}" \
  --arg sourceRuntime "BYO" \
  --arg sourceImageId "${image_id}" \
  --arg sourcePolicyDigest "${policy_digest}" \
  --arg resourceGroup "${AZURE_RESOURCE_GROUP}" \
  --arg clusterName "${AKS_NAME}" \
  --arg location "${location}" \
  '{
    recordedAt:$recordedAt,
    repositoryCommit:$repositoryCommit,
    karsVersion:$karsVersion,
    model:$model,
    sourceRuntime:$sourceRuntime,
    sourceImageId:$sourceImageId,
    sourcePolicyDigest:$sourcePolicyDigest,
    target:{
      resourceGroup:$resourceGroup,
      clusterName:$clusterName,
      location:$location,
      deployed:false
    }
  }' >"${EVIDENCE_DIR}/promotion-record.json"

pass "Promotion record links the code/05 image and code/06 policy to the AKS plan"
