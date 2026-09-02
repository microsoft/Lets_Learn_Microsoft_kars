#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

python3 -m venv "${LAB_ROOT}/.venv"
"${LAB_ROOT}/.venv/bin/python" -m pip install \
  --index-url "${PIP_INDEX_URL}" \
  --requirement "${LAB_ROOT}/requirements.txt" \
  --quiet
pass "Python dependencies are installed from Microsoft Package Feed Proxy"
