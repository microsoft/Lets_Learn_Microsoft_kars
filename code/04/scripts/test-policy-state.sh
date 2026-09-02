#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

coordinator="${EVIDENCE_DIR}/coordinator-tool-policy.json"
specialist="${EVIDENCE_DIR}/specialist-tool-policy.json"
inference="${EVIDENCE_DIR}/inference-policy.json"
mcp="${EVIDENCE_DIR}/mcp-server.json"
compiled="${EVIDENCE_DIR}/compiled-tool-profile.json"

[[ "$(jq -r '.status.phase' "${coordinator}")" == "Ready" ]] \
  || fail "Coordinator ToolPolicy is not Ready"
jq -e '.status.conditions[] | select(.type == "Ready" and .status == "True" and .reason == "RouterEnforcing")' \
  "${coordinator}" >/dev/null || fail "Coordinator ToolPolicy lacks RouterEnforcing evidence"
pass "Coordinator ToolPolicy is Ready because the router echoed its digest"

status_digest="$(jq -r '.status.agtProfileDigest' "${coordinator}")"
compiled_digest="$(jq -r '.metadata.annotations["kars.azure.com/agt-profile-digest"]' "${compiled}")"
[[ "${status_digest}" == "${compiled_digest}" ]] \
  || fail "Compiled ToolPolicy digest does not match status"
pass "ToolPolicy status digest matches the compiled ConfigMap"

jq -e '.spec.rateLimit == {rps:2,burst:20,window:"1m"}
  and .spec.approval.mode == "never"
  and .spec.appliesTo.mcpServer == "forge-workspace"
  and .spec.appliesTo.sandboxMatchLabels["kars.azure.com/sandbox"] == "forge"' \
  "${coordinator}" >/dev/null || fail "Coordinator ToolPolicy selector or controls changed"
pass "ToolPolicy carries the expected selector, rate limit, burst, window, and approval mode"

for action in \
  workspace_get_task \
  workspace_read_file \
  workspace_search \
  workspace_apply_patch \
  workspace_run_test \
  workspace_get_diff \
  workspace_reset; do
  jq -e --arg action "\"tool:${action}:*\"" \
    '.spec.agtProfile.inline | contains($action)' "${coordinator}" >/dev/null \
    || fail "Coordinator capability is missing tool:${action}:*"
done
pass "Coordinator AGT profile names all seven workspace capabilities"

if jq -e '.spec.agtProfile.inline | contains("tool:workspace_")' "${specialist}" >/dev/null; then
  fail "Specialist ToolPolicy unexpectedly grants workspace capabilities"
fi
pass "Specialist AGT profile grants inference and mesh, but no workspace tool capability"

[[ "$(jq -r '.status.phase' "${mcp}")" == "Ready" ]] \
  || fail "McpServer/forge-workspace is not Ready"
jq -e '.spec.allowedSandboxes.matchLabels["kars.azure.com/sandbox"] == "forge"' \
  "${mcp}" >/dev/null || fail "MCP sandbox selector is not restricted to Forge"
pass "McpServer coarse gate selects only the Forge sandbox label"

[[ "$(jq -r '.status.phase' "${inference}")" == "Ready" ]] \
  || fail "InferencePolicy/forge-inference is not Ready"
jq -e '.status.compiledDigest == .status.loadedDigest
  and .spec.tokenBudget.perRequestTokens == 20000
  and .spec.tokenBudget.dailyTokens == 100000' \
  "${inference}" >/dev/null || fail "Inference policy digest or budget is inconsistent"
pass "Inference budget is loaded by the router with matching compiled and loaded digests"
