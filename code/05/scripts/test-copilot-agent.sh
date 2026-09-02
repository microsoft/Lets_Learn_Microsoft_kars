#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

[[ -n "${GITHUB_COPILOT_CLI_PATH}" && -x "${GITHUB_COPILOT_CLI_PATH}" ]] \
  || fail "GitHub Copilot CLI is not installed"

"${LAB_ROOT}/scripts/setup-python.sh"
PYTHONPATH="${LAB_ROOT}" \
  "${VENV_DIR}/bin/python" -m host_agent.copilot_claw \
  --output "${EVIDENCE_DIR}/host-copilot-agent.json"

jq -e '
  .model == "gpt-5.6-sol"
  and .issueId == "FORMAT-482"
  and .toolCalls == 1
  and (.response | contains("COPILOT_GPT_5_6_SOL_OK"))
  and (.runNonce as $nonce | .response | contains($nonce))
  and (.response | contains("STOP_FOR_HUMAN_REVIEW"))
' "${EVIDENCE_DIR}/host-copilot-agent.json" >/dev/null \
  || fail "GitHubCopilotAgent evidence is inconsistent"
pass "Host-side Microsoft Agent Framework used GitHub Copilot GPT-5.6-Sol"
