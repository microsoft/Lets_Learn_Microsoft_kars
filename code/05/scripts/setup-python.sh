#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

if [[ ! -x "${VENV_DIR}/bin/python" ]]; then
  python3 -m venv "${VENV_DIR}"
fi

"${VENV_DIR}/bin/pip" install --quiet --requirement "${LAB_ROOT}/requirements.txt"
"${VENV_DIR}/bin/python" -c \
  'from importlib.metadata import version; assert version("agent-framework-github-copilot") == "1.0.3"'
pass "Microsoft Agent Framework GitHub Copilot provider 1.0.3 is installed"
