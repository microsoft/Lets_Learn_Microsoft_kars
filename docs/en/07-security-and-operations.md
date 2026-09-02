# 7. Security and Operations: Contain, Observe, and Recover Forge

> **Delivery stage:** Operate the Chapter 6 BYO production candidate
> **Starting point:** OpenClaw Forge behavior, now running as a kars BYO
> workload with GitHub Copilot GPT-5.6-Sol
> **Executable lab:** [`code/06`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/06)

## Everything still starts from OpenClaw

Chapter 1 defined the OpenClaw issue-to-patch workflow. Chapters 2 through 5
bounded its filesystem, Kubernetes API, tools, and policies. Chapter 6 kept the
same Forge contract while adding a host-side Microsoft Agent Framework canary
and an in-cluster kars BYO runtime.

Chapter 7 operates that real runtime:

```text
OpenClaw FORMAT-482 workflow
    -> application Repair Guard
    -> BYO agent, UID 1000, no provider credential
    -> localhost kars Router, UID 1001
    -> GitHub Copilot GPT-5.6-Sol
    -> policy decisions, audit chain, metrics, recovery evidence
```

The lesson is not that an Agent will never fail. It is that a failed Agent must
stop, leave evidence, remain inside its authority, and recover through an
understood procedure.

## Run the real experiment

First complete [`code/05`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/05), then run:

```bash
cd code/06
make test
```

The validated run used macOS arm64. The scripts also support macOS amd64 and
Linux amd64. Windows amd64 uses Ubuntu WSL2 with Docker Desktop WSL integration.

The lab enforces Microsoft Package Feed Proxy for npm, PyPI, and NuGet, reuses
the authenticated GitHub Copilot CLI, and fixes the model to `gpt-5.6-sol`.

## Stop the repair loop in the application

A platform budget limits cost, but it cannot determine whether two patches are
equivalent or whether the task has exceeded its business deadline. The
`RepairGuard` in
[`code/06/operations/repair_guard.py`](https://github.com/kinfey/LetsLearnMicrosoftKars/blob/main/code/06/operations/repair_guard.py)
returns explicit
human-escalation decisions for:

- the same patch digest appearing twice;
- more than the configured repair attempts;
- a task reaching its deadline before a new attempt.

The deterministic tests run before any live model call. The OpenClaw-derived
workflow still ends at `STOP_FOR_HUMAN_REVIEW`; no merge or deploy action is
introduced.

## Capture evidence before changing the workload

The incident inventory records:

- `KarsSandbox` and `InferencePolicy` state;
- sanitized Deployment security contexts and environment variable names;
- Pod image IDs, UIDs, readiness, and restart counts;
- namespace Events;
- admission policies;
- least-privilege RBAC results.

The live Sandbox ServiceAccount returned:

```json
{
  "canGetSecrets": "no",
  "canCreatePods": "no"
}
```

The evidence deliberately excludes Secret values.

## Close the BYO exec-policy gap

The installed upstream `kars-sandbox-exec-ban` matched the OpenClaw container
name `openclaw`. The Chapter 6 BYO runtime uses the container name `agent`, so
an initial harmless `kubectl exec ... -- true` succeeded.

[`code/06/manifests/byo-agent-exec-ban.yaml`](https://github.com/kinfey/LetsLearnMicrosoftKars/blob/main/code/06/manifests/byo-agent-exec-ban.yaml)
adds the same fail-closed control
for `agent` containers in namespaces labeled
`kars.azure.com/isolated=strict`. With no break-glass label, the API server
returns:

```text
ValidatingAdmissionPolicy 'kars-byo-agent-exec-ban' ... denied request:
exec/attach into the BYO agent runtime is denied
```

This is why security tests must target the actual runtime shape, not only the
original OpenClaw container name.

## Verify the mediated path

The boundary phase proves:

- the runtime contract still names `gpt-5.6-sol`;
- provider credential names are absent from the Agent environment;
- direct Internet egress from the Agent times out;
- exec/attach into the BYO Agent is denied;
- a normal request still succeeds through `127.0.0.1:8443`.

The Router then exposes operational evidence:

```bash
curl http://127.0.0.1:18444/agt/audit
curl http://127.0.0.1:18444/agt/audit/verify
curl http://127.0.0.1:18444/agt/status
curl http://127.0.0.1:18444/metrics
```

The completed run reported `integrity: valid`, `Hash chain verified`, native
governance, a loaded policy, and kars audit/inference metrics.

## Exercise a token-budget incident

The lab temporarily changes:

```yaml
spec:
  tokenBudget:
    perRequestTokens: 16
```

The current Router fast-fail implementation checks declared output limits on
the Chat Completions path. A request with `max_tokens: 17` receives:

```json
{
  "error": {
    "message": "Requested max_tokens=17 exceeds InferencePolicy tokenBudget.perRequestTokens=16",
    "type": "token_budget_exceeded",
    "code": "per_request_tokens_exceeded"
  }
}
```

The HTTP status is 429. The lab then restores `1024` and runs GPT-5.6-Sol again
through the BYO application's `/v1/responses` path.

These are separate verified claims. This experiment does not claim that the
Responses route has identical declared-token preflight enforcement.

## Treat policy activation as a rollout

The generated ConfigMap changed, but the running Router Pod kept the old
mounted profile during the experiment. Its loaded digest therefore did not
converge until the Deployment restarted.

The runbook performs:

```bash
kubectl -n kars-forge-byo-copilot-claw rollout restart \
  deployment/forge-byo-copilot-claw
kubectl -n kars-forge-byo-copilot-claw rollout status \
  deployment/forge-byo-copilot-claw
```

It waits until:

- the Policy generation equals `status.observedGeneration`;
- `compiledDigest` equals `loadedDigest`;
- phase is `Ready`.

The same procedure is used when restoring the original policy, including from
the exit trap after a failure.

## Recover from Pod loss

After collecting volatile evidence, the experiment deletes only the current
Pod by its exact name. The Deployment creates a replacement with a different
UID and returns to Ready. Port-forwards are re-established, the BYO endpoint
calls GPT-5.6-Sol, and the Router verifies a new audit chain.

This proves Pod self-healing. It does not prove a controller upgrade, cluster
restore, or regional disaster-recovery procedure; those require separate
runbooks and tests.

## Audit integrity is not audit persistence

Before Pod replacement, the Router had two audit entries. Immediately after
replacement, it had zero:

```json
{
  "beforeRestart": 2,
  "immediatelyAfterRestart": 0,
  "persisted": false
}
```

The next request started a new chain and `/agt/audit/verify` again returned
valid. That proves tamper detection inside the current in-memory chain. It does
not preserve incident history across Pod loss.

Production operation must stream audit records to an independently controlled,
durable backend before deleting a suspect Pod. Chain-head signing and stronger
non-repudiation must also be evaluated against the kars maturity documentation.

## Record the release, not only the response

The final record includes:

| Field | Validated value |
| --- | --- |
| kars | `0.1.25` |
| Model | `gpt-5.6-sol` |
| Runtime | `BYO` |
| Repository | exact Git commit |
| Workload | exact image digest |
| Policy | exact loaded digest |

An Agent saying "the test passed" is not release evidence. The response,
policy decision, runtime identity, image, and source revision must be
correlated.

## Provider telemetry caveat

GitHub Copilot applies provider-side safety controls, but the Router path used
here does not receive Azure AI Foundry-style `prompt_filter_results` with the
same visible categories and severities. Operations dashboards must represent
the telemetry that the selected provider actually exposes.

## Production checklist

- Keep application attempt/deadline/duplicate guards in addition to platform
  budgets.
- Extend admission controls whenever a new runtime changes container names or
  resource shapes.
- Export audit and metrics outside the workload before destructive response.
- Alert on denial patterns and budget exhaustion, not every successful denial.
- Use workload identity or Router-owned credentials; keep credentials out of
  the Agent.
- Pin kars, images, models, and policy artifacts.
- Test policy activation, rollback, Pod recovery, upgrades, and restore
  separately.
- Preserve human approval before merge, release, or deployment.

## Definition of done

The security and operations test is complete when the OpenClaw-derived workflow
stops bad repair loops, the real BYO runtime stays inside credential/network/
exec boundaries, over-budget traffic receives a machine-verifiable denial,
audit integrity is checked without confusing it with persistence, the workload
recovers with a new Pod UID, GPT-5.6-Sol succeeds afterward, and a release
record pins the exact software and policy inputs.

## Official references

- [kars security](https://github.com/Azure/kars/blob/main/docs/security.md)
- [kars maturity](https://github.com/Azure/kars/blob/main/docs/maturity.md)
- [kars operations](https://github.com/Azure/kars/tree/main/docs/operations)
- [Secret rotation](https://github.com/Azure/kars/blob/main/docs/operations/secret-rotation.md)
- [Upgrades](https://github.com/Azure/kars/blob/main/docs/operations/upgrades.md)
- [Chaos tier](https://github.com/Azure/kars/blob/main/docs/operations/chaos-tier.md)
- [SRE runbook](https://github.com/Azure/kars/blob/main/docs/runbooks/sre.md)
- [Microsoft Agent Framework GitHub Copilot samples](https://github.com/microsoft/agent-framework/tree/main/python/samples/02-agents/providers/github_copilot)
- [Microsoft Agent Framework Build Your Own Claw](https://github.com/microsoft/agent-framework/tree/main/python/samples/02-agents/harness/build_your_own_claw)
## Sandbox-escape checkpoint: investigate covert channels

Incident response must distinguish HTTPS, DNS, metadata-service, local-daemon,
and exec attempts. `code/06` records each denied channel in the hash-linked
audit chain and rejects break-glass records that have no incident ID.

KARS gives Operations a common control and evidence plane across runtimes:
Controller Conditions, Router denials, policy budgets, admission decisions,
and workload recovery can be investigated as one sequence.

```bash
cd code/06
make unit
make test
```

This prevents “network blocked” from becoming an unsupported conclusion when a
different egress channel or operator bypass was attempted.
