#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

contract="$(curl -fsS "http://127.0.0.1:${LOCAL_PORT}/contract")"
printf '%s\n' "${contract}" | jq . >"${EVIDENCE_DIR}/byo-runtime-contract.json"
jq -e '
  .model == "gpt-5.6-sol"
  and .runtimeKind == "BYO"
  and .contractVersion == "v1"
  and .routerUrl == "http://127.0.0.1:8443"
  and .providerCredentialNames == []
  and .workflow[-1] == "STOP_FOR_HUMAN_REVIEW"
  and (.forbiddenActions | contains(["MERGE", "DEPLOY"]))
' "${EVIDENCE_DIR}/byo-runtime-contract.json" >/dev/null \
  || fail "BYO runtime did not receive the expected KARS contract"
pass "BYO runtime received GPT-5.6-Sol and no Copilot provider credential"

egress="$(curl -fsS "http://127.0.0.1:${LOCAL_PORT}/direct-egress")"
printf '%s\n' "${egress}" | jq . >"${EVIDENCE_DIR}/byo-direct-egress.json"
jq -e '.blocked == true' "${EVIDENCE_DIR}/byo-direct-egress.json" >/dev/null \
  || fail "BYO agent unexpectedly reached the internet directly"
pass "BYO agent direct egress is denied"

curl -fsS \
  -H 'content-type: application/json' \
  --data '{"issue_id":"FORMAT-482"}' \
  "http://127.0.0.1:${LOCAL_PORT}/run" |
  jq . >"${EVIDENCE_DIR}/byo-model-response.json"
jq -e '
  .model == "gpt-5.6-sol"
  and .issueId == "FORMAT-482"
  and (.reply | contains("KARS_BYO_GPT_5_6_SOL_OK"))
  and (.reply | contains("STOP_FOR_HUMAN_REVIEW"))
  and .responseEvents > 0
' "${EVIDENCE_DIR}/byo-model-response.json" >/dev/null \
  || fail "BYO GPT-5.6-Sol response is inconsistent"
pass "BYO runtime reached GitHub Copilot GPT-5.6-Sol only through the KARS Router"

status="$(curl -sS -o "${EVIDENCE_DIR}/byo-scope-denial.json" -w '%{http_code}' \
  -H 'content-type: application/json' \
  --data '{"issue_id":"UNAPPROVED-1"}' \
  "http://127.0.0.1:${LOCAL_PORT}/run")"
[[ "${status}" == "403" ]] || fail "Unapproved issue did not return HTTP 403"
pass "BYO workflow rejects an issue outside the approved scope"

jq -e '
  .status.compiledDigest == .status.loadedDigest
  and .status.phase == "Ready"
  and .spec.modelPreference.primary.deployment == "gpt-5.6-sol"
' "${EVIDENCE_DIR}/byo-inference-policy.json" >/dev/null \
  || fail "BYO InferencePolicy is not loaded by the Router"
pass "BYO InferencePolicy digest is loaded and Ready"

jq -e '
  ([.containers[] | select(.name == "agent")] | length) == 1
  and
  ([.containers[] | select(.name == "agent")
    | .securityContext.runAsUser == 1000
      and .securityContext.readOnlyRootFilesystem == true
      and .securityContext.allowPrivilegeEscalation == false] | all)
  and
  ([.containers[] | select(.name == "inference-router")] | length) == 1
  and
  ([.containers[] | select(.name == "inference-router")
    | .securityContext.runAsUser == 1001] | all)
  and
  ([.initContainers[] | select(.name == "egress-guard")] | length) == 1
  and
  ([.initContainers[] | select(.name == "egress-guard")
    | (.securityContext.capabilities.add | contains(["NET_ADMIN"]))] | all)
' "${EVIDENCE_DIR}/byo-deployment-sanitized.json" >/dev/null \
  || fail "BYO pod does not preserve the KARS security shell"
pass "BYO keeps UID separation, read-only rootfs, and the egress guard"
