from __future__ import annotations

import unittest

from operations.handoff import Action, HandoffEnvelope, Role, authorize


SHA_A = "sha256:" + "a" * 64
SHA_B = "sha256:" + "b" * 64


class HandoffTests(unittest.TestCase):
    def setUp(self) -> None:
        self.envelope = HandoffEnvelope(
            issue_id="FORMAT-482",
            patch_digest=SHA_A,
            test_evidence_digest=SHA_B,
            artifact_manifest_digest=SHA_A,
            producer=Role.BUILDER,
            intended_consumer=Role.REVIEWER,
        )

    def test_builder_can_propose_but_cannot_approve(self) -> None:
        self.assertTrue(
            authorize(Role.BUILDER, Action.PROPOSE_PATCH, self.envelope)
        )
        self.assertFalse(
            authorize(Role.BUILDER, Action.APPROVE_RELEASE, self.envelope)
        )

    def test_reviewer_can_review_and_approve_builder_artifact(self) -> None:
        self.assertTrue(
            authorize(Role.REVIEWER, Action.REVIEW_PATCH, self.envelope)
        )
        self.assertTrue(
            authorize(Role.REVIEWER, Action.APPROVE_RELEASE, self.envelope)
        )

    def test_reviewer_cannot_modify_source(self) -> None:
        self.assertFalse(
            authorize(Role.REVIEWER, Action.MODIFY_SOURCE, self.envelope)
        )

    def test_self_review_is_denied(self) -> None:
        self_review = HandoffEnvelope(
            issue_id="FORMAT-482",
            patch_digest=SHA_A,
            test_evidence_digest=SHA_B,
            artifact_manifest_digest=SHA_A,
            producer=Role.REVIEWER,
            intended_consumer=Role.REVIEWER,
        )
        self.assertFalse(
            authorize(Role.REVIEWER, Action.APPROVE_RELEASE, self_review)
        )

    def test_unpinned_evidence_or_wrong_model_is_denied(self) -> None:
        invalid = HandoffEnvelope(
            issue_id="FORMAT-482",
            patch_digest="latest",
            test_evidence_digest=SHA_B,
            artifact_manifest_digest=SHA_A,
            producer=Role.BUILDER,
            intended_consumer=Role.REVIEWER,
            model="gpt-5-mini",
        )
        self.assertFalse(
            authorize(Role.REVIEWER, Action.REVIEW_PATCH, invalid)
        )

    def test_unpinned_artifact_manifest_is_denied(self) -> None:
        invalid = HandoffEnvelope(
            issue_id="FORMAT-482",
            patch_digest=SHA_A,
            test_evidence_digest=SHA_B,
            artifact_manifest_digest="workspace-latest",
            producer=Role.BUILDER,
            intended_consumer=Role.REVIEWER,
        )
        self.assertFalse(authorize(Role.REVIEWER, Action.APPROVE_RELEASE, invalid))

    def test_envelope_digest_is_deterministic(self) -> None:
        self.assertEqual(self.envelope.digest(), self.envelope.digest())
        self.assertRegex(self.envelope.digest(), r"^sha256:[0-9a-f]{64}$")


if __name__ == "__main__":
    unittest.main()
