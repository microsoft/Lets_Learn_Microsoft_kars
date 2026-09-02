#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
require_forge

namespace="$(forge_namespace)"
pod="$(forge_pod)"
pod_json="$(kubectl -n "${namespace}" get pod "${pod}" -o json)"
workspace_json="$(kubectl -n kars-mcp get deployment forge-workspace-mcp -o json)"

[[ "$(kubectl -n kars-system get karssandbox forge -o jsonpath='{.status.phase}')" == "Running" ]] \
  || fail "Forge sandbox is not Running"
pass "KarsSandbox/forge is Running"

jq -e '.spec.initContainers[] | select(.name == "egress-guard")' \
  <<<"${pod_json}" >/dev/null || fail "egress-guard init container is missing"
pass "egress-guard init container exists"

[[ "$(jq -r '.spec.containers[] | select(.name == "openclaw") | .securityContext.runAsUser' <<<"${pod_json}")" == "1000" ]] \
  || fail "OpenClaw does not run as UID 1000"
[[ "$(jq -r '.spec.containers[] | select(.name == "inference-router") | .securityContext.runAsUser' <<<"${pod_json}")" == "1001" ]] \
  || fail "Inference router does not run as UID 1001"
pass "OpenClaw UID 1000 and router UID 1001 are separated"

jq -e '.spec.containers[] | select(.name == "openclaw")
  | .securityContext.readOnlyRootFilesystem == true
    and .securityContext.allowPrivilegeEscalation == false
    and (.securityContext.capabilities.drop | index("ALL") != null)' \
  <<<"${pod_json}" >/dev/null || fail "OpenClaw security context is not hardened"
pass "OpenClaw has a read-only root filesystem, no privilege escalation, and no capabilities"

[[ "$(kubectl -n kars-system get karssandbox forge \
  -o jsonpath='{.spec.sandbox.writablePaths[*]}')" == "/sandbox /tmp" ]] \
  || fail "Forge writable paths expanded beyond /sandbox and /tmp"
pass "Forge writable paths are limited to disposable sandbox and temporary storage"

if jq -e '.spec.volumes[]? | select(has("hostPath"))' <<<"${pod_json}" >/dev/null; then
  fail "Forge Pod contains a hostPath volume"
fi
pass "Forge Pod does not mount the developer host filesystem"

if jq -e '
  [.spec.volumes[]? |
    select(.hostPath.path == "/var/run/docker.sock" or .name == "docker-socket")] |
  length > 0
' <<<"${pod_json}" >/dev/null; then
  fail "Forge Pod exposes a Docker daemon control socket"
fi
pass "Forge cannot escape through a mounted container-daemon socket"

[[ "$(jq -r '.spec.automountServiceAccountToken // false' <<<"${pod_json}")" == "false" ]] \
  || fail "Forge Pod automatically mounts a Kubernetes service-account token"
pass "Forge has no ambient Kubernetes API credential"

if jq -e '.spec.containers[] | select(.name == "openclaw") | .env[]?.name
  | select(test("(^|_)(COPILOT|GITHUB).*(TOKEN|KEY)|^(GH_TOKEN|GITHUB_TOKEN)$"))' \
  <<<"${pod_json}" >/dev/null; then
  fail "OpenClaw contains a GitHub/Copilot provider credential reference"
fi
pass "OpenClaw has no GitHub/Copilot provider credential reference"

jq -e '.spec.containers[] | select(.name == "inference-router") | .env[]?.name
  | select(. == "COPILOT_GITHUB_TOKEN")' \
  <<<"${pod_json}" >/dev/null || fail "Router provider credential reference is missing"
pass "Provider credential is isolated to the inference router"

jq -e '.spec.template.spec.automountServiceAccountToken == false
  and (.spec.template.spec.volumes[] | select(.name == "workspace") | has("emptyDir"))
  and (.spec.template.spec.containers[0].securityContext.readOnlyRootFilesystem == true)
  and (.spec.template.spec.containers[0].securityContext.allowPrivilegeEscalation == false)' \
  <<<"${workspace_json}" >/dev/null || fail "Workspace MCP is not disposable and hardened"
pass "Workspace MCP uses emptyDir, disables service-account token mounting, and is hardened"

[[ "$(kubectl -n kars-system get karssandbox forge -o jsonpath='{.spec.networkPolicy.defaultDeny}')" == "true" ]] \
  || fail "Sandbox default-deny networking is disabled"
kubectl -n "${namespace}" get networkpolicy sandbox-policy >/dev/null \
  || fail "Generated sandbox NetworkPolicy is missing"
pass "Sandbox default-deny intent and generated NetworkPolicy exist"

set +e
exec_error="$(kubectl -n "${namespace}" exec "${pod}" -c openclaw -- id 2>&1)"
exec_rc=$?
set -e
if [[ ${exec_rc} -eq 0 ]] || [[ "${exec_error}" != *"kars-sandbox-exec-ban"* ]]; then
  fail "OpenClaw kubectl exec was not denied by the KARS admission policy"
fi
pass "KARS admission policy denies normal kubectl exec into OpenClaw"
