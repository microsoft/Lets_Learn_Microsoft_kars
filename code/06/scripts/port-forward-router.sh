#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

exec kubectl --context kind-kars-dev -n "${SANDBOX_NAMESPACE}" port-forward \
  "deployment/${SANDBOX_NAME}" "${ROUTER_PORT}:8443"
