from __future__ import annotations

import argparse
import asyncio
import json
import os
import secrets
from pathlib import Path
from typing import Annotated

from agent_framework import tool
from agent_framework.github import GitHubCopilotAgent, GitHubCopilotOptions
from copilot.generated.rpc import (
    PermissionDecisionApproveOnce,
    PermissionDecisionUserNotAvailable,
)
from copilot.session import PermissionRequestResult
from copilot.session_events import PermissionRequest, PermissionRequestCustomTool

from host_agent.workflow import ALLOWED_ISSUE, contract_for

MODEL = os.environ.get("GITHUB_COPILOT_MODEL", "gpt-5.6-sol")
EXPECTED_MARKER = "COPILOT_GPT_5_6_SOL_OK"
tool_calls = 0
run_nonce = secrets.token_hex(8)


@tool(approval_mode="never_require")
def inspect_forge_contract(
    issue_id: Annotated[str, "The exact approved issue identifier."],
) -> dict[str, object]:
    """Return the bounded Forge workflow contract for an approved issue."""
    global tool_calls
    tool_calls += 1
    return {
        **contract_for(issue_id).to_dict(),
        "runNonce": run_nonce,
    }


def bounded_permission_handler(
    request: PermissionRequest,
    _context: dict[str, str],
) -> PermissionRequestResult:
    if (
        isinstance(request, PermissionRequestCustomTool)
        and request.tool_name == "inspect_forge_contract"
    ):
        return PermissionDecisionApproveOnce()
    return PermissionDecisionUserNotAvailable()


async def run(output: Path) -> None:
    if MODEL != "gpt-5.6-sol":
        raise RuntimeError(f"this lab requires gpt-5.6-sol, found {MODEL!r}")

    options = GitHubCopilotOptions(
        model=MODEL,
        timeout=120,
        on_permission_request=bounded_permission_handler,
        available_tools=["inspect_forge_contract"],
        enable_config_discovery=False,
        skip_custom_instructions=True,
        enable_skills=False,
        working_directory=str(Path.cwd()),
    )
    agent: GitHubCopilotAgent[GitHubCopilotOptions] = GitHubCopilotAgent(
        instructions=(
            "You are the host-side Forge canary. You have one bounded custom tool. "
            "Call inspect_forge_contract exactly once with FORMAT-482. Do not request "
            "shell, file, URL, MCP, or write permissions. After reading the contract, "
            "reply on one line with COPILOT_GPT_5_6_SOL_OK, FORMAT-482, the runNonce "
            "returned by the tool, and STOP_FOR_HUMAN_REVIEW in that order."
        ),
        tools=[inspect_forge_contract],
        default_options=options,
    )

    async with agent:
        result = await agent.run(
            "Inspect the approved Forge contract and stop at human review."
        )

    response = str(result).strip()
    evidence = {
        "model": MODEL,
        "issueId": ALLOWED_ISSUE,
        "toolCalls": tool_calls,
        "runNonce": run_nonce,
        "response": response,
        "credentialBoundary": "host Copilot CLI session; not injected into KARS BYO",
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")

    if tool_calls != 1:
        raise RuntimeError(f"expected one bounded tool call, observed {tool_calls}")
    expected_parts = (
        EXPECTED_MARKER,
        ALLOWED_ISSUE,
        run_nonce,
        "STOP_FOR_HUMAN_REVIEW",
    )
    if not all(part in response for part in expected_parts):
        raise RuntimeError(f"unexpected Copilot response: {response}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    asyncio.run(run(args.output))


if __name__ == "__main__":
    main()
