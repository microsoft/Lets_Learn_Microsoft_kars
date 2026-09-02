#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

kubectl -n kars-mcp port-forward \
  service/forge-workspace-mcp "${MCP_PORT}:8931"
