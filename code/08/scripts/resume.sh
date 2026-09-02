#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

kubectl --context "${KARS_KUBE_CONTEXT}" -n kars-system patch \
  "karssandbox/${KARS_SANDBOX_NAME}" --type=merge \
  -p '{"spec":{"suspended":false}}' >/dev/null
pass "Release Pilot is resumed"
