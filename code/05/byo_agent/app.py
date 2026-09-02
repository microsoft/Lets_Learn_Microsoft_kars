from __future__ import annotations

import json
import os
import socket
from typing import Any

import httpx
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from workflow import WORKFLOW

MODEL = os.environ.get("KARS_MODEL", "")
ROUTER_URL = os.environ.get("KARS_ROUTER_URL", "http://127.0.0.1:8443")
CONTRACT_VERSION = os.environ.get("KARS_RUNTIME_CONTRACT_VERSION", "")
RUNTIME_KIND = os.environ.get("KARS_RUNTIME_KIND", "")
EXPECTED_MODEL = "gpt-5.6-sol"
EXPECTED_CONTRACT = "v1"
EXPECTED_KIND = "BYO"

app = FastAPI(title="forge-byo-copilot-claw")


class RunRequest(BaseModel):
    issue_id: str


def extract_output_text(events: list[dict[str, Any]]) -> str:
    deltas = [
        event.get("delta", "")
        for event in events
        if event.get("type") == "response.output_text.delta"
    ]
    if deltas:
        return "".join(str(delta) for delta in deltas)

    for event in reversed(events):
        response = event.get("response")
        if not isinstance(response, dict):
            continue
        output = response.get("output", [])
        for item in output:
            for content in item.get("content", []):
                if content.get("type") == "output_text":
                    return str(content.get("text", ""))
    return ""


def call_router(prompt: str) -> tuple[str, list[dict[str, Any]]]:
    payload = {
        "model": MODEL,
        "input": prompt,
        "max_output_tokens": 64,
        "stream": True,
    }
    events: list[dict[str, Any]] = []
    with httpx.stream(
        "POST",
        f"{ROUTER_URL}/v1/responses",
        headers={"authorization": "Bearer kars-router"},
        json=payload,
        timeout=120,
    ) as response:
        response.raise_for_status()
        for line in response.iter_lines():
            if not line.startswith("data: "):
                continue
            data = line[6:]
            if data == "[DONE]":
                continue
            events.append(json.loads(data))
    return extract_output_text(events), events


@app.get("/healthz")
def healthz() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/contract")
def contract() -> dict[str, object]:
    return {
        "model": MODEL,
        "runtimeKind": RUNTIME_KIND,
        "contractVersion": CONTRACT_VERSION,
        "routerUrl": ROUTER_URL,
        "workflow": WORKFLOW,
        "forbiddenActions": ["MERGE", "DEPLOY"],
        "providerCredentialNames": [
            name
            for name in os.environ
            if (
                ("COPILOT" in name or "GITHUB" in name)
                and ("TOKEN" in name or "KEY" in name)
            )
        ],
    }


@app.get("/direct-egress")
def direct_egress() -> dict[str, object]:
    try:
        with socket.create_connection(("example.com", 443), timeout=3):
            return {"blocked": False, "detail": "direct connection unexpectedly succeeded"}
    except OSError as exc:
        return {"blocked": True, "detail": type(exc).__name__}


@app.post("/run")
def run(request: RunRequest) -> dict[str, object]:
    if request.issue_id != "FORMAT-482":
        raise HTTPException(status_code=403, detail="issue is outside the approved scope")
    if (MODEL, CONTRACT_VERSION, RUNTIME_KIND) != (
        EXPECTED_MODEL,
        EXPECTED_CONTRACT,
        EXPECTED_KIND,
    ):
        raise HTTPException(status_code=503, detail="KARS runtime contract mismatch")

    marker = "KARS_BYO_GPT_5_6_SOL_OK"
    prompt = (
        "You are the KARS BYO Forge candidate. Reply on one line with exactly: "
        f"{marker} FORMAT-482 STOP_FOR_HUMAN_REVIEW"
    )
    reply, events = call_router(prompt)
    if marker not in reply:
        raise HTTPException(status_code=502, detail=f"unexpected model response: {reply}")
    return {
        "model": MODEL,
        "issueId": request.issue_id,
        "workflow": WORKFLOW,
        "reply": reply.strip(),
        "responseEvents": len(events),
    }
