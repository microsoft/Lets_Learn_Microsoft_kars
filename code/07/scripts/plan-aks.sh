#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

location="$(resolve_location)"

jq -n \
  --arg resourceGroup "${AZURE_RESOURCE_GROUP}" \
  --arg clusterName "${AKS_NAME}" \
  --arg location "${location}" \
  --arg sandboxName "${KARS_SANDBOX_NAME}" \
  --arg release "${KARS_RELEASE}" \
  --arg isolation "${KARS_ISOLATION}" \
  --arg meshTrust "${KARS_MESH_TRUST}" \
  --arg model "${GITHUB_COPILOT_MODEL}" \
  '{
    mode:"plan-only",
    createsAzureResources:false,
    resourceGroup:$resourceGroup,
    clusterName:$clusterName,
    location:$location,
    sandboxName:$sandboxName,
    release:$release,
    isolation:$isolation,
    meshTrust:$meshTrust,
    model:$model,
    day0:{
      network:"KARS-managed AKS networking; verify Azure CNI/Cilium after deployment",
      identity:"OIDC issuer and Workload Identity",
      apiExposure:"no direct public inference-router exposure"
    },
    day1:{
      observability:"Azure Monitor plus exported KARS audit/metrics",
      gitops:"apply reviewed Builder and Reviewer resources",
      recovery:"reuse code/06 policy and Pod recovery checks"
    }
  }' >"${EVIDENCE_DIR}/aks-plan.json"

printf '%q ' kars up \
  --name "${KARS_SANDBOX_NAME}" \
  --model "${GITHUB_COPILOT_MODEL}" \
  --policy developer \
  --region "${location}" \
  --cluster-name "${AKS_NAME}" \
  --resource-group "${AZURE_RESOURCE_GROUP}" \
  --isolation "${KARS_ISOLATION}" \
  --release "${KARS_RELEASE}" \
  --mesh-trust "${KARS_MESH_TRUST}" \
  --dry-run \
  --yes >"${EVIDENCE_DIR}/kars-up-command.txt"
printf '\n' >>"${EVIDENCE_DIR}/kars-up-command.txt"

kars up \
  --name "${KARS_SANDBOX_NAME}" \
  --model "${GITHUB_COPILOT_MODEL}" \
  --policy developer \
  --region "${location}" \
  --cluster-name "${AKS_NAME}" \
  --resource-group "${AZURE_RESOURCE_GROUP}" \
  --isolation "${KARS_ISOLATION}" \
  --release "${KARS_RELEASE}" \
  --mesh-trust "${KARS_MESH_TRUST}" \
  --dry-run \
  --yes >"${EVIDENCE_DIR}/kars-up-dry-run.txt"

jq -e '
  .mode == "plan-only"
  and .createsAzureResources == false
  and .model == "gpt-5.6-sol"
  and (.resourceGroup | length > 0)
  and (.clusterName | length > 0)
  and (.location | length > 0)
' "${EVIDENCE_DIR}/aks-plan.json" >/dev/null \
  || fail "AKS plan is incomplete"

grep -q "Steps that would execute" "${EVIDENCE_DIR}/kars-up-dry-run.txt" \
  || fail "KARS dry-run output was not captured"
pass "KARS AKS plan completed without creating Azure resources"
