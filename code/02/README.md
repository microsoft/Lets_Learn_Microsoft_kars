# Forge sandbox boundary lab

[English](README.md) | [简体中文](README.zh.md)

This lab turns Chapter 3's sandbox claims into executable checks against the
Forge deployment from [`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01). Its design follows the
[Azure/kars security model](https://github.com/Azure/kars/blob/main/docs/security.md)
and [runtime contract](https://github.com/Azure/kars/blob/main/docs/runtimes.md).

## What this lab proves

| Boundary | Executable evidence |
|----------|---------------------|
| Desired state | `KarsSandbox/forge` is `Running`; a deleted Pod is reconciled |
| Process | OpenClaw runs as UID 1000 and the inference router as UID 1001 |
| Operator access | normal `kubectl exec` into OpenClaw is denied by kars admission policy |
| Filesystem | OpenClaw has a read-only root filesystem and no hostPath; the repository lives in the MCP Pod's disposable `emptyDir` |
| Identity | OpenClaw has no GitHub/Copilot provider credential reference; the router owns it |
| Network | direct Agent HTTPS fails while `127.0.0.1:8443` inference succeeds |
| Policy reconciliation | a missing `InferencePolicy` produces `Degraded/InferencePolicyNotFound` |
| Evidence lifecycle | YAML, JSON, and logs are copied to `.evidence/` outside the sandbox |

The live deployment reveals an important refinement to the chapter: Forge does
not mount the repository directly. The hardened `forge-workspace-mcp` Pod owns
the fixed-revision disposable workspace and exposes only seven narrow tools.

## KARS advantage and Agent container details

KARS turns the security requirements into generated and continuously
reconciled Pod state instead of conventions inside OpenClaw:

| Agent container detail | Executable check |
| --- | --- |
| UID `1000`, Router UID `1001` | Pod `securityContext` inspection |
| Read-only root, no privilege escalation, capabilities dropped | `scripts/test-static.sh` |
| Writable paths exactly `/sandbox` and `/tmp` | `KarsSandbox.spec.sandbox` assertion |
| No `hostPath`, Docker socket, or automatic service-account token | Pod volume and identity assertions |
| No provider credential reference | Agent and Router environment-name comparison |
| Default-deny egress with loopback Router access | Sandbox and generated NetworkPolicy evidence |
| Normal exec denied | `kars-sandbox-exec-ban` probe |

The Agent container is allowed to reason and call loopback services; it is not
allowed to own the credential or external route used to fulfill those calls.
That separation is the concrete KARS advantage over placing OpenClaw, its key,
its tools, and unrestricted networking in one application container.

## Prerequisites

1. Deploy and validate [`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01).
2. Keep the `kars-dev` kind cluster running.
3. Install `kubectl`, `jq`, `curl`, Docker, and Node.js 22.

All package restore configuration comes from
[`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01)
and is verified before
the lab runs:

- npm: `https://packagefeedproxy.microsoft.io/npm/`
- PyPI: `https://packagefeedproxy.microsoft.io/pypi/simple/`
- NuGet: `https://packagefeedproxy.microsoft.io/nuget/v3/index.json`

## Run

The non-disruptive checks inspect resources, verify the exec denial, and test a
temporary missing-policy sandbox:

```bash
cd code/02
make test
```

Run the complete lab, including an audited short-lived break-glass probe and a
Forge Pod restart:

```bash
make test-full
```

`test-full` temporarily labels namespace `kars-forge` with
`kars.azure.com/break-glass=true`, probes only UID, filesystem writability,
credential variable names, direct HTTPS, and the loopback router, then removes
the label through a shell trap. It never prints credential values.

The Pod restart deletes only the current Forge Pod. The kars-managed Deployment
creates a replacement and the script verifies a new Pod UID and a `Running`
Sandbox phase.

## Evidence

Each run writes a timestamped directory:

```text
.evidence/<UTC timestamp>/
├── README.md
├── transcript.log
├── forge-sandbox.yaml
├── forge-pod.json
├── pod-summary.json
├── network-policies.yaml
├── workspace-deployment.yaml
├── exec-admission-policy.yaml
├── controller.log
├── router.log
├── missing-policy-sandbox.json
└── reconciliation.json
```

This directory is intentionally outside Kubernetes and ignored by Git. It
survives Pod and workspace cleanup without committing cluster-specific logs.

## Individual experiments

```bash
make inspect
make degraded
make reconcile
make clean
```

`make reconcile` requires the explicit restart opt-in already set by the
Makefile target. `make clean` removes temporary cluster state but preserves
local evidence.

## Platform notes

The validated environment is macOS arm64. The same scripts use the platform
detection from
[`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01)
and support macOS amd64, Linux amd64, and Windows
amd64 through Ubuntu WSL2. Run Windows commands inside WSL2, not native
PowerShell or CMD.
## Sandbox-escape progression: contain the process

`code/01` proved that hostile repository text cannot obtain a useful tool. This
stage moves one layer down and proves that the resulting process also lacks an
escape primitive. `make test` now verifies that writable paths remain limited
to `/sandbox` and `/tmp`, no host filesystem or container-daemon socket is
mounted, no ambient Kubernetes service-account token exists, and normal
`kubectl exec` is denied. `make test-full` is the only path that enables the
audited break-glass probes.

This blocks the infrastructure prerequisites commonly used by path, Docker
socket, and runtime-control sandbox escapes. Path canonicalization itself is
tested in `code/01`; this stage proves the Pod cannot turn a missed application
check into host or cluster authority.
