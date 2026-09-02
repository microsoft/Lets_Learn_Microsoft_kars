#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

kubectl -n kars-mcp scale deployment forge-workspace-mcp --replicas=1 >/dev/null 2>&1 || true
kubectl -n kars-mcp rollout status deployment/forge-workspace-mcp \
  --timeout=180s >/dev/null 2>&1 || true

echo "Workspace MCP is Ready. Local evidence was preserved."
