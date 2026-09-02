from __future__ import annotations

import unittest

from host_agent.workflow import (
    ALLOWED_ISSUE,
    ALLOWED_TEST,
    WORKFLOW,
    WorkflowState,
    contract_for,
    validate_runtime_artifact,
)


class WorkflowTests(unittest.TestCase):
    def test_contract_stops_for_human_review(self) -> None:
        contract = contract_for(ALLOWED_ISSUE)
        self.assertEqual(contract.allowed_test, ALLOWED_TEST)
        self.assertEqual(contract.states, WORKFLOW)
        self.assertEqual(contract.states[-1], WorkflowState.STOP_FOR_HUMAN_REVIEW)
        self.assertNotIn("MERGE", [state.value for state in contract.states])
        self.assertNotIn("DEPLOY", [state.value for state in contract.states])

    def test_unknown_issue_fails_closed(self) -> None:
        with self.assertRaisesRegex(ValueError, "outside the approved scope"):
            contract_for("UNAPPROVED-1")

    def test_runtime_artifact_is_immutable_and_digest_pinned(self) -> None:
        digest = "sha256:" + "a" * 64
        self.assertEqual(
            str(validate_runtime_artifact("/app/forge/agent.py", digest)),
            "/app/forge/agent.py",
        )
        with self.assertRaisesRegex(ValueError, "immutable /app"):
            validate_runtime_artifact("/sandbox/settings.json", digest)
        with self.assertRaisesRegex(ValueError, "symbolic links"):
            validate_runtime_artifact("/app/forge/agent.py", digest, is_symlink=True)
        with self.assertRaisesRegex(ValueError, "digest pinned"):
            validate_runtime_artifact("/app/forge/agent.py", "latest")


if __name__ == "__main__":
    unittest.main()
