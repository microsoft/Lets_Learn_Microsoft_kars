#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

if [[ ! -x "${LAB_ROOT}/.venv/bin/python" ]]; then
  python3 -m venv "${LAB_ROOT}/.venv"
fi

PIP_INDEX_URL="${PIP_INDEX_URL}" \
  "${LAB_ROOT}/.venv/bin/pip" install --quiet -r "${LAB_ROOT}/requirements.txt"

pass "Python dependencies are installed from Microsoft Package Feed Proxy"
