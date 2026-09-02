# kars Kubernetes API contract lab

[English](README.md) | [简体中文](README.zh.md)

This lab turns Chapter 4 into an executable Kubernetes API lifecycle using the
Forge environment from [`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01)
and the evidence practices from
[`code/02`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/02).
It follows the upstream
[kars CRD reference](https://github.com/Azure/kars/blob/main/docs/api/crd-reference.md),
[basic agent example](https://github.com/Azure/kars/tree/main/examples/basic-agent),
and [architecture](https://github.com/Azure/kars/blob/main/docs/architecture.md).

## What it demonstrates

| API behavior | Experiment |
|--------------|------------|
| Exact API identity | `KarsSandbox` succeeds; incorrectly cased `karsSandbox` is rejected |
| CRD schema | an unsupported runtime is rejected by server-side validation |
| Required sibling reference | `spec.inferenceRef.name` resolves only in the Sandbox namespace |
| Server-side apply | field manager `code03-lab` is recorded in `managedFields` |
| Desired versus observed state | `status.observedGeneration` must catch up with `metadata.generation` |
| Generated resources | the Controller creates namespace `kars-forge-contract` and its Deployment |
| Reviewable change | `kubectl diff` exposes the V1-to-V2 instruction and token-budget changes |
| Actionable failure | a missing policy produces `Degraded/InferencePolicyNotFound` |
| Recovery | reapplying the reviewed V2 manifest returns the Sandbox to `Running` |
| Finalizer ownership | `kars.azure.com/namespace-cleanup` is attached to the owner resource |
| Provider validation boundary | an opaque invalid deployment passes the Kubernetes API but fails at inference time |

The lab uses a dedicated `forge-contract` Sandbox and does not modify the
Chapter 2 `forge` Sandbox.

## Microsoft package sources

Before running any test, the lab applies and verifies the package-source
configuration from
[`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01):

- npm: `https://packagefeedproxy.microsoft.io/npm/`
- PyPI: `https://packagefeedproxy.microsoft.io/pypi/simple/`
- NuGet: `https://packagefeedproxy.microsoft.io/nuget/v3/index.json`

The upstream source files are restored when the lab exits.

## Run

Keep the validated
[`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01)
kind environment running, then execute:

```bash
cd code/03
make test
```

The command:

1. Reads the model selected by the live Forge contract.
2. Renders the V1, V2, and cross-namespace manifests into `.generated/`.
3. Runs server-side schema validation.
4. Applies V1 with field manager `code03-lab`.
5. Waits for `Running` and current `observedGeneration`.
6. Records generated resources, finalizers, and managed fields.
7. Diffs and applies V2.
8. Breaks and restores `inferenceRef`.
9. Proves cross-namespace references remain unresolved.
10. Proves an invalid provider deployment fails only when inference is called.
11. Deletes all temporary resources through kars finalizers.

## Evidence

Results are stored outside Kubernetes:

```text
.evidence/<UTC timestamp>/
├── transcript.log
├── karssandbox-schema.txt
├── inferencepolicy-schema.txt
├── karssandbox-crd.yaml
├── contract-v1-sandbox.json
├── contract-v1-policy.json
├── contract-v1-deployment.json
├── contract-v1.diff
├── contract-v1-to-v2.diff
├── contract-v2-sandbox.json
├── contract-v2-policy.json
├── contract-missing-policy.json
├── contract-recovered.json
├── cross-namespace-sandbox.json
├── invalid-runtime.txt
├── invalid-kind-case.txt
├── invalid-provider-sandbox.json
├── invalid-provider-request.txt
└── kars-system-events.txt
```

`.evidence/` and `.generated/` are ignored by Git.

## Individual commands

```bash
make render
make validate
make clean
```

Use `kubectl diff --server-side --field-manager=code03-lab` before applying
contract changes. A field should have one declarative owner; emergency patches
must be reconciled back to the reviewed manifest.

## Platform support

The validated environment is macOS arm64. Platform detection is inherited from
[`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01),
including macOS amd64, Linux amd64, and Windows amd64 through Ubuntu
WSL2.
## Sandbox-escape progression: authority cannot rewrite itself

After `code/02` removes ambient host and cluster access, this stage treats the
Kubernetes resource specification as an authority boundary. The lifecycle test
attempts to change `inferenceRef` with a separate
`agent-self-modification` Server-side Apply field manager. Kubernetes must
reject the change as a managed-field conflict before the reviewed manifest is
reconciled.

The KARS advantage here is that model, budget, runtime, and policy references
are Controller-reconciled API state with observable Conditions. They are not
mutable settings owned by the Agent framework.

Run `make test` and inspect
`.evidence/<run>/self-modified-authority.txt`. A workload becoming writable is
not sufficient to change its model, policy reference, budget, or controller
contract.
