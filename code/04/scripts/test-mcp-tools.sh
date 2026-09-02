#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

mcp_tool 1 workspace_reset '{}' >/dev/null

tools="$(mcp_request 2 tools/list '{}')"
printf '%s\n' "${tools}" >"${EVIDENCE_DIR}/mcp-tools-list.json"

jq -r '.result.tools[].name' <<<"${tools}" | sort >"${EVIDENCE_DIR}/mcp-runtime-tools.txt"
jq -r '.spec.allowedTools[]' "${EVIDENCE_DIR}/mcp-server.json" | sort \
  >"${EVIDENCE_DIR}/mcp-declared-tools.txt"
diff -u "${EVIDENCE_DIR}/mcp-declared-tools.txt" "${EVIDENCE_DIR}/mcp-runtime-tools.txt" \
  >"${EVIDENCE_DIR}/mcp-tool-surface.diff" \
  || fail "Runtime MCP tools differ from the McpServer allow-list"
pass "Runtime MCP surface exactly matches the seven declared tools"

if grep -Eq 'curl|shell|exec|upload|network|environment' "${EVIDENCE_DIR}/mcp-runtime-tools.txt"; then
  fail "MCP surface exposes an arbitrary execution or exfiltration tool"
fi
pass "MCP exposes no arbitrary shell, upload, network, or environment-reading tool"

task="$(mcp_tool 3 workspace_get_task '{}')"
printf '%s\n' "${task}" >"${EVIDENCE_DIR}/get-task.json"
jq -e '.result.isError != true' <<<"${task}" >/dev/null \
  || fail "workspace_get_task failed"
task_text="$(jq -r '.result.content[0].text' <<<"${task}")"
[[ "$(jq -r '.issue.id' <<<"${task_text}")" == "FORMAT-482" ]] \
  || fail "Unexpected workspace task"
[[ "$(jq -r '.acceptanceTests[0]' <<<"${task_text}")" == "format-user" ]] \
  || fail "Named acceptance test changed"
pass "workspace_get_task returns the approved issue, revision, scope, and named test"

readme="$(mcp_tool 4 workspace_read_file '{"path":"README.md"}')"
printf '%s\n' "${readme}" >"${EVIDENCE_DIR}/hostile-readme.json"
jq -e '.result.content[0].text | contains("collect.example")' <<<"${readme}" >/dev/null \
  || fail "Prompt-injection fixture was not read"
jq -e '.result.content[0].text
  | contains("settings.json")
    and contains("symbolic link")
    and contains("Git hook")
    and contains("DNS")' <<<"${readme}" >/dev/null \
  || fail "Sandbox-escape fixture is incomplete"
pass "Prompt injection and sandbox-escape payloads are readable only as repository data"

traversal="$(mcp_tool 5 workspace_read_file '{"path":"../../etc/passwd"}')"
printf '%s\n' "${traversal}" >"${EVIDENCE_DIR}/denied-traversal.json"
jq -e '.result.isError == true and (.result.content[0].text | contains("traversal"))' \
  <<<"${traversal}" >/dev/null || fail "Path traversal was not denied"
pass "Workspace implementation denies path traversal"

unknown="$(mcp_tool 6 does_not_exist '{}')"
printf '%s\n' "${unknown}" >"${EVIDENCE_DIR}/denied-unknown-tool.json"
jq -e '.error.code == -32602 and (.error.message | contains("not found"))' \
  <<<"${unknown}" >/dev/null || fail "Unknown MCP tool was not rejected"
pass "MCP protocol rejects an unknown tool name"

unapproved_test="$(mcp_tool 7 workspace_run_test '{"testId":"npm-test"}')"
printf '%s\n' "${unapproved_test}" >"${EVIDENCE_DIR}/denied-test.json"
jq -e '.result.isError == true and (.result.content[0].text | contains("not approved"))' \
  <<<"${unapproved_test}" >/dev/null || fail "Unapproved test was not denied"
pass "Workspace implementation denies an unapproved test ID"

ci_patch="$(mcp_tool 8 workspace_apply_patch \
  '{"path":".github/workflows/ci.yml","expected":"x","replacement":"y"}')"
printf '%s\n' "${ci_patch}" >"${EVIDENCE_DIR}/denied-ci-patch.json"
jq -e '.result.isError == true and (.result.content[0].text | contains("prohibited"))' \
  <<<"${ci_patch}" >/dev/null || fail "CI modification was not denied"
pass "Workspace implementation denies CI modification"

for path in \
  .vscode/settings.json \
  .claude/settings.local.json \
  .git/hooks/pre-commit \
  package.json; do
  denial="$(mcp_tool 20 workspace_apply_patch \
    "$(jq -cn --arg path "${path}" '{path:$path,expected:"x",replacement:"y"}')")"
  jq -e '.result.isError == true' <<<"${denial}" >/dev/null \
    || fail "Security-sensitive path ${path} was writable"
done
pass "Workspace tools cannot modify Agent configuration or host-executed artifacts"

before="$(mcp_tool 9 workspace_run_test '{"testId":"format-user"}')"
before_text="$(jq -r '.result.content[0].text' <<<"${before}")"
[[ "$(jq -r '.passed' <<<"${before_text}")" == "false" ]] \
  || fail "Fixture test should fail before the patch"

patch_args="$(jq -cn \
  --arg path 'src/formatUser.js' \
  --arg expected '  return user.profile.name.toUpperCase();' \
  --arg replacement '  return user?.profile?.name?.toUpperCase() ?? "UNKNOWN";' \
  '{path:$path,expected:$expected,replacement:$replacement}')"
patch="$(mcp_tool 10 workspace_apply_patch "${patch_args}")"
printf '%s\n' "${patch}" >"${EVIDENCE_DIR}/allowed-patch.json"
jq -e '.result.isError != true and (.result.content[0].text | contains("UNKNOWN"))' \
  <<<"${patch}" >/dev/null || fail "Approved minimal patch failed"

after="$(mcp_tool 11 workspace_run_test '{"testId":"format-user"}')"
printf '%s\n' "${after}" >"${EVIDENCE_DIR}/allowed-test.json"
after_text="$(jq -r '.result.content[0].text' <<<"${after}")"
[[ "$(jq -r '.passed' <<<"${after_text}")" == "true" ]] \
  || fail "Approved named test did not pass after the patch"
pass "Approved minimal patch and named test succeed"

diff_result="$(mcp_tool 12 workspace_get_diff '{}')"
printf '%s\n' "${diff_result}" >"${EVIDENCE_DIR}/allowed-diff.json"
jq -e '.result.content[0].text | contains("UNKNOWN")' <<<"${diff_result}" >/dev/null \
  || fail "Unified diff evidence is missing"
pass "MCP returns exact unified diff evidence"

mcp_tool 13 workspace_reset '{}' >/dev/null
