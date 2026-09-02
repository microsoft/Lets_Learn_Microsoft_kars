#!/usr/bin/env bash
set -euo pipefail

requested_deploy="${DEPLOY_AZURE:-}"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
[[ -z "${requested_deploy}" ]] || DEPLOY_AZURE="${requested_deploy}"
[[ "${DEPLOY_AZURE}" == "true" ]] \
  || fail "Azure deployment is opt-in. Set DEPLOY_AZURE=true."

exec > >(tee "${EVIDENCE_DIR}/azure-deploy.log") 2>&1

state="$(az aks show \
  --resource-group "${AZURE_RESOURCE_GROUP}" \
  --name "${AKS_NAME}" \
  --query provisioningState -o tsv 2>/dev/null || true)"
[[ "${state}" == "Succeeded" ]] \
  || fail "Existing AKS ${AZURE_RESOURCE_GROUP}/${AKS_NAME} must be Succeeded"

location="$(az aks show \
  --resource-group "${AZURE_RESOURCE_GROUP}" \
  --name "${AKS_NAME}" \
  --query location -o tsv)"
if [[ -n "${AZURE_LOCATION}" && "${AZURE_LOCATION}" != "${location}" ]]; then
  fail "Configured AZURE_LOCATION does not match existing AKS location ${location}"
fi

az aks get-credentials \
  --resource-group "${AZURE_RESOURCE_GROUP}" \
  --name "${AKS_NAME}" \
  --overwrite-existing \
  --only-show-errors >/dev/null
kubectl --context "${KARS_KUBE_CONTEXT}" get deployment \
  -n kars-system kars-controller >/dev/null
pass "Existing AKS and KARS control plane are ready"

image_tag="applied-$(git -C "${REPO_ROOT}" rev-parse --short=12 HEAD)"
az acr build \
  --registry "${KARS_ACR_NAME}" \
  --image "fabrikam-release-pilot:${image_tag}" \
  --platform linux/amd64 \
  --file "${LAB_ROOT}/pilot_agent/Dockerfile" \
  "${LAB_ROOT}/pilot_agent" \
  --only-show-errors >/dev/null
image_digest="$(az acr repository show-tags \
  --name "${KARS_ACR_NAME}" \
  --repository fabrikam-release-pilot \
  --detail \
  --query "[?name=='${image_tag}'].digest | [0]" \
  -o tsv)"
[[ "${image_digest}" == sha256:* ]] || fail "Could not resolve ACR image digest"
FORGE_IMAGE="${KARS_ACR_NAME}.azurecr.io/fabrikam-release-pilot@${image_digest}"
export FORGE_IMAGE
printf '%s\n' "${FORGE_IMAGE}" >"${STATE_DIR}/current-image"
pass "Linux amd64 Pilot image is pinned by digest"

# KARS v0.1.25 carries agentCode through the runtime plan but does not yet
# materialize the OCI source mount. Point the first-class MAF runtime override
# at the digest-pinned image that extends the official KARS MAF adapter.
kubectl --context "${KARS_KUBE_CONTEXT}" -n kars-system set env \
  deployment/kars-controller "MAF_RUNTIME_IMAGE=${FORGE_IMAGE}" >/dev/null
kubectl --context "${KARS_KUBE_CONTEXT}" -n kars-system rollout status \
  deployment/kars-controller --timeout=5m >/dev/null
pass "KARS Controller MAF runtime is pinned to the Pilot image"

"${LAB_ROOT}/scripts/setup.sh"
"${LAB_ROOT}/scripts/render.sh"
"${LAB_ROOT}/scripts/validate.sh"

# Replace the runtime object atomically when upgrading an existing BYO
# Sandbox. JSON Merge Patch interprets byo:null as field deletion, so CRD
# admission never observes an invalid mixed BYO/MAF runtime.
if kubectl --context "${KARS_KUBE_CONTEXT}" -n kars-system get \
  "karssandbox/${KARS_SANDBOX_NAME}" >/dev/null 2>&1; then
  runtime_patch="$(jq -cn \
    --arg owner "${SUPPORT_OWNER}" \
    --arg concurrency "${TASK_CONCURRENCY_LIMIT}" \
    --arg daily "${DAILY_TASK_LIMIT}" \
    '{spec:{runtime:{
      kind:"MicrosoftAgentFramework",
      byo:null,
      microsoftAgentFramework:{
        language:"python",
        extraEnv:{
          SUPPORT_OWNER:$owner,
          TASK_CONCURRENCY_LIMIT:$concurrency,
          DAILY_TASK_LIMIT:$daily
        }
      }
    }}}')"
  kubectl --context "${KARS_KUBE_CONTEXT}" -n kars-system patch \
    "karssandbox/${KARS_SANDBOX_NAME}" --type=merge \
    -p "${runtime_patch}" >/dev/null
fi

kubectl --context "${KARS_KUBE_CONTEXT}" apply \
  -f "${RENDERED_DIR}/release-pilot.yaml" >/dev/null

phase=""
for _ in $(seq 1 120); do
  phase="$(kubectl --context "${KARS_KUBE_CONTEXT}" -n kars-system get \
    "karssandbox/${KARS_SANDBOX_NAME}" \
    -o jsonpath='{.status.phase}' 2>/dev/null || true)"
  [[ "${phase}" == "Running" ]] && break
  sleep 5
done
[[ "${phase}" == "Running" ]] || fail "${KARS_SANDBOX_NAME} did not reach Running"

namespace="kars-${KARS_SANDBOX_NAME}"
ready_image=""
for _ in $(seq 1 120); do
  ready_image="$(kubectl --context "${KARS_KUBE_CONTEXT}" -n "${namespace}" get \
    "deployment/${KARS_SANDBOX_NAME}" \
    -o jsonpath='{.spec.template.spec.containers[?(@.name=="agent")].image}' \
    2>/dev/null || true)"
  [[ "${ready_image}" == "${FORGE_IMAGE}" ]] && break
  sleep 5
done
[[ "${ready_image}" == "${FORGE_IMAGE}" ]] \
  || fail "MAF deployment template did not adopt the pinned ACR digest"
kubectl --context "${KARS_KUBE_CONTEXT}" -n "${namespace}" rollout status \
  "deployment/${KARS_SANDBOX_NAME}" --timeout=10m >/dev/null
stable_pods=0
for _ in $(seq 1 120); do
  stable_pods="$(kubectl --context "${KARS_KUBE_CONTEXT}" -n "${namespace}" get pod \
    -l "kars.azure.com/sandbox=${KARS_SANDBOX_NAME}" -o json |
    jq --arg image "${FORGE_IMAGE}" '
      [
        .items[]
        | select(.metadata.deletionTimestamp == null)
        | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))
        | select(any(.spec.containers[]; .name == "agent" and .image == $image))
      ]
      | length
    ')"
  total_pods="$(kubectl --context "${KARS_KUBE_CONTEXT}" -n "${namespace}" get pod \
    -l "kars.azure.com/sandbox=${KARS_SANDBOX_NAME}" -o json |
    jq '[.items[] | select(.metadata.deletionTimestamp == null)] | length')"
  [[ "${stable_pods}" == "1" && "${total_pods}" == "1" ]] && break
  sleep 2
done
[[ "${stable_pods}" == "1" && "${total_pods}" == "1" ]] \
  || fail "MAF rollout did not converge to one stable Ready Pod"

kubectl --context "${KARS_KUBE_CONTEXT}" -n "${namespace}" apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Service
metadata:
  name: fabrikam-dev-tools
spec:
  selector:
    kars.azure.com/sandbox: ${KARS_SANDBOX_NAME}
  ports:
    - name: mcp
      port: 8080
      targetPort: 8080
YAML
kubectl --context "${KARS_KUBE_CONTEXT}" apply \
  -f "${RENDERED_DIR}/mcp-and-eval.yaml" >/dev/null
pass "Release Pilot, MCP metadata, and evaluation declaration are deployed"

"${LAB_ROOT}/scripts/verify-azure.sh"
