from __future__ import annotations

from dataclasses import dataclass, field
from enum import StrEnum


class RepairDecision(StrEnum):
    RETRY = "retry"
    NEEDS_HUMAN_DUPLICATE = "needs_human_duplicate"
    NEEDS_HUMAN_LIMIT = "needs_human_limit"
    NEEDS_HUMAN_DEADLINE = "needs_human_deadline"


@dataclass
class RepairGuard:
    max_attempts: int
    deadline_epoch_seconds: int
    attempts: int = 0
    patch_digests: set[str] = field(default_factory=set)

    def evaluate(self, patch_digest: str, now_epoch_seconds: int) -> RepairDecision:
        if now_epoch_seconds >= self.deadline_epoch_seconds:
            return RepairDecision.NEEDS_HUMAN_DEADLINE
        if patch_digest in self.patch_digests:
            return RepairDecision.NEEDS_HUMAN_DUPLICATE
        if self.attempts >= self.max_attempts:
            return RepairDecision.NEEDS_HUMAN_LIMIT

        self.patch_digests.add(patch_digest)
        self.attempts += 1
        return RepairDecision.RETRY
