#!/usr/bin/env bash
set -euo pipefail

requested_deploy_aks="${DEPLOY_AKS:-}"
requested_kars_source_root="${KARS_SOURCE_ROOT:-}"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
[[ -z "${requested_deploy_aks}" ]] || DEPLOY_AKS="${requested_deploy_aks}"
[[ -z "${requested_kars_source_root}" ]] \
  || KARS_SOURCE_ROOT="${requested_kars_source_root}"

[[ "${DEPLOY_AKS}" == "true" ]] \
  || fail "Azure deployment is opt-in. Set DEPLOY_AKS=true after reviewing the plan."
[[ -d "${KARS_SOURCE_ROOT}/deploy/helm/kars" ]] \
  || fail "KARS_SOURCE_ROOT must contain deploy/helm/kars"
[[ -f "${KARS_SOURCE_ROOT}/deploy/agentmesh-agt.yaml" ]] \
  || fail "KARS_SOURCE_ROOT must contain deploy/agentmesh-agt.yaml"

exec > >(tee "${EVIDENCE_DIR}/azure-deploy.log") 2>&1

location="$(resolve_location)"
release_tag="${KARS_RELEASE#v}"
image_tag="$(git -C "${REPO_ROOT}" rev-parse --short=12 HEAD)"
api_cidr="$(curl -fsS https://api.ipify.org)/32"
aks_context="${AKS_NAME}"
app_pf_pid=""
router_pf_pid=""

stop_forwards() {
  for pid in "${app_pf_pid}" "${router_pf_pid}"; do
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
      kill "${pid}"
      wait "${pid}" 2>/dev/null || true
    fi
  done
}
trap stop_forwards EXIT

wait_for_aks() {
  local state
  for _ in $(seq 1 180); do
    state="$(az aks show \
      --resource-group "${AZURE_RESOURCE_GROUP}" \
      --name "${AKS_NAME}" \
      --query provisioningState -o tsv)"
    case "${state}" in
      Succeeded)
        return
        ;;
      Failed|Canceled)
        fail "AKS entered terminal provisioning state ${state}"
        ;;
    esac
    sleep 10
  done
  fail "AKS did not reach Succeeded within 30 minutes"
}

printf 'Deploying KARS to Azure\n'
printf 'Resource group: %s\n' "${AZURE_RESOURCE_GROUP}"
printf 'Location: %s\n' "${location}"
printf 'AKS: %s\n' "${AKS_NAME}"
printf 'ACR: %s\n\n' "${KARS_ACR_NAME}"

az account set --subscription "$(az account show --query id -o tsv)"

if ! az monitor log-analytics workspace show \
  --resource-group "${AZURE_RESOURCE_GROUP}" \
  --workspace-name "${LOG_ANALYTICS_WORKSPACE}" >/dev/null 2>&1; then
  az monitor log-analytics workspace create \
    --resource-group "${AZURE_RESOURCE_GROUP}" \
    --workspace-name "${LOG_ANALYTICS_WORKSPACE}" \
    --location "${location}" \
    --only-show-errors >/dev/null
fi
workspace_id="$(az monitor log-analytics workspace show \
  --resource-group "${AZURE_RESOURCE_GROUP}" \
  --workspace-name "${LOG_ANALYTICS_WORKSPACE}" \
  --query id -o tsv)"
pass "Log Analytics workspace is ready"

if ! az acr show --name "${KARS_ACR_NAME}" >/dev/null 2>&1; then
  az acr create \
    --resource-group "${AZURE_RESOURCE_GROUP}" \
    --name "${KARS_ACR_NAME}" \
    --location "${location}" \
    --sku Basic \
    --admin-enabled false \
    --only-show-errors >/dev/null
fi
acr_login_server="$(az acr show --name "${KARS_ACR_NAME}" \
  --query loginServer -o tsv)"
pass "Dedicated ACR is ready"

if ! az aks show \
  --resource-group "${AZURE_RESOURCE_GROUP}" \
  --name "${AKS_NAME}" >/dev/null 2>&1; then
  az aks create \
    --resource-group "${AZURE_RESOURCE_GROUP}" \
    --name "${AKS_NAME}" \
    --location "${location}" \
    --tier free \
    --enable-managed-identity \
    --nodepool-name system \
    --node-count 1 \
    --node-vm-size Standard_D2as_v5 \
    --os-sku AzureLinux \
    --network-plugin azure \
    --network-plugin-mode overlay \
    --network-dataplane cilium \
    --enable-oidc-issuer \
    --enable-workload-identity \
    --enable-addons monitoring,azure-policy,azure-keyvault-secrets-provider \
    --workspace-resource-id "${workspace_id}" \
    --enable-azure-monitor-metrics \
    --api-server-authorized-ip-ranges "${api_cidr}" \
    --attach-acr "${KARS_ACR_NAME}" \
    --generate-ssh-keys \
    --only-show-errors >/dev/null
fi
wait_for_aks
pass "AKS cluster ${AKS_NAME} is ready"

if ! az aks nodepool show \
  --resource-group "${AZURE_RESOURCE_GROUP}" \
  --cluster-name "${AKS_NAME}" \
  --name clawpool >/dev/null 2>&1; then
  az aks nodepool add \
    --resource-group "${AZURE_RESOURCE_GROUP}" \
    --cluster-name "${AKS_NAME}" \
    --name clawpool \
    --mode User \
    --node-count 1 \
    --node-vm-size Standard_D4as_v5 \
    --os-sku AzureLinux \
    --enable-encryption-at-host \
    --labels kars.azure.com/pool=sandbox \
    --node-taints kars.azure.com/sandbox=true:NoSchedule \
    --only-show-errors >/dev/null
fi
wait_for_aks
pass "Dedicated sandbox node pool is ready"

az aks update \
  --resource-group "${AZURE_RESOURCE_GROUP}" \
  --name "${AKS_NAME}" \
  --attach-acr "${KARS_ACR_NAME}" \
  --only-show-errors >/dev/null
wait_for_aks
az aks get-credentials \
  --resource-group "${AZURE_RESOURCE_GROUP}" \
  --name "${AKS_NAME}" \
  --overwrite-existing \
  --only-show-errors >/dev/null
export KARS_KUBE_CONTEXT="${aks_context}"
kubectl --context "${aks_context}" get nodes >/dev/null
pass "AKS credentials and ACR pull access are ready"

for mapping in \
  "kars-controller:kars-controller" \
  "kars-inference-router:kars-inference-router" \
  "openclaw-sandbox:openclaw-sandbox" \
  "kars-agentmesh-relay:agentmesh-relay-agt" \
  "kars-agentmesh-registry:agentmesh-registry-agt"; do
  source_repo="${mapping%%:*}"
  target_repo="${mapping##*:}"
  az acr import \
    --name "${KARS_ACR_NAME}" \
    --source "ghcr.io/azure/${source_repo}:v${release_tag}" \
    --image "${target_repo}:latest" \
    --force \
    --only-show-errors >/dev/null
done
pass "Pinned KARS ${KARS_RELEASE} release images were imported"

az acr build \
  --registry "${KARS_ACR_NAME}" \
  --image "forge-byo-copilot-claw:${image_tag}" \
  --platform linux/amd64 \
  --file "${CODE05_ROOT}/byo_agent/Dockerfile" \
  "${CODE05_ROOT}/byo_agent" \
  --only-show-errors >/dev/null
image_digest="$(az acr repository show-tags \
  --name "${KARS_ACR_NAME}" \
  --repository forge-byo-copilot-claw \
  --detail \
  --query "[?name=='${image_tag}'].digest | [0]" \
  -o tsv)"
[[ "${image_digest}" == sha256:* ]] \
  || fail "Could not resolve the BYO image digest from ACR"
FORGE_IMAGE="${acr_login_server}/forge-byo-copilot-claw@${image_digest}"
export FORGE_IMAGE
pass "Linux amd64 BYO image was built and pinned by digest"

kubectl --context "${aks_context}" create namespace kars-system \
  --dry-run=client -o yaml |
  kubectl --context "${aks_context}" apply -f - >/dev/null
kubectl --context "${aks_context}" label namespace kars-system \
  app.kubernetes.io/managed-by=Helm --overwrite >/dev/null
kubectl --context "${aks_context}" annotate namespace kars-system \
  meta.helm.sh/release-name=kars \
  meta.helm.sh/release-namespace=kars-system \
  --overwrite >/dev/null
copilot_token="$(kubectl --context kind-kars-dev -n kars-system get \
  secret kars-dev-creds -o jsonpath='{.data.api-key}' | base64 --decode)"
printf '%s' "${copilot_token}" |
  kubectl --context "${aks_context}" -n kars-system create secret generic \
    kars-copilot-creds \
    --from-file=api-key=/dev/stdin \
    --dry-run=client -o yaml |
  kubectl --context "${aks_context}" apply -f - >/dev/null
unset copilot_token
pass "GitHub Copilot credential was transferred without printing it"

helm upgrade --install kars "${KARS_SOURCE_ROOT}/deploy/helm/kars" \
  --kube-context "${aks_context}" \
  --namespace kars-system \
  --create-namespace \
  -f "${LAB_ROOT}/config/azure-github-copilot-values.yaml" \
  --set "controller.image.repository=${acr_login_server}/kars-controller" \
  --set "controller.image.tag=latest" \
  --set "inferenceRouter.image.repository=${acr_login_server}/kars-inference-router" \
  --set "inferenceRouter.image.tag=latest" \
  --set "sandbox.image.repository=${acr_login_server}/openclaw-sandbox" \
  --set "sandbox.image.tag=latest" \
  --set "karsRelease=${KARS_RELEASE}"
kubectl --context "${aks_context}" -n kars-system patch deployment \
  kars-controller --type=merge \
  -p '{"spec":{"template":{"spec":{"nodeSelector":{"kars.azure.com/pool":"sandbox"},"tolerations":[{"key":"kars.azure.com/sandbox","operator":"Equal","value":"true","effect":"NoSchedule"}]}}}}' \
  >/dev/null
kubectl --context "${aks_context}" -n kars-system rollout status \
  deployment/kars-controller --timeout=15m >/dev/null
pass "KARS Helm control plane is ready"

sed \
  -e "s|karsacr.azurecr.io/agentmesh-registry-agt:latest|${acr_login_server}/agentmesh-registry-agt:latest|g" \
  -e "s|karsacr.azurecr.io/agentmesh-relay-agt:latest|${acr_login_server}/agentmesh-relay-agt:latest|g" \
  "${KARS_SOURCE_ROOT}/deploy/agentmesh-agt.yaml" |
  "${LAB_ROOT}/scripts/azure-node-placement.py" \
  >"${EVIDENCE_DIR}/agentmesh-agt.yaml"
kubectl --context "${aks_context}" apply \
  -f "${EVIDENCE_DIR}/agentmesh-agt.yaml" >/dev/null
kubectl --context "${aks_context}" -n agentmesh rollout status \
  deployment/registry --timeout=300s >/dev/null
kubectl --context "${aks_context}" -n agentmesh rollout status \
  deployment/relay --timeout=300s >/dev/null
pass "AGT registry and relay are ready"

if ! kubectl --context "${aks_context}" -n kars-system get \
  karssandbox/forge-intake >/dev/null 2>&1; then
  kars add forge-intake \
    --runtime openclaw \
    --model "${GITHUB_COPILOT_MODEL}" \
    --isolation enhanced \
    --token-budget-per-request 1024 \
    --token-budget-daily 4096 \
    --governance
fi

"${LAB_ROOT}/scripts/render-gitops.sh"
kubectl --context "${aks_context}" apply \
  -f "${RENDERED_DIR}/multi-agent.yaml" >/dev/null
kubectl --context "${aks_context}" apply \
  -f "${CODE06_ROOT}/manifests/byo-agent-exec-ban.yaml" >/dev/null

for sandbox in forge-intake forge-builder forge-reviewer; do
  for _ in $(seq 1 120); do
    phase="$(kubectl --context "${aks_context}" -n kars-system get \
      "karssandbox/${sandbox}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    [[ "${phase}" == "Running" ]] && break
    sleep 5
  done
  [[ "${phase}" == "Running" ]] || fail "${sandbox} did not reach Running"
done
pass "OpenClaw Intake, Builder, and Reviewer Sandboxes are Running"

kubectl --context "${aks_context}" -n kars-forge-builder port-forward \
  deployment/forge-builder 18087:8080 \
  >"${EVIDENCE_DIR}/azure-app-port-forward.log" 2>&1 &
app_pf_pid=$!
kubectl --context "${aks_context}" -n kars-forge-builder port-forward \
  deployment/forge-builder 18445:8443 \
  >"${EVIDENCE_DIR}/azure-router-port-forward.log" 2>&1 &
router_pf_pid=$!
for _ in $(seq 1 60); do
  curl -fsS http://127.0.0.1:18087/healthz >/dev/null 2>&1 && break
  sleep 2
done

curl -fsS \
  -H 'content-type: application/json' \
  --data '{"issue_id":"FORMAT-482"}' \
  http://127.0.0.1:18087/run |
  jq . >"${EVIDENCE_DIR}/azure-gpt-response.json"
jq -e '
  .model == "gpt-5.6-sol"
  and (.reply | contains("KARS_BYO_GPT_5_6_SOL_OK"))
' "${EVIDENCE_DIR}/azure-gpt-response.json" >/dev/null \
  || fail "Azure KARS GPT-5.6-Sol inference failed"

curl -fsS http://127.0.0.1:18445/agt/audit/verify |
  jq . >"${EVIDENCE_DIR}/azure-audit-verify.json"
jq -e '.integrity == "valid" and .entries > 0' \
  "${EVIDENCE_DIR}/azure-audit-verify.json" >/dev/null \
  || fail "Azure Router audit verification failed"

kubectl --context "${aks_context}" -n kars-forge-builder get deployment \
  forge-builder -o json |
  jq '{
    containers:[.spec.template.spec.containers[] | {
      name,
      envNames:[(.env // [])[] | .name]
    }]
  }' >"${EVIDENCE_DIR}/azure-deployment-sanitized.json"
jq -e '
  [.containers[] | select(.name=="agent") | .envNames[]] |
  all(test("TOKEN|KEY|SECRET|COPILOT|GITHUB"; "i") | not)
' "${EVIDENCE_DIR}/azure-deployment-sanitized.json" >/dev/null \
  || fail "Provider credential name leaked into the Azure Agent container"

pod="$(kubectl --context "${aks_context}" -n kars-forge-builder get pod \
  -o jsonpath='{.items[0].metadata.name}')"
if kubectl --context "${aks_context}" -n kars-forge-builder exec \
  "${pod}" -c agent -- true \
  >"${EVIDENCE_DIR}/azure-exec-denial.txt" 2>&1; then
  fail "Azure BYO Agent unexpectedly allowed kubectl exec"
fi
grep -Eqi 'denied|forbidden|break-glass' \
  "${EVIDENCE_DIR}/azure-exec-denial.txt" \
  || fail "Azure exec denial failed for an unexpected reason"
pass "Azure GPT-5.6-Sol, audit, credential boundary, and exec denial passed"

az aks show \
  --resource-group "${AZURE_RESOURCE_GROUP}" \
  --name "${AKS_NAME}" \
  --query '{
    name:name,
    location:location,
    provisioningState:provisioningState,
    kubernetesVersion:kubernetesVersion,
    networkPlugin:networkProfile.networkPlugin,
    networkPluginMode:networkProfile.networkPluginMode,
    networkDataplane:networkProfile.networkDataplane,
    workloadIdentity:securityProfile.workloadIdentity.enabled,
    oidcIssuer:oidcIssuerProfile.enabled
  }' -o json >"${EVIDENCE_DIR}/azure-aks.json"
jq -n \
  --arg image "${FORGE_IMAGE}" \
  --arg model "${GITHUB_COPILOT_MODEL}" \
  --arg policyDigest "$(kubectl --context "${aks_context}" -n kars-system get \
    inferencepolicy/forge-builder-inference -o jsonpath='{.status.loadedDigest}')" \
  '{image:$image,model:$model,policyDigest:$policyDigest,deployed:true}' \
  >"${EVIDENCE_DIR}/azure-release-record.json"

stop_forwards
trap - EXIT
pass "Real Azure deployment completed"
