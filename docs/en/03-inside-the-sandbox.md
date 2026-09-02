# 3. Development: Protect the Customer Repository

> **Delivery stage:** Development environment
> **New problem:** How can Forge execute customer code without seeing unrelated
> source, developer credentials, or an unrestricted network?
> **Deliverable:** A tested Sandbox boundary and disposable workspace design.
> **Working lab:** [`code/02`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/02)

## The question behind the word

ByteCraft's design partner is willing to provide a small private repository,
but only after the team explains where the code will live and who can access
it. After the local lab, Maya says, "Forge runs in a sandbox now."

Lina asks a deceptively simple question:

> What exactly is the sandbox protecting, and what is it not protecting?

A sandbox is not a magic label. For Forge, it must protect private source code,
separate the Agent from credentials, restrict network destinations, and leave
enough evidence to explain a failed or malicious action. If the team cannot
name those boundaries, it cannot test them.

This chapter pauses the feature work and opens the sandbox layer by layer.

## `karsSandbox` is the unit of work

In kars, one `karsSandbox` represents one Agent workload. It connects:

- a runtime such as OpenClaw, Hermes, an adapter, or BYO;
- a required `InferencePolicy`;
- sandbox isolation and security settings;
- network policy and optional approvals;
- generated Kubernetes resources;
- reconciliation status and conditions.

The custom resource is the desired-state contract. The running pod is one
result of that contract. Editing the pod directly does not redefine the
sandbox; the controller may replace it during reconciliation.

For the Forge story, one sandbox means one bounded execution context for one
development role. It does **not** mean every developer, repository, and Agent
should share one long-lived workspace.

## Open the production-shaped pod

In local Kubernetes and AKS, the important pod shape is:

```text
karsSandbox: forge
└── Pod
    ├── init: egress-guard  UID 0, NET_ADMIN during initialization
    ├── openclaw           UID 1000
    └── inference-router  UID 1001
```

### Agent container technical anatomy

The `openclaw` container is intentionally treated as the least-trusted
container in the Pod. The KARS Controller derives it from the
`KarsSandbox.spec.runtime` and `spec.sandbox` contract rather than asking the
application to hard-code its own security settings.

| Kubernetes/runtime detail | Forge configuration | Result inside the Agent container |
| --- | --- | --- |
| `runAsNonRoot` / runtime UID | `true` / UID `1000` | The Agent cannot depend on root ownership |
| `readOnlyRootFilesystem` | `true` | Image layers, binaries, and system configuration are not writable |
| `allowPrivilegeEscalation` | `false` | Setuid or process transitions cannot add privilege |
| Linux capabilities | Drop `ALL` | No ambient network, mount, or process-management capability |
| Writable paths | `/sandbox`, `/tmp` | State and caches have explicit disposal boundaries |
| Volumes | No `hostPath` or Docker socket | The Agent cannot reach the developer home or container daemon |
| Service account | `automountServiceAccountToken: false` | No implicit Kubernetes API bearer token appears in the filesystem |
| Provider environment | No GitHub/Copilot token reference | Prompt-injected code cannot read the model credential from `env` |
| Repository access | No checkout mounted in this Pod | Reads and writes cross the Router to the bounded workspace MCP service |
| Network namespace | Shared with Router; UID-aware egress controls | Loopback is available, independent external egress is not |
| Operator access | Exec Admission Policy | Normal `pods/exec` and attach paths into the Agent runtime are denied |

The container still has meaningful capability: it can run OpenClaw, keep
conversation state in approved writable paths, call `127.0.0.1:8443`, and ask
for governed tools. Sandboxing does not mean an empty process. It means every
side effect beyond that runtime envelope crosses a separately enforced
boundary.

### What kars provides and what the platform still owns

KARS provides the runtime adapter, Controller reconciliation, Router sidecar,
UID separation, sandbox security context, Egress Guard integration,
NetworkPolicy intent, policy references, Conditions, and exec admission
boundary. The platform team still owns the correctness of images, MCP
implementations, Secret selection, allowed endpoints, writable data, and any
external system that consumes Agent-produced artifacts.

This division is the practical advantage for ByteCraft: security controls are
not reimplemented inside OpenClaw, but KARS also does not pretend that an unsafe
tool server or incorrectly mounted Secret becomes safe merely because it runs
next to a Router.

### `egress-guard`

The init container installs network rules so the Agent UID can reach the router
on loopback but cannot establish an independent external path. It is a safety
net, not the policy decision point.

### `agent`

Forge and its OpenClaw runtime execute as UID 1000. In the
[`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01)
implementation, OpenClaw does not mount the repository directly. It calls the
local router, which mediates access to the separate workspace MCP service.
OpenClaw owns neither provider credentials nor direct egress.

### `inference-router`

The Rust router executes as UID 1001. Its model-facing HTTP endpoint uses port
`8443`; its forward-proxy path uses port `8444`. It evaluates policy, budget,
identity, egress, governance, and audit behavior.

The UID split matters: code interpreted or executed by Forge does not run as the
same operating-system user as the router holding external authority.

## Five boundaries around one code change

Maya assigns Forge a workspace containing issue #482. The team follows the
task through five boundaries.

### 1. Process boundary

Forge runs as a non-root Agent process. The router runs under a different UID.
A command executed by the development Agent should not be able to inspect the
router's process environment or credential material.

This is stronger in local Kubernetes and AKS than in single-container Docker
development, where Agent and router are co-located and UID/network separation
is not production-equivalent.

### 2. Filesystem boundary

The Agent receives only the runtime files required for the task. A good
development sandbox uses an ephemeral checkout or worktree at a pinned
revision and does not mount a developer's home directory, SSH directory,
global Git credential store, or unrelated repositories.

Forge applies a stronger split. The hardened `forge-workspace-mcp` Pod owns the
fixed-revision repository in a size-limited `emptyDir`; the OpenClaw Pod has no
repository or `hostPath` mount. The MCP Deployment also disables automatic
service-account token mounting and exposes only seven bounded tools.

kars defines the runtime sandbox, but the platform team still owns careful
volume and secret design. A NetworkPolicy cannot protect a Secret that was
mounted directly into the Agent container.

### 3. Network boundary

The Agent sends controlled requests to `127.0.0.1:8443` or the documented proxy
path. The egress guard and Kubernetes NetworkPolicy prevent an independent
route; the router makes the actual policy decision.

This distinction is important:

- Network controls answer, "Can this packet leave by another path?"
- Router policy answers, "Is this model, tool, host, or action allowed?"

Defense in depth requires both.

### 4. Identity boundary

In production, the router uses Workload Identity or a per-sandbox Entra Agent
ID, depending on deployment mode. Forge does not receive the resulting Azure
credential.

Local Kubernetes reproduces the pod and network shape but uses a static
provider credential for development. It is production-shaped infrastructure,
not production identity.

### 5. Lifecycle and evidence boundary

The controller observes the `karsSandbox`, creates or updates resources, and
reports conditions. The router records request-time decisions. When the task
ends, the workspace can be discarded while audit evidence is exported
independently.

Ephemeral execution reduces persistence risk, but deleting a pod before
exporting evidence can also destroy useful incident context.

## Inspect the sandbox rather than assuming

Start with the Forge deployment from Chapter 2, then use the executable lab:

```bash
cd code/02
make inspect
```

The script discovers the generated namespace and Pod from
`KarsSandbox/forge`; it does not hard-code a Pod name. It exports:

- the Sandbox desired state and Conditions;
- the Pod specification and a compact UID/mount summary;
- NetworkPolicy;
- the workspace MCP Deployment;
- the kars exec Admission Policy;
- recent controller and router logs.

The output is written to `.evidence/<UTC timestamp>/` outside Kubernetes, so it
survives Pod reconciliation and workspace cleanup.

Normal operators also cannot assume interactive shell access:

```bash
kubectl -n kars-forge exec <forge-pod> -c openclaw -- id
```

kars rejects this request through `kars-sandbox-exec-ban`. The complete lab can
temporarily enable the audited namespace break-glass label, run narrowly scoped
read-only probes, and remove the label through a shell trap.

## Test the boundaries with Forge

The fixture repository from [`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01) is intentionally disposable. Never use a
production checkout for these experiments.

| Test | Expected result |
| --- | --- |
| Inspect Forge and its assigned workspace | Allowed through kars resources and bounded MCP tools |
| Read a developer home-directory Secret | No host filesystem or home directory is mounted |
| Call the model through the router | Allowed under inference policy |
| Reach an unknown host directly from OpenClaw | Times out with HTTP `000` |
| Write to `/etc` from OpenClaw | Denied by the read-only root filesystem |
| Find a Copilot credential in OpenClaw | No provider credential variable is present |
| Use ordinary `kubectl exec` on OpenClaw | Denied by kars Admission Policy |
| Restart the Agent | Controller returns workload to desired state |
| Reference a missing inference policy | `Degraded/InferencePolicyNotFound` |

Run the non-disruptive checks:

```bash
make test
```

Run the complete experiment, including short-lived break-glass probes and a
Forge Pod replacement:

```bash
make test-full
```

The verified macOS arm64 run showed OpenClaw UID 1000, router UID 1001, denied
root-filesystem writes, no provider credential in OpenClaw, blocked direct
HTTPS, HTTP 200 through `127.0.0.1:8443`, a missing-policy Degraded condition,
and successful controller replacement of the deleted Forge Pod.

Before running, the lab enforces the Microsoft package sources used by
[`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01):

```text
https://packagefeedproxy.microsoft.io/npm/
https://packagefeedproxy.microsoft.io/pypi/simple/
https://packagefeedproxy.microsoft.io/nuget/v3/index.json
```

## Choose the right isolation level

kars uses secure sandbox defaults, including enhanced isolation, a strict
seccomp profile, and default-deny networking. AKS can optionally use
Kata/AMD SEV-SNP-backed confidential isolation for stronger workload
separation.

Confidential isolation may be appropriate when Forge handles unreleased source
or high-value build inputs. It does not replace least-privilege identity,
signed images, tool policy, egress policy, or code review.

## What the sandbox does not promise

The team adds these limitations to its threat model:

- It does not prove a generated patch is correct.
- It does not make untrusted code safe to merge.
- It cannot protect a credential mounted into the Agent by mistake.
- It does not turn Docker development mode into a production boundary.
- It does not replace tenant-level RBAC, quotas, image policy, or audit export.
- It cannot compensate for a policy that deliberately allows arbitrary shell
  and unrestricted egress.

The sandbox bounds authority. Tests, evaluation, review, and deployment policy
still decide whether a change is acceptable.

## Sandbox design record for Forge

Before continuing, the team records:

```text
Workload: one Forge Builder task
Source: fixed-revision checkout in the workspace MCP Pod's emptyDir
Agent user: UID 1000
Router user: UID 1001
External path: router only
Credentials in Agent: none
OpenClaw writable scope: /sandbox and /tmp
Repository writes: bounded workspace MCP tools only
Lifecycle owner: kars controller
Evidence destination: code/02/.evidence, then an external audit store
Cleanup: export evidence before Pod or workspace removal
```

The next chapter turns this understood runtime boundary into a reviewable
Kubernetes contract.

## Definition of done

The development environment is ready when the disposable fixed-revision
checkout is isolated in the workspace MCP Pod, OpenClaw has no repository mount
or reusable Git/model credential, direct unknown egress fails, UID separation
and exec restrictions are visible, controller reconciliation is proven, and
exported evidence survives workspace cleanup.

## Official references

- [Architecture and deployment modes](https://github.com/Azure/kars/blob/main/docs/architecture.md)
- [karsSandbox CRD reference](https://github.com/Azure/kars/blob/main/docs/api/crd-reference.md#karssandbox--the-agent)
- [Runtime contract](https://github.com/Azure/kars/blob/main/docs/runtimes.md)
- [Security model](https://github.com/Azure/kars/blob/main/docs/security.md)
## Sandbox-escape checkpoint: remove ambient authority

The first containment checkpoint is structural. Forge may write only to
`/sandbox` and `/tmp`; it receives no host mount, Docker socket, provider
credential, or ambient Kubernetes service-account token. Normal exec into the
Agent runtime is denied, while break-glass is explicit and audited.

Run the corresponding checks in [`code/02`](../../code/02):

```bash
make test
```

This stage does not assume every prompt injection will be recognized. It
removes the process-level primitives needed to turn a bad decision into host or
cluster control.
