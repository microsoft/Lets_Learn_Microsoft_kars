# 4. Platform: Turn Forge into a Kubernetes API Contract

> **Delivery stage:** Shared development platform
> **New problem:** How can every engineer and CI job reproduce and review the
> same Forge environment?
> **Deliverable:** Versioned `KarsSandbox` and `InferencePolicy` contracts with
> executable lifecycle evidence.
> **Working lab:** [`code/03`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/03)

## Replace terminal memory with desired state

[`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01)
proved that OpenClaw could complete a bounded Issue-to-Patch workflow.
[`code/02`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/02)
opened the generated Pod and tested the isolation boundary.
Neither result should depend on remembering which commands Maya typed.

The shared platform needs a reviewable API contract:

- Git stores the intended workload and authority.
- Kubernetes validates the object shape.
- kars reconciles the requested state.
- `status.conditions` explains whether the request succeeded.
- `metadata.generation` and `status.observedGeneration` show whether the
  controller has processed the latest change.

The [`code/03`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/03)
lab exercises this complete lifecycle against the running
`kars-dev` cluster.

## Use the exact kars API identity

Kubernetes API names are case-sensitive. The installed CRD is:

```text
apiVersion: kars.azure.com/v1alpha1
kind: KarsSandbox
```

The earlier spelling `karsSandbox` is not an alias. Server-side validation
returns `no matches for kind` when the Kind casing is wrong.

Inspect the live schema instead of assuming a field exists:

```bash
kubectl explain karssandbox.spec --recursive
kubectl explain inferencepolicy.spec --recursive
kubectl get crd karssandboxes.kars.azure.com -o yaml
```

The experiment saves all three outputs outside the cluster as evidence.

## Separate workload from inference authority

The smallest deployable kars agent is:

1. A sibling `InferencePolicy`.
2. A `KarsSandbox` whose required `spec.inferenceRef.name` points to that
   policy.

There is no unrestricted inline inference fallback. The reference is local to
the Sandbox namespace.

[`code/03/manifests/contract-v1.yaml`](https://github.com/kinfey/LetsLearnMicrosoftKars/blob/main/code/03/manifests/contract-v1.yaml)
contains the first contract:

```yaml
apiVersion: kars.azure.com/v1alpha1
kind: InferencePolicy
metadata:
  name: forge-contract-inference
  namespace: kars-system
spec:
  appliesTo:
    sandboxName: forge-contract
  modelPreference:
    primary:
      provider: azure-openai
      deployment: __MODEL__
  tokenBudget:
    perRequestTokens: 1024
    dailyTokens: 4096
---
apiVersion: kars.azure.com/v1alpha1
kind: KarsSandbox
metadata:
  name: forge-contract
  namespace: kars-system
spec:
  runtime:
    kind: OpenClaw
    openclaw:
      config:
        agent:
          model: azure/__MODEL__
  sandbox:
    isolation: enhanced
    seccompProfile: kars-strict
    readOnlyRootFilesystem: true
    runAsNonRoot: true
    allowPrivilegeEscalation: false
    writablePaths:
      - /sandbox
      - /tmp
  inferenceRef:
    name: forge-contract-inference
  networkPolicy:
    defaultDeny: true
    egressMode: Strict
    allowedEndpoints: []
```

`__MODEL__` is not committed as an account-specific value. The lab reads the
model from the live [`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01)
Forge Sandbox and renders manifests into
`code/03/.generated/`.

The dedicated `forge-contract` Sandbox keeps the API experiment separate from
the working `forge` Agent.

## Validate before persisting

Run:

```bash
cd code/03
make validate
```

The script uses the API server, not only a YAML parser:

```bash
kubectl apply \
  --server-side \
  --dry-run=server \
  --field-manager=code03-lab \
  -f .generated/contract-v1.yaml
```

The same experiment proves two negative cases:

| Invalid contract | API result |
| --- | --- |
| `kind: karsSandbox` | Rejected because Kind names are case-sensitive |
| `runtime.kind: UnsupportedRuntime` | Rejected by the installed CRD enum |

These failures happen before an object is persisted and before the controller
creates a workload.

## Apply with one field owner

The lab uses Server-side Apply:

```bash
kubectl apply \
  --server-side \
  --field-manager=code03-lab \
  -f .generated/contract-v1.yaml
```

Kubernetes records `code03-lab` in `metadata.managedFields`. This makes field
ownership visible and gives GitOps tools a clean path to detect conflicts.

The rule remains:

> One declarative field has one owner.

An emergency `kubectl patch` may be necessary, but the reviewed manifest must
subsequently restore the intended state. The lab demonstrates this by
temporarily breaking `inferenceRef` and then reapplying V2 with the original
field manager.

## Read status as the controller's answer

After V1 is applied, the experiment waits for all of these facts:

```text
status.phase == Running
metadata.generation == status.observedGeneration
status.conditions[type=Ready].status == True
```

The verified run produced:

```text
generation=1 observedGeneration=1 phase=Running
```

It also confirmed that kars attached:

```text
kars.azure.com/namespace-cleanup
```

as a finalizer and generated:

```text
Namespace/kars-forge-contract
Deployment/forge-contract
```

The owner resource is the source of truth. Operators inspect its Conditions
before debugging the generated Deployment or Pod.

## Review a contract change with `kubectl diff`

V2 changes both the OpenClaw instructions and the inference budget:

```yaml
tokenBudget:
  perRequestTokens: 2048
  dailyTokens: 8192
```

Before applying it, the lab runs:

```bash
kubectl diff \
  --server-side \
  --field-manager=code03-lab \
  -f .generated/contract-v2.yaml
```

The diff exits with status 1 because a reviewed change is pending. After
Server-side Apply, the verified state becomes:

```text
generation=2 observedGeneration=2 phase=Running
```

This is stronger evidence than seeing a new Pod: it proves the owner resource
changed and the controller observed that exact generation.

## Test dependency failures and recovery

### Missing sibling policy

The lab temporarily changes:

```yaml
inferenceRef:
  name: intentionally-missing-policy
```

The Sandbox reports:

```text
phase: Degraded
reason: InferencePolicyNotFound
```

Reapplying the reviewed V2 manifest restores `forge-contract-inference`, and
the Sandbox returns to `Running`.

### Policy in another namespace

[`code/03/manifests/cross-namespace.yaml`](https://github.com/kinfey/LetsLearnMicrosoftKars/blob/main/code/03/manifests/cross-namespace.yaml)
creates an `InferencePolicy` in
`code03-policy-other` while the Sandbox remains in `kars-system`.

The policy name exists, but the reference is unresolved because
`inferenceRef` is namespace-local. The Condition explicitly says
cross-namespace references are unsupported. No `kars-forge-cross-namespace`
workload namespace or Pod is created.

### Invalid provider deployment

Provider deployment names are opaque strings to the Kubernetes API. Therefore
`intentionally-invalid-model` passes CRD validation, and the Sandbox can reach
`Running`.

Validity is checked when inference is requested. The verified router request
returned:

```text
HTTP 400
```

This distinction prevents a misleading debugging assumption:

- schema and reconciliation prove the contract is structurally deployable;
- only a live inference request proves the configured provider deployment is
  usable.

## Run the complete contract lab

```bash
cd code/03
make test
```

The command performs:

1. Microsoft package-source enforcement.
2. Model-aware manifest rendering.
3. Server-side schema validation.
4. V1 Server-side Apply and readiness checks.
5. Managed-field, finalizer, namespace, and Deployment inspection.
6. Idempotence and V1-to-V2 diff checks.
7. V2 generation and budget reconciliation.
8. Missing-policy failure and recovery.
9. Cross-namespace reference failure.
10. Invalid provider request testing.
11. Finalizer-driven cleanup.

Evidence is stored in:

```text
code/03/.evidence/<UTC timestamp>/
```

The directory contains the CRD schema, owner resources, generated Deployment,
diffs, Conditions, request status, events, and the complete transcript. It is
outside Kubernetes and excluded from Git.

## Enforce Microsoft package sources

Before the experiment runs, it applies and verifies:

```text
https://packagefeedproxy.microsoft.io/npm/
https://packagefeedproxy.microsoft.io/pypi/simple/
https://packagefeedproxy.microsoft.io/nuget/v3/index.json
```

The upstream kars and OpenClaw source files are restored on exit.

## Add resources only for requirements

The installed kars API exposes these relevant resource kinds:

| Requirement | Resource Kind |
| --- | --- |
| Run an Agent workload | `KarsSandbox` |
| Select and budget inference | `InferencePolicy` |
| Govern tools | `ToolPolicy` |
| Register an MCP service | `McpServer` |
| Persist approved memory | `KarsMemory` |
| Run evaluations | `KarsEval` |
| Describe trusted peers | `TrustGraph` |
| Temporarily approve egress | `EgressApproval` |
| Govern an SRE action | `KarsSREAction` |
| Expose an A2A endpoint | `A2AAgent` |

Do not create every CRD for completeness. Each object must answer a real
product or operational requirement and must be checked against the maturity of
the installed kars revision.

## Definition of done

The platform contract is ready when Server-side validation rejects malformed
objects, one field manager owns the reviewed fields, `kubectl diff` exposes
authority changes, the controller reports the current generation, dependency
failures produce actionable Conditions, live inference validates provider
configuration, finalizers clean generated resources, and CI can repeat the
same experiment without relying on a developer's shell history.

## Official references

- [kars CRD reference](https://github.com/Azure/kars/blob/main/docs/api/crd-reference.md)
- [kars basic agent example](https://github.com/Azure/kars/tree/main/examples/basic-agent)
- [kars architecture](https://github.com/Azure/kars/blob/main/docs/architecture.md)
- [kars source repository](https://github.com/Azure/kars)
## Sandbox-escape checkpoint: authority is an owned API field

The next checkpoint prevents the workload from rewriting its own authority.
`code/03` uses Server-side Apply ownership and demonstrates that an
`agent-self-modification` manager cannot replace the reviewed `inferenceRef`.
Generation, `observedGeneration`, finalizers, and Conditions then show whether
the reviewed contract was reconciled.

KARS adds value here by making authority declarative and observable. A generic
Agent container may have configuration files, but it does not by itself
provide a Controller that restores reviewed state and reports why the workload
is `Running` or `Degraded`.

```bash
cd code/03
make test
```

Model selection, policy references, budgets, and runtime settings are platform
API state, not files the Agent may edit.
