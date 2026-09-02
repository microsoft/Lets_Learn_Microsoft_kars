from __future__ import annotations

import unittest
from dataclasses import replace

from operations.audit_chain import (
    BoundaryChannel,
    boundary_denial,
    build_chain,
    verify_chain,
)


class AuditChainTests(unittest.TestCase):
    def test_detects_modified_record(self) -> None:
        records = build_chain(
            [
                {"action": "inference", "decision": "allow"},
                {"action": "egress", "decision": "deny"},
            ]
        )
        self.assertTrue(verify_chain(records))

        records[0] = replace(
            records[0],
            payload={"action": "inference", "decision": "deny"},
        )
        self.assertFalse(verify_chain(records))

    def test_records_covert_egress_and_requires_break_glass_incident(self) -> None:
        records = build_chain(
            [
                boundary_denial(BoundaryChannel.HTTPS, "collect.example"),
                boundary_denial(BoundaryChannel.DNS, "encoded.collect.example"),
                boundary_denial(BoundaryChannel.METADATA, "link-local"),
                boundary_denial(BoundaryChannel.LOCAL_DAEMON, "docker.sock"),
            ]
        )
        self.assertTrue(verify_chain(records))
        self.assertTrue(all(record.payload["decision"] == "deny" for record in records))
        with self.assertRaisesRegex(ValueError, "incident ID"):
            boundary_denial(BoundaryChannel.EXEC, "agent", break_glass=True)


if __name__ == "__main__":
    unittest.main()
