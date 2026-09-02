#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

PYTHONPATH="${LAB_ROOT}" python3 -m unittest discover \
  -s "${LAB_ROOT}/tests" \
  -p 'test_*.py'
pass "Repair limits and audit tamper detection pass deterministic unit tests"
