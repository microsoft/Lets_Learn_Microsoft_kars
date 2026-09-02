from __future__ import annotations

import unittest

from operations.repair_guard import RepairDecision, RepairGuard


class RepairGuardTests(unittest.TestCase):
    def test_stops_on_repeated_equivalent_patch(self) -> None:
        guard = RepairGuard(max_attempts=3, deadline_epoch_seconds=100)
        self.assertEqual(guard.evaluate("patch-a", 1), RepairDecision.RETRY)
        self.assertEqual(
            guard.evaluate("patch-a", 2),
            RepairDecision.NEEDS_HUMAN_DUPLICATE,
        )

    def test_stops_after_attempt_limit(self) -> None:
        guard = RepairGuard(max_attempts=2, deadline_epoch_seconds=100)
        self.assertEqual(guard.evaluate("patch-a", 1), RepairDecision.RETRY)
        self.assertEqual(guard.evaluate("patch-b", 2), RepairDecision.RETRY)
        self.assertEqual(
            guard.evaluate("patch-c", 3),
            RepairDecision.NEEDS_HUMAN_LIMIT,
        )

    def test_deadline_wins_before_new_attempt(self) -> None:
        guard = RepairGuard(max_attempts=3, deadline_epoch_seconds=10)
        self.assertEqual(
            guard.evaluate("patch-a", 10),
            RepairDecision.NEEDS_HUMAN_DEADLINE,
        )
        self.assertEqual(guard.attempts, 0)


if __name__ == "__main__":
    unittest.main()
