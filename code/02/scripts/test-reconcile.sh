#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
require_forge

if [[ "${ALLOW_POD_RESTART:-0}" != "1" ]]; then
  echo "SKIP: set ALLOW_POD_RESTART=1 to test controller reconciliation"
  exit 0
fi

namespace="$(forge_namespace)"
old_pod="$(forge_pod)"
old_uid="$(kubectl -n "${namespace}" get pod "${old_pod}" -o jsonpath='{.metadata.uid}')"

kubectl -n "${namespace}" delete pod "${old_pod}" --wait=false >/dev/null
kubectl -n "${namespace}" rollout status deployment/forge --timeout=240s >/dev/null

new_pod="$(forge_pod)"
new_uid="$(kubectl -n "${namespace}" get pod "${new_pod}" -o jsonpath='{.metadata.uid}')"
[[ "${new_uid}" != "${old_uid}" ]] || fail "Controller did not replace the deleted Forge Pod"
[[ "$(kubectl -n kars-system get karssandbox forge -o jsonpath='{.status.phase}')" == "Running" ]] \
  || fail "Forge did not return to Running"

cat >"${EVIDENCE_DIR}/reconciliation.json" <<EOF
{
  "oldPod": "${old_pod}",
  "oldUid": "${old_uid}",
  "newPod": "${new_pod}",
  "newUid": "${new_uid}",
  "sandboxPhase": "Running"
}
EOF

pass "KARS controller replaced ${old_pod} with ${new_pod}"
