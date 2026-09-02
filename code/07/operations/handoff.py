from __future__ import annotations

import hashlib
import json
from dataclasses import asdict, dataclass
from enum import StrEnum


class Role(StrEnum):
    BUILDER = "builder"
    REVIEWER = "reviewer"


class Action(StrEnum):
    PROPOSE_PATCH = "propose_patch"
    REVIEW_PATCH = "review_patch"
    APPROVE_RELEASE = "approve_release"
    MODIFY_SOURCE = "modify_source"


@dataclass(frozen=True)
class HandoffEnvelope:
    issue_id: str
    patch_digest: str
    test_evidence_digest: str
    artifact_manifest_digest: str
    producer: Role
    intended_consumer: Role
    model: str = "gpt-5.6-sol"

    def digest(self) -> str:
        payload = json.dumps(
            asdict(self),
            sort_keys=True,
            separators=(",", ":"),
        ).encode()
        return f"sha256:{hashlib.sha256(payload).hexdigest()}"


def is_sha256_digest(value: str) -> bool:
    if not value.startswith("sha256:") or len(value) != 71:
        return False
    try:
        int(value[7:], 16)
    except ValueError:
        return False
    return True


def authorize(role: Role, action: Action, envelope: HandoffEnvelope) -> bool:
    if envelope.model != "gpt-5.6-sol":
        return False
    if not is_sha256_digest(envelope.patch_digest):
        return False
    if not is_sha256_digest(envelope.test_evidence_digest):
        return False
    if not is_sha256_digest(envelope.artifact_manifest_digest):
        return False

    if role is Role.BUILDER:
        return action is Action.PROPOSE_PATCH

    if envelope.intended_consumer is not Role.REVIEWER:
        return False
    if envelope.producer is Role.REVIEWER:
        return False
    return action in {Action.REVIEW_PATCH, Action.APPROVE_RELEASE}
