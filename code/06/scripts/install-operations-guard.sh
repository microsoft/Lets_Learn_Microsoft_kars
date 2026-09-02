#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

kubectl --context kind-kars-dev apply \
  -f "${LAB_ROOT}/manifests/byo-agent-exec-ban.yaml" >/dev/null

kubectl --context kind-kars-dev wait \
  --for=jsonpath='{.status.observedGeneration}'=1 \
  validatingadmissionpolicy/kars-byo-agent-exec-ban \
  --timeout=60s >/dev/null

pass "BYO agent exec/attach admission guard is installed"
