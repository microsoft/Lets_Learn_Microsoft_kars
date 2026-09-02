#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
require_forge

if [[ "${ALLOW_BREAK_GLASS:-0}" != "1" ]]; then
  echo "SKIP: set ALLOW_BREAK_GLASS=1 to run audited in-container probes"
  exit 0
fi

namespace="$(forge_namespace)"
pod="$(forge_pod)"

cleanup() {
  kubectl label namespace "${namespace}" kars.azure.com/break-glass- >/dev/null 2>&1 || true
}
trap cleanup EXIT

kubectl label namespace "${namespace}" kars.azure.com/break-glass=true --overwrite >/dev/null

uid="$(kubectl -n "${namespace}" exec "${pod}" -c openclaw -- id -u)"
[[ "${uid}" == "1000" ]] || fail "OpenClaw process UID is ${uid}, expected 1000"
pass "Break-glass probe confirms OpenClaw process UID 1000"

root_write="$(kubectl -n "${namespace}" exec "${pod}" -c openclaw -- sh -lc \
  'if touch /etc/forge-boundary-test 2>/dev/null; then rm -f /etc/forge-boundary-test; echo allowed; else echo denied; fi')"
[[ "${root_write}" == "denied" ]] || fail "OpenClaw wrote to the read-only root filesystem"
pass "OpenClaw cannot write to /etc"

provider_env_names="$(kubectl -n "${namespace}" exec "${pod}" -c openclaw -- sh -lc \
  'env | cut -d= -f1 | grep -E "(^|_)(COPILOT|GITHUB).*(TOKEN|KEY)|^(GH_TOKEN|GITHUB_TOKEN)$" || true')"
[[ -z "${provider_env_names}" ]] || fail "OpenClaw exposes provider credential variables: ${provider_env_names}"
pass "OpenClaw process environment has no GitHub/Copilot provider credential"

direct_result="$(kubectl -n "${namespace}" exec "${pod}" -c openclaw -- sh -lc \
  'set +e; code=$(curl -sS --connect-timeout 3 --max-time 6 -o /dev/null -w "%{http_code}" https://example.com 2>/tmp/direct.err); rc=$?; printf "%s %s" "$rc" "$code"')"
direct_rc="${direct_result%% *}"
direct_http="${direct_result##* }"
if [[ "${direct_rc}" == "0" ]] || [[ "${direct_http}" != "000" ]]; then
  fail "OpenClaw direct egress unexpectedly succeeded: rc=${direct_rc} http=${direct_http}"
fi
pass "OpenClaw direct HTTPS egress is blocked"

router_http="$(kubectl -n "${namespace}" exec "${pod}" -c openclaw -- sh -lc \
  'curl -sS --max-time 45 -o /tmp/router-response -w "%{http_code}" \
    -H "content-type: application/json" \
    -H "x-kars-sandbox: forge" \
    --data '"'"'{"model":"gpt-5.6-sol","messages":[{"role":"user","content":"Reply with BOUNDARY_OK only."}],"max_completion_tokens":32}'"'"' \
    http://127.0.0.1:8443/v1/chat/completions')"
[[ "${router_http}" == "200" ]] || fail "Loopback router returned HTTP ${router_http}"
pass "OpenClaw reaches inference only through the loopback router"
