from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum
from pathlib import PurePosixPath


class WorkflowState(StrEnum):
    RECEIVE_REQUIREMENT = "RECEIVE_REQUIREMENT"
    VALIDATE_SCOPE = "VALIDATE_SCOPE"
    INSPECT_REPOSITORY = "INSPECT_REPOSITORY"
    PROPOSE_PLAN = "PROPOSE_PLAN"
    VERIFY_IMMUTABLE_RUNTIME_ARTIFACT = "VERIFY_IMMUTABLE_RUNTIME_ARTIFACT"
    APPLY_MINIMAL_PATCH = "APPLY_MINIMAL_PATCH"
    RUN_TARGETED_TESTS = "RUN_TARGETED_TESTS"
    SUMMARIZE_EVIDENCE = "SUMMARIZE_EVIDENCE"
    STOP_FOR_HUMAN_REVIEW = "STOP_FOR_HUMAN_REVIEW"


WORKFLOW = tuple(WorkflowState)
ALLOWED_ISSUE = "FORMAT-482"
ALLOWED_TEST = "format-user"


@dataclass(frozen=True)
class ForgeContract:
    issue_id: str
    allowed_test: str
    states: tuple[WorkflowState, ...]
    forbidden_actions: tuple[str, ...] = (
        "MERGE",
        "DEPLOY",
        "MODIFY_AGENT_CONFIGURATION",
        "CREATE_HOST_EXECUTED_ARTIFACT",
    )

    def to_dict(self) -> dict[str, object]:
        return {
            "issueId": self.issue_id,
            "allowedTest": self.allowed_test,
            "states": [state.value for state in self.states],
            "forbiddenActions": list(self.forbidden_actions),
        }


def contract_for(issue_id: str) -> ForgeContract:
    if issue_id != ALLOWED_ISSUE:
        raise ValueError(f"issue {issue_id!r} is outside the approved scope")
    return ForgeContract(
        issue_id=ALLOWED_ISSUE,
        allowed_test=ALLOWED_TEST,
        states=WORKFLOW,
    )


def validate_runtime_artifact(
    artifact_path: str,
    artifact_digest: str,
    *,
    is_symlink: bool = False,
) -> PurePosixPath:
    path = PurePosixPath(artifact_path)
    if not path.is_absolute() or path == PurePosixPath("/app"):
        raise ValueError("runtime artifact must be an absolute file under /app")
    if PurePosixPath("/app") not in path.parents:
        raise ValueError("runtime artifact must remain under immutable /app")
    if ".." in path.parts or is_symlink:
        raise ValueError("runtime artifact cannot use traversal or symbolic links")
    if not artifact_digest.startswith("sha256:") or len(artifact_digest) != 71:
        raise ValueError("runtime artifact must be digest pinned")
    try:
        int(artifact_digest[7:], 16)
    except ValueError as exc:
        raise ValueError("runtime artifact digest is invalid") from exc
    return path
