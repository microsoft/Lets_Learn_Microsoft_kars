from __future__ import annotations

import asyncio
import json
import os
import threading
import uuid
from typing import Annotated, Any, Literal

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

# Bootstrap in this process before importing MAF so the OpenAI client is
# pinned to the local KARS Router and receives only the router sentinel key.
from kars_runtime_maf_python import bootstrap

bootstrap()

from agent_framework import Agent, tool
from agent_framework.openai import OpenAIChatClient

from controls import (
    AuditChain,
    ControlViolation,
    Handoff,
    TaskLedger,
    digest_text,
    validate_artifact_path,
)
from workflow import APPROVED_TOOLS, FORBIDDEN_ACTIONS, WORKFLOW

MODEL = os.environ.get("KARS_MODEL", "")
CONTRACT_VERSION = os.environ.get("KARS_RUNTIME_CONTRACT_VERSION", "")
RUNTIME_KIND = os.environ.get("KARS_RUNTIME_KIND", "")
SUPPORT_OWNER = os.environ.get("SUPPORT_OWNER", "unassigned")
CONCURRENCY_LIMIT = int(os.environ.get("TASK_CONCURRENCY_LIMIT", "2"))
DAILY_TASK_LIMIT = int(os.environ.get("DAILY_TASK_LIMIT", "20"))
EXPECTED_MODEL = "gpt-5.6-sol"
EXPECTED_CONTRACT = "v1"
EXPECTED_KIND = "MicrosoftAgentFramework"
ISSUE_ID = "FAB-482"
REVISION = "sha256:98ea5005d70f6471b35a1ab99c37d8fe34141b859b6d55e290ce1b9cbf877b43"

app = FastAPI(title="fabrikam-release-pilot")
audit = AuditChain()
ledger = TaskLedger(CONCURRENCY_LIMIT, DAILY_TASK_LIMIT)
_evidence_lock = threading.Lock()
_tool_evidence: dict[str, dict[str, str]] = {}


class KarsOpenAIChatClient(OpenAIChatClient):
    def _parse_response_from_openai(
        self, response: Any, options: dict[str, Any]
    ) -> Any:
        parsed = super()._parse_response_from_openai(response, options)
        if options.get("store") is False:
            for message in parsed.messages:
                for content in message.contents:
                    if content.type == "function_call":
                        content.additional_properties.pop("fc_id", None)
        return parsed


@tool(approval_mode="never_require")
def inspect_release_contract(
    request_id: Annotated[str, "Opaque request identifier supplied verbatim by the caller."],
    issue_id: Annotated[str, "The approved issue identifier."],
    revision: Annotated[str, "The pinned source revision digest."],
) -> str:
    """Inspect the one approved issue and return bounded patch/test evidence."""
    if issue_id != ISSUE_ID or revision != REVISION:
        raise ValueError("release contract is outside the approved scope")

    patch = (
        '- note = payload["customer_note"].strip()\n'
        '+ note = (payload.get("customer_note") or "").strip()\n'
    )
    tests = "2 passed: missing note returns 200; supplied note remains unchanged"
    with _evidence_lock:
        _tool_evidence[request_id] = {"patch": patch, "tests": tests}
    return json.dumps(
        {
            "issueId": ISSUE_ID,
            "revision": REVISION,
            "patch": patch,
            "tests": tests,
            "requiresHumanApproval": True,
        },
        sort_keys=True,
    )


def consume_tool_evidence(request_id: str) -> dict[str, str] | None:
    with _evidence_lock:
        return _tool_evidence.pop(request_id, None)


maf_client = KarsOpenAIChatClient(model=MODEL)
maf_client.function_invocation_configuration["max_iterations"] = 3
maf_client.function_invocation_configuration["max_function_calls"] = 1
builder = Agent(
    client=maf_client,
    name="FabrikamReleaseBuilder",
    instructions=(
        "You are the Microsoft Agent Framework Builder inside a KARS-governed "
        "release pilot. You have exactly one bounded tool. For every request, "
        "call inspect_release_contract exactly once using the request_id, issue_id, "
        "and revision supplied by the user. Never invent another tool, modify source, "
        "approve a patch, merge, deploy, or access a URL. After the tool returns, "
        "emit only the exact completion line requested by the user."
    ),
    tools=[inspect_release_contract],
    default_options={"store": False},
)


class IntakeRequest(BaseModel):
    issue_id: str
    customer: str
    requirement: str


SCENARIO_DENIALS = {
    "unknown_tool": (403, "tool_denied", "shell is not an approved tool"),
    "unknown_host": (403, "egress_denied", "unknown package host is not approved"),
    "repeated_loop": (429, "repair_limit", "repeated test loop exceeded its bound"),
    "mcp_unavailable": (503, "mcp_unavailable", "development MCP is unavailable"),
    "builder_self_approve": (
        403,
        "separation_of_duties",
        "Builder cannot approve its own patch",
    ),
    "reviewer_modify_source": (
        403,
        "separation_of_duties",
        "Reviewer cannot modify source",
    ),
    "untrusted_peer": (403, "peer_trust", "untrusted or expired peer draft rejected"),
    "self_modify_authority": (
        403,
        "authority_denied",
        "Builder cannot modify Agent, MCP, or approval configuration",
    ),
    "symlink_escape": (
        403,
        "artifact_symlink",
        "symbolic-link artifacts cannot enter the release handoff",
    ),
    "host_trust_handoff": (
        403,
        "artifact_scope",
        "hooks, tasks, interpreters, and host-executed artifacts are prohibited",
    ),
    "dns_egress": (
        403,
        "egress_denied",
        "DNS is not an approved data channel",
    ),
}


class RunRequest(BaseModel):
    issue_id: str
    customer: str
    scenario: Literal[
        "normal",
        "unknown_tool",
        "unknown_host",
        "repeated_loop",
        "mcp_unavailable",
        "builder_self_approve",
        "reviewer_modify_source",
        "untrusted_peer",
        "self_modify_authority",
        "symlink_escape",
        "host_trust_handoff",
        "dns_egress",
    ] = "normal"


def reject(request: RunRequest, status: int, code: str, detail: str) -> None:
    audit.append(
        "workflow_control",
        "denied",
        {"issueId": request.issue_id, "customer": request.customer, "code": code},
    )
    raise HTTPException(status_code=status, detail={"code": code, "message": detail})


@app.get("/healthz")
def healthz() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/contract")
def contract() -> dict[str, Any]:
    return {
        "model": MODEL,
        "runtimeKind": RUNTIME_KIND,
        "contractVersion": CONTRACT_VERSION,
        "supportOwner": SUPPORT_OWNER,
        "workflow": WORKFLOW,
        "approvedTools": APPROVED_TOOLS,
        "forbiddenActions": FORBIDDEN_ACTIONS,
        "taskConcurrencyLimit": CONCURRENCY_LIMIT,
        "dailyTaskLimit": DAILY_TASK_LIMIT,
        "providerCredentialNames": [
            name
            for name in os.environ
            if ("COPILOT" in name or "GITHUB" in name)
            and ("TOKEN" in name or "KEY" in name)
        ],
    }


@app.post("/intake")
def intake(request: IntakeRequest) -> dict[str, Any]:
    if request.issue_id != ISSUE_ID:
        raise HTTPException(status_code=403, detail="issue is outside the approved pilot")
    if "customer note" not in request.requirement.lower():
        raise HTTPException(status_code=422, detail="acceptance criterion is incomplete")
    audit.append(
        "openclaw_intake",
        "approved",
        {"issueId": ISSUE_ID, "customer": request.customer, "revision": REVISION},
    )
    return {
        "stage": "OPENCLAW_INTAKE",
        "issueId": ISSUE_ID,
        "customer": request.customer,
        "revision": REVISION,
        "acceptanceCriteria": [
            "missing optional customer note does not return 500",
            "existing note behavior remains unchanged",
            "targeted tests pass",
            "human approval is required before merge or deployment",
        ],
    }


@app.post("/run")
async def run(request: RunRequest) -> dict[str, Any]:
    if request.issue_id != ISSUE_ID:
        reject(request, 403, "scope_denied", "issue is outside the approved pilot")
    if (MODEL, CONTRACT_VERSION, RUNTIME_KIND) != (
        EXPECTED_MODEL,
        EXPECTED_CONTRACT,
        EXPECTED_KIND,
    ):
        reject(request, 503, "runtime_contract", "KARS runtime contract mismatch")

    if request.scenario in SCENARIO_DENIALS:
        status, code, detail = SCENARIO_DENIALS[request.scenario]
        reject(request, status, code, detail)

    try:
        ledger.acquire(request.customer)
    except ControlViolation as exc:
        reject(request, exc.status_code, exc.code, exc.detail)

    try:
        marker = "KARS_APPLIED_PROJECT_GPT_5_6_SOL_OK"
        request_id = uuid.uuid4().hex
        result = await asyncio.wait_for(
            builder.run(
                "OpenClaw Intake approved this immutable release contract:\n"
                f"request_id={request_id}\n"
                f"issue_id={ISSUE_ID}\n"
                f"revision={REVISION}\n"
                "Call inspect_release_contract exactly once with those values. "
                f"Then reply exactly: {marker} FAB-482 READY_FOR_HUMAN_REVIEW"
            ),
            timeout=120,
        )
        reply = result.text
        if marker not in reply:
            raise HTTPException(status_code=502, detail="unexpected model response")

        evidence = consume_tool_evidence(request_id)
        if evidence is None:
            raise HTTPException(
                status_code=502,
                detail="MAF Builder did not invoke the approved inspection tool",
            )
        patch = evidence["patch"]
        tests = evidence["tests"]
        artifact_path = validate_artifact_path("src/customer_note.py")
        handoff = Handoff(
            issue_id=ISSUE_ID,
            revision=REVISION,
            patch_digest=digest_text(patch),
            test_evidence_digest=digest_text(tests),
            artifact_manifest_digest=digest_text(artifact_path),
        )
        audit.append(
            "builder_handoff",
            "allowed",
            {
                "issueId": ISSUE_ID,
                "customer": request.customer,
                "handoffDigest": handoff.digest(),
            },
        )
        return {
            "model": MODEL,
            "issueId": ISSUE_ID,
            "customer": request.customer,
            "workflow": WORKFLOW,
            "patch": patch,
            "tests": tests,
            "handoff": {
                **handoff.__dict__,
                "digest": handoff.digest(),
            },
            "reply": reply.strip(),
            "mafAgent": builder.name,
            "mafTool": inspect_release_contract.name,
            "mafToolCalls": 1,
            "nextAction": "STOP_FOR_HUMAN_PR_APPROVAL",
        }
    finally:
        ledger.release()


@app.get("/usage")
def usage() -> dict[str, Any]:
    return ledger.report()


@app.get("/audit")
def audit_log() -> dict[str, Any]:
    entries = audit.snapshot()
    return {
        "integrity": "valid" if audit.verify() else "invalid",
        "entries": len(entries),
        "events": entries,
    }


@app.post("/mcp")
def mcp_metadata() -> dict[str, Any]:
    return {
        "name": "fabrikam-dev-tools",
        "status": "available",
        "tools": APPROVED_TOOLS,
    }
