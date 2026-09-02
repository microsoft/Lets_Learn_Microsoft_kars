# kars AKS and multi-agent promotion lab

[English](README.md) | [简体中文](README.zh.md)

This lab starts from the OpenClaw Forge contract in
[`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01),
the GPT-5.6-Sol BYO runtime in
[`code/05`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/05),
and the security/recovery evidence in
[`code/06`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/06).
It prepares a reviewed AKS promotion without
allowing one Agent to build and approve the same change:

```text
OpenClaw Intake
    -> approved FORMAT-482 contract
    -> Forge Builder (patch + targeted tests)
    -> digest-pinned handoff envelope
    -> Forge Reviewer (read evidence + approve/reject)
    -> human-reviewed GitOps promotion
    -> kars on AKS
```

The default run is intentionally **plan-only**. It executes kars
`up --dry-run`, validates the GitOps resources against the live local kars
CRDs, and creates no Azure resources. Real AKS deployment is an explicit
opt-in because it creates billable infrastructure.

## Default and optional Azure parameters

| Variable | Value | Meaning |
| --- | --- | --- |
| `AZURE_RESOURCE_GROUP` | required | Your Azure resource group |
| `AKS_NAME` | required | Your AKS cluster name |
| `KARS_ACR_NAME` | required | Your globally unique ACR name |
| `LOG_ANALYTICS_WORKSPACE` | required | Your Log Analytics workspace |
| `AZURE_LOCATION` | existing resource-group location, otherwise `eastus2` | Azure region |
| `KARS_SANDBOX_NAME` | `forge-intake` | Initial OpenClaw sandbox created by `kars up` |
| `KARS_RELEASE` | `v0.1.25` | Pinned kars release |
| `KARS_ISOLATION` | `enhanced` | kars isolation level |
| `KARS_MESH_TRUST` | `anonymous` | Initial mesh trust mode |
| `GITHUB_COPILOT_MODEL` | `gpt-5.6-sol` | Required model |
| `DEPLOY_AKS` | `false` | Real Azure creation switch |
| `FORGE_IMAGE` | local development image | Plan-only image placeholder; real deployment builds and pins it in ACR |

To supply Azure values without committing them:

```bash
cp config/aks.env.example config/aks.env
```

`config/aks.env` is ignored by Git.

## What the plan-only lab proves

- [`code/05`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/05)
  remains `Running` with its original 1024-token policy.
- The [`code/06`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/06)
  BYO exec admission guard is installed.
- Microsoft Package Feed Proxy is used for npm, PyPI, and NuGet.
- The host-side Microsoft Agent Framework `GitHubCopilotAgent` performs a real
  GPT-5.6-Sol tool call before promotion.
- The handoff contract pins patch and test-evidence SHA-256 digests.
- Builder can propose a patch but cannot approve a release.
- Reviewer can read/decide on Builder evidence but cannot modify source or
  approve its own artifact.
- Builder and Reviewer have separate `KarsSandbox`, `InferencePolicy`, and
  `ToolPolicy` resources.
- Reviewer has the smaller inference budget.
- Both roles retain the BYO v1 contract, strict egress, enhanced isolation,
  read-only root filesystems, and GPT-5.6-Sol.
- The live kars API server accepts all six rendered resources using
  `kubectl apply --dry-run=server`.
- kars `0.1.25` completes `kars up --dry-run` for the selected Azure target.
- Real deployment is denied unless it is explicitly enabled and an upstream
  kars source checkout is available.
- A promotion record links the source Git commit,
  [`code/05`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/05)
  image digest,
  [`code/06`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/06)
  loaded policy digest, and target AKS parameters.

## Run without creating Azure resources

```bash
cd code/07
make test
```

The completed default run resolved:

```text
Resource group: <your-resource-group>
AKS cluster:    <your-aks-cluster>
Location:       <your-azure-region>
Model:          gpt-5.6-sol
kars release:   v0.1.25
Azure created:  no
```

Successful output ends with:

```text
All plan-only AKS and multi-agent checks passed.
No Azure resources were created.
Evidence: .../code/07/.evidence/<UTC timestamp>
```

Focused commands:

```bash
make unit
make plan
make validate
```

## GitOps authority split

The rendered file is `rendered/multi-agent.yaml`.

| Control | Builder | Reviewer |
| --- | --- | --- |
| Sandbox | `forge-builder` | `forge-reviewer` |
| Per-request budget | 2048 | 512 |
| Daily budget | 8192 | 2048 |
| Patch source | Allowed through named workspace actions | Not present |
| Review decision | Not present | Named review action |
| Approval mode | `never` at the tool gate | `always` |
| Trust threshold | 700 | 800 |

Passing a handoff envelope does not transfer the Builder's workspace,
credential, or tool authority to the Reviewer.

## AKS Day-0 and Day-1 decisions

The plan delegates infrastructure creation to the current kars `up` workflow,
which reports AKS, ACR, Key Vault, model infrastructure, Azure Monitor,
Workload Identity, firewall configuration, Helm, and the initial sandbox.

Review these before real deployment:

- **Day 0:** Azure location, address space/network architecture, API exposure,
  isolation level, node/region quota, and identity topology.
- **Day 1:** GitOps reconciliation, external audit export, monitoring,
  maintenance windows, policy rollout, rollback, and the
  [`code/06`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/06)
  recovery
  procedure.

Use Azure CNI Overlay/Cilium and Workload Identity for production unless the
environment has a documented reason to choose another Day-0 design. Verify the
actual kars-provisioned cluster rather than assuming a CLI plan proves every
network setting.

## Real Azure deployment

Review `.evidence/<run>/aks-plan.json`, the rendered manifests, quota, and
cost. The real deployment uses Azure CLI instead of non-dry-run `kars up`
because kars `0.1.25` would append `-aks` to the requested cluster name.

```bash
cp config/aks.env.example config/aks.env
# Edit config/aks.env:
# DEPLOY_AKS=true

make deploy
```

`make deploy` creates the cluster named by `AKS_NAME`, plus the configured ACR
and Log Analytics workspace; imports kars `v0.1.25`; builds the BYO image through ACR Tasks with
`--platform linux/amd64`; pins the image by digest; installs kars and AGT; and
applies the reviewed Builder/Reviewer resources. It refuses to deploy unless
`DEPLOY_AKS` is exactly `true`.

No subscription ID is stored in the repository or evidence.

### Verified Azure result

- The configured AKS cluster is `Succeeded` in the configured Azure location.
- The `system` pool uses one `Standard_D2as_v5` node and `clawpool` uses one
  `Standard_D4as_v5` node; both report `amd64`.
- Azure CNI Overlay, Cilium, OIDC issuer, and Workload Identity are enabled.
- kars Controller, AGT Registry/Relay, OpenClaw Intake, Builder, and Reviewer
  are Running.
- The Builder and Reviewer use the same digest-pinned Linux amd64 image.
- A real Router call returned `KARS_BYO_GPT_5_6_SOL_OK` from
  `gpt-5.6-sol`; Router audit integrity, credential isolation, and exec denial
  also passed.

## Mesh and A2A scope

The installed kars CLI exposes `mesh`, `pair`, and `a2a` commands, and current
upstream kars documents cluster federation and A2A ingress. This lab uses
`registryMode: local` and a deterministic reviewed handoff envelope. It does
not claim that cross-cluster pairing, public A2A ingress, Entra mesh trust, or
encrypted relay delivery was exercised.

Enable those only after separate trust, expiry, replay, ingress, dual-policy,
and audit tests. Connectivity alone is not authorization.

## Evidence

Each run writes:

```text
.evidence/<UTC timestamp>/
├── transcript.log
├── host-copilot-agent.json
├── gitops-server-dry-run.txt
├── aks-plan.json
├── kars-up-command.txt
├── kars-up-dry-run.txt
├── deploy-opt-in-denial.txt
├── deploy-source-denial.txt
├── azure-gpt-response.json
├── azure-audit-verify.json
└── azure-release-record.json
```

The promotion record does not contain Azure subscription IDs, credentials, or
Secret values.

## Platform support

The completed run was validated on macOS arm64. The inherited scripts support
macOS amd64 and Linux amd64. On Windows amd64, run inside Ubuntu WSL2 with
Docker Desktop WSL integration and Azure CLI, kubectl, Helm, Node.js 22, and
the kars CLI installed inside WSL2.

## References

- [Azure/kars getting started](https://github.com/Azure/kars/blob/main/docs/getting-started.md)
- [Azure/kars enterprise self-hosted blueprint](https://github.com/Azure/kars/blob/main/docs/blueprints/03-enterprise-self-hosted.md)
- [Azure/kars cross-org federation blueprint](https://github.com/Azure/kars/blob/main/docs/blueprints/05-cross-org-federation.md)
- [Azure/kars CRD reference](https://github.com/Azure/kars/blob/main/docs/api/crd-reference.md)
- [Microsoft Agent Framework GitHub Copilot samples](https://github.com/microsoft/agent-framework/tree/main/python/samples/02-agents/providers/github_copilot)
- [Microsoft Agent Framework Build Your Own Claw](https://github.com/microsoft/agent-framework/tree/main/python/samples/02-agents/harness/build_your_own_claw)
- [Azure CNI Overlay](https://learn.microsoft.com/azure/aks/azure-cni-overlay)
## Sandbox-escape progression: review the artifact, not the workspace

The Builder-to-Reviewer handoff now carries an
`artifact_manifest_digest` in addition to patch and test-evidence digests.
Review authorization fails when any of the three is unpinned. GitOps validation
also requires default-deny egress, no arbitrary endpoint, exactly the
disposable writable paths, and no shell, exec, Docker, or settings capability
in either role.

The KARS advantage is that the Builder and Reviewer receive separate
Controller-managed sandboxes and policies. Separation of duties is enforced by
platform resources, not by asking one multi-role Agent to remember which hat it
is wearing.

Run `make unit` and `make validate`. The Reviewer receives a digest-pinned
envelope, never the Builder's mutable workspace, preventing a trust-handoff
artifact from gaining authority during promotion.
