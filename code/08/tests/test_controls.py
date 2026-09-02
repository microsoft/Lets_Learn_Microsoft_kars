import asyncio
import os
import sys
import types
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parents[1] / "pilot_agent"))
os.environ.setdefault("KARS_MODEL", "gpt-5.6-sol")
os.environ.setdefault("OPENAI_API_KEY", "router-managed")

runtime_module = types.ModuleType("kars_runtime_maf_python")
runtime_module.bootstrap = lambda: None
sys.modules.setdefault("kars_runtime_maf_python", runtime_module)

from app import (
    SCENARIO_DENIALS,
    builder,
    consume_tool_evidence,
    inspect_release_contract,
    maf_client,
)
from controls import (
    AuditChain,
    ControlViolation,
    Handoff,
    TaskLedger,
    digest_text,
    validate_artifact_path,
)


def test_handoff_is_digest_pinned() -> None:
    handoff = Handoff(
        issue_id="FAB-482",
        revision=digest_text("revision"),
        patch_digest=digest_text("patch"),
        test_evidence_digest=digest_text("tests"),
        artifact_manifest_digest=digest_text("src/customer_note.py"),
    )
    assert handoff.digest().startswith("sha256:")
    assert len(handoff.digest()) == 71
    with pytest.raises(ControlViolation, match="SHA-256"):
        Handoff(
            issue_id="FAB-482",
            revision="latest",
            patch_digest=digest_text("patch"),
            test_evidence_digest=digest_text("tests"),
            artifact_manifest_digest=digest_text("src/customer_note.py"),
        )


def test_audit_chain_detects_valid_history() -> None:
    chain = AuditChain()
    chain.append("intake", "approved", {"issueId": "FAB-482"})
    chain.append("tool", "denied", {"tool": "shell"})
    assert chain.verify()
    assert len(chain.snapshot()) == 2


def test_daily_customer_usage_is_reported() -> None:
    ledger = TaskLedger(concurrency_limit=1, daily_limit=2)
    ledger.acquire("fabrikam")
    ledger.release()
    ledger.acquire("contoso")
    ledger.release()
    assert ledger.report()["customers"] == {"contoso": 1, "fabrikam": 1}
    with pytest.raises(ControlViolation, match="daily task limit"):
        ledger.acquire("fabrikam")


def test_concurrency_limit_fails_closed() -> None:
    ledger = TaskLedger(concurrency_limit=1, daily_limit=10)
    ledger.acquire("fabrikam")
    with pytest.raises(ControlViolation, match="concurrency"):
        ledger.acquire("contoso")
    ledger.release()


def test_maf_builder_exposes_one_bounded_tool() -> None:
    assert type(maf_client).__name__ == "KarsOpenAIChatClient"
    assert inspect_release_contract.name == "inspect_release_contract"
    assert maf_client.function_invocation_configuration["max_function_calls"] == 1
    assert maf_client.function_invocation_configuration["max_iterations"] == 3
    assert builder.default_options["store"] is False


def test_maf_tool_produces_digest_ready_evidence() -> None:
    request_id = "test-request"
    asyncio.run(
        inspect_release_contract.invoke(
            arguments={
                "request_id": request_id,
                "issue_id": "FAB-482",
                "revision": "sha256:98ea5005d70f6471b35a1ab99c37d8fe34141b859b6d55e290ce1b9cbf877b43",
            }
        )
    )
    evidence = consume_tool_evidence(request_id)
    assert evidence is not None
    assert digest_text(evidence["patch"]).startswith("sha256:")
    assert "2 passed" in evidence["tests"]


def test_application_has_no_direct_router_http_client() -> None:
    source = (Path(__file__).parents[1] / "pilot_agent" / "app.py").read_text()
    assert "import httpx" not in source
    assert "/v1/responses" not in source
    assert 'pop("fc_id", None)' in source


def test_release_artifacts_cannot_escape_or_trigger_host_execution() -> None:
    assert validate_artifact_path("src/customer_note.py") == "src/customer_note.py"
    with pytest.raises(ControlViolation, match="escapes"):
        validate_artifact_path("../.vscode/settings.json")
    with pytest.raises(ControlViolation, match="source artifacts"):
        validate_artifact_path(".git/hooks/pre-commit")
    with pytest.raises(ControlViolation, match="symbolic-link"):
        validate_artifact_path("src/customer_note.py", is_symlink=True)


@pytest.mark.parametrize(
    "scenario",
    ["self_modify_authority", "symlink_escape", "host_trust_handoff", "dns_egress"],
)
def test_sandbox_escape_scenarios_are_explicitly_denied(scenario: str) -> None:
    status, code, detail = SCENARIO_DENIALS[scenario]
    assert status == 403
    assert code in {"authority_denied", "artifact_symlink", "artifact_scope", "egress_denied"}
    assert detail
