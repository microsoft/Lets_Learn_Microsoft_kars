# kars security and operations lab

[English](README.md) | [简体中文](README.zh.md)

This lab starts with the OpenClaw Forge workflow from
[`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01)
and operates the GPT-5.6-Sol kars BYO runtime deployed by
[`code/05`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/05):

```text
OpenClaw issue-to-patch contract
    -> bounded repair loop
    -> kars BYO agent (UID 1000)
    -> localhost Inference Router (UID 1001)
    -> GitHub Copilot GPT-5.6-Sol
    -> audit, policy, metrics, recovery, release evidence
```

It does not simulate a second application. It changes policy, replaces the
real `forge-byo-copilot-claw` Pod, verifies recovery, and restores the original
1024-token limit.

## What the lab proves

- A deterministic Repair Guard stops repeated equivalent patches, excess
  attempts, and expired tasks before another model call.
- The host-side Microsoft Agent Framework
  `GitHubCopilotAgent` canary still calls GPT-5.6-Sol.
- The Sandbox ServiceAccount cannot read Secrets or create Pods.
- The Agent environment contains no GitHub/Copilot provider credential names.
- Direct Agent egress remains denied.
- The upstream exec admission policy targets the `openclaw` container name.
  [`code/06`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/06)
  installs a complementary policy for the BYO `agent` container and
  proves `kubectl exec` is denied.
- `/agt/audit/verify` reports a valid Router hash chain and `/agt/status`
  reports native governance with a loaded policy.
- A temporary 16-token policy rejects a Chat Completions request declaring
  `max_tokens: 17` with HTTP 429 and code
  `per_request_tokens_exceeded`.
- In this environment, the generated policy ConfigMap did not refresh in the
  running Router Pod. The incident procedure therefore performs an explicit
  Deployment rollout after both the temporary policy and the restored policy.
- Deleting the active Pod causes the Deployment to create a new Ready Pod, and
  GPT-5.6-Sol succeeds again through `/v1/responses`.
- The local Router audit count changed from two entries to zero immediately
  after Pod replacement. A new valid chain starts after the next request, but
  production history requires external audit export.
- The release record pins repository commit, kars version, model, runtime,
  image ID, and loaded policy digest.

## Microsoft package sources

The lab applies and verifies:

- npm: `https://packagefeedproxy.microsoft.io/npm/`
- PyPI: `https://packagefeedproxy.microsoft.io/pypi/simple/`
- NuGet: `https://packagefeedproxy.microsoft.io/nuget/v3/index.json`

The source rewrites inherited from
[`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01)
are restored when the run exits.

## Prerequisites

- Complete [`code/05`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/05)
  first. `forge-byo-copilot-claw` must be
  `Running`.
- Docker Desktop, kind, kubectl, jq, curl, Python 3.11+, and Node.js 22.
- GitHub Copilot CLI installed and authenticated.
- kars provider `github-copilot` with access to `gpt-5.6-sol`.

## Run

```bash
cd code/06
make test
```

The test performs real Pod rollouts and briefly changes
`forge-byo-inference.spec.tokenBudget.perRequestTokens` from `1024` to `16`.
Exit traps restore the original value if a later assertion fails.

Successful output ends with:

```text
All security and operations checks passed.
Evidence: .../code/06/.evidence/<UTC timestamp>
```

Useful focused commands:

```bash
make unit
make inspect
make clean
```

`make clean` removes the
[`code/06`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/06)
BYO exec admission guard and confirms the
[`code/05`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/05)
runtime and original inference budget are healthy. It does not delete the
[`code/05`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/05)
Sandbox.

## Incident sequence

1. Verify Microsoft sources and deterministic Repair Guard tests.
2. Run the MAF GitHub Copilot GPT-5.6-Sol canary.
3. Install the BYO `agent` exec/attach admission guard.
4. Capture sanitized Sandbox, Policy, Deployment, Pod, Event, and RBAC data.
5. Verify credential isolation, direct-egress denial, and exec denial.
6. Generate a real GPT-5.6-Sol audit record and capture audit/status/metrics.
7. Apply the temporary token budget, roll the Pod, require HTTP 429, restore
   the policy, roll again, and run a model smoke test.
8. Delete the current Pod by exact name and wait for Deployment recovery.
9. Compare audit counts across replacement and start a new verified chain.
10. Write the release record.

## Evidence

Each run stores evidence under `.evidence/<UTC timestamp>/`, including:

```text
transcript.log
host-copilot-agent.json
sandbox-rbac.json
exec-admission-policies.json
exec-denial.txt
baseline-model-response.json
audit-before-restart.json
audit-verify-before-restart.json
governance-status-before-restart.json
metrics-before-restart.txt
budget-denial.json
restart.json
audit-persistence.json
audit-verify-after-restart.json
post-restart-model-response.json
release-record.json
```

Secret values are not exported. Deployment evidence retains environment
variable names only.

## Operational boundaries

- The Repair Guard and Router token budget solve different problems. The
  application stops a bad loop; the platform limits its cost.
- The verified fast-fail budget path is `/v1/chat/completions` with
  `max_tokens` or `max_completion_tokens`. The BYO application smoke path uses
  `/v1/responses`; this lab does not claim identical preflight enforcement for
  that route.
- A valid in-memory audit chain proves mutation detection for its current
  lifetime, not persistence across Pod loss.
- The lab validates Pod self-healing, not a full kars controller upgrade or
  database restore.
- GitHub Copilot applies provider-side safety controls, but this Router path
  does not expose Azure AI Foundry-style `prompt_filter_results`.

## Platform support

The completed run was validated on macOS arm64. The inherited scripts also
support macOS amd64 and Linux amd64. On Windows amd64, run the lab inside
Ubuntu WSL2 with Docker Desktop WSL integration enabled; use Linux paths and
tools inside WSL2.

## References

- [kars security](https://github.com/Azure/kars/blob/main/docs/security.md)
- [kars maturity](https://github.com/Azure/kars/blob/main/docs/maturity.md)
- [kars operations](https://github.com/Azure/kars/tree/main/docs/operations)
- [kars SRE runbook](https://github.com/Azure/kars/blob/main/docs/runbooks/sre.md)
- [Microsoft Agent Framework GitHub Copilot samples](https://github.com/microsoft/agent-framework/tree/main/python/samples/02-agents/providers/github_copilot)
- [Microsoft Agent Framework Build Your Own Claw samples](https://github.com/microsoft/agent-framework/tree/main/python/samples/02-agents/harness/build_your_own_claw)
## Sandbox-escape progression: investigate every exit channel

Containment failures are incidents even when no HTTP request succeeds.
`boundary_denial` records HTTPS, DNS, metadata-service, local-daemon, and exec
attempts in the tamper-evident audit chain. A break-glass event is invalid
without an incident ID.

The KARS advantage is that runtime denial, Controller state, Router decisions,
budgets, and recovery can be correlated at the platform layer instead of
reconstructing incompatible logs from every Agent framework.

Run `make unit` for deterministic channel and audit tests, then `make test` for
the live exec-admission and direct-egress boundaries. Operations must not
describe “the network was blocked” without identifying which channel was
attempted and which layer denied it.
