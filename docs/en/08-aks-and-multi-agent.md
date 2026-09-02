# 8. AKS and Multi-Agent Promotion: Separate Build from Approval

> **Delivery stage:** Plan and review the AKS production promotion
> **Starting point:** OpenClaw Forge, the Chapter 6 GPT-5.6-Sol BYO runtime,
> and the Chapter 7 security/recovery evidence
> **Executable lab:** [`code/07`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/07)

## Everything still starts from OpenClaw

OpenClaw established the original FORMAT-482 issue-to-patch behavior. The
runtime changed in Chapter 6 and the operational controls became measurable in
Chapter 7, but the business contract did not change:

```text
OpenClaw Intake
    -> approved issue and acceptance criteria
    -> Forge Builder
    -> patch digest + test-evidence digest
    -> Forge Reviewer
    -> human-reviewed GitOps change
    -> kars on AKS
```

The multi-agent design is not two prompts chatting. It is separation of
identity, tools, budget, data, and approval authority.

## Run the safe default

```bash
cd code/07
make test
```

The default run creates no Azure resources. It:

1. confirms the [`code/05`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/05)
   BYO runtime and [`code/06`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/06)
   security guard;
2. verifies Microsoft npm, PyPI, and NuGet sources;
3. runs deterministic Builder/Reviewer authorization tests;
4. calls GPT-5.6-Sol through the host Microsoft Agent Framework
   `GitHubCopilotAgent`;
5. renders two independent kars Sandboxes and Policies;
6. validates them with the live kars API server using Server-side Dry-run;
7. executes the official kars `up --dry-run`;
8. proves that real deployment requires explicit opt-in and an upstream kars
   source checkout;
9. creates a promotion record linking source image and policy digests.

The completed macOS arm64 run passed every phase without creating Azure
resources.

## Interpret the requested Azure values correctly

The lab uses:

| Parameter | Value |
| --- | --- |
| Resource group | required: your Azure resource group |
| AKS cluster | required: your AKS cluster name |
| ACR | required: your globally unique ACR name |
| Log Analytics | required: your workspace name |
| Azure location | optional: existing resource-group location, otherwise `eastus2` |
| Model | `gpt-5.6-sol` |
| kars release | `v0.1.25` |
| Isolation | `enhanced` |

Copy [`code/07/config/aks.env.example`](https://github.com/kinfey/LetsLearnMicrosoftKars/blob/main/code/07/config/aks.env.example)
to the ignored `code/07/config/aks.env` file and fill in every required Azure value. The
tutorial intentionally does not publish or default to names from a real
deployment.

## Use plan-only as the deployment gate

The generated command was:

```bash
kars up \
  --name forge-intake \
  --model gpt-5.6-sol \
  --policy developer \
  --region "<your-azure-region>" \
  --cluster-name "${AKS_NAME}" \
  --resource-group "${AZURE_RESOURCE_GROUP}" \
  --isolation enhanced \
  --release v0.1.25 \
  --mesh-trust anonymous \
  --dry-run \
  --yes
```

kars reported that a real run would check Azure credentials, deploy AKS, ACR,
Key Vault, model infrastructure, Azure Monitor, and Workload Identity; configure
firewalls and ACR attachment; install the kars control plane; create a
federated credential; and wait for the initial Sandbox.

Dry-run proves command resolution and preflight. It does not prove quota,
capacity, model availability, network routing, or runtime health in the future
cluster.

## Separate Builder and Reviewer authority

[`code/07/operations/handoff.py`](https://github.com/kinfey/LetsLearnMicrosoftKars/blob/main/code/07/operations/handoff.py)
defines a digest-pinned handoff envelope. The
tests require:

- Builder may propose a patch but cannot approve release.
- Reviewer may review and approve a Builder artifact.
- Reviewer cannot modify source.
- Reviewer cannot approve an artifact produced by Reviewer.
- Wrong model or unpinned evidence is rejected.

The handoff contains references and digests, not a reusable credential or the
Builder's writable workspace.

## Render separate kars resources

The GitOps template produces:

| Resource | Builder | Reviewer |
| --- | --- | --- |
| `KarsSandbox` | `forge-builder` | `forge-reviewer` |
| `InferencePolicy` | `forge-builder-inference` | `forge-reviewer-inference` |
| `ToolPolicy` | `forge-builder-tools` | `forge-reviewer-tools` |
| Per-request tokens | 2048 | 512 |
| Daily tokens | 8192 | 2048 |
| Tool authority | read/search/patch/test/diff | read diff/evidence + submit decision |
| Approval mode | `never` | `always` |
| Trust threshold | 700 | 800 |

Both Sandboxes use:

- `runtime.kind: BYO`;
- `contractVersion: v1`;
- GPT-5.6-Sol;
- enhanced isolation;
- read-only root filesystem;
- strict, default-deny egress;
- local registry mode.

The live kars CRDs accepted all six resources in Server-side Dry-run. They were
not applied, so no extra local Agent Pods were created.

## Carry Chapter 7 evidence into promotion

The promotion record includes:

- the repository commit;
- kars version `0.1.25`;
- model `gpt-5.6-sol`;
- the running [`code/05`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/05)
  BYO image digest;
- the loaded [`code/06`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/06)
  policy digest;
- target resource group, cluster name, and location;
- `deployed: false`.

Promotion must start from known runtime and policy artifacts, not rebuild an
untraceable image during production approval.

## Review AKS Day-0 decisions

Before removing `--dry-run`, decide:

- Azure location and regional quota/capacity;
- VNet and address spaces;
- API-server access;
- Azure CNI Overlay versus directly routable Pod IPs;
- Cilium/network-policy requirements;
- egress through a static gateway, firewall, or NVA;
- Workload Identity and Key Vault integration;
- system/user node pools, zones, and VM sizes;
- confidential isolation requirements.

These are Day-0 decisions because some require cluster recreation. For a
production design, prefer Azure CNI Overlay with Cilium, Workload Identity,
multiple zones, and non-burstable VM families unless the environment has a
documented constraint.

kars owns the infrastructure workflow in this lab. Inspect the resulting AKS
configuration after deployment; do not infer every network property from a
successful CLI dry-run.

## Plan Day-1 operation

The AKS deployment is incomplete without:

- external Router audit export, because Chapter 7 proved local history resets
  with the Pod;
- Managed Prometheus, Container Insights, Grafana, and control-plane diagnostic
  logs;
- maintenance windows and staged upgrade/rollback;
- image signing and digest pinning;
- GitOps ownership of production fields;
- post-deployment allow and deny tests;
- Pod disruption budgets and topology spread for replicated services;
- policy rollout verification using compiled and loaded digests.

## Deploy only by explicit opt-in

Review the plan, rendered resources, quota, and cost:

```bash
cd code/07
cp config/aks.env.example config/aks.env
```

Set:

```text
DEPLOY_AKS=true
```

Then:

```bash
make deploy
```

The script refuses the operation unless the switch is exactly `true`. It uses
Azure CLI rather than non-dry-run `kars up`, because kars `0.1.25` appends an
`-aks` suffix to the requested name. It creates the exact cluster name supplied
in `AKS_NAME`, builds the BYO image through ACR Tasks with
`--platform linux/amd64`, resolves its digest, installs kars and AGT, and
applies the reviewed resources.

No subscription ID or credential is written to the repository.

## Verified Azure deployment

The real deployment completed on the configured Azure environment:

- The configured AKS cluster is `Succeeded` with Azure CNI Overlay and Cilium.
- OIDC issuer and Workload Identity are enabled.
- The one-node `system` pool uses `Standard_D2as_v5`; the one-node
  `clawpool` uses `Standard_D4as_v5`. Both nodes report `amd64`.
- The kars Controller and AGT Registry/Relay are Ready.
- OpenClaw Intake, Builder, and Reviewer Sandboxes are Running.
- Builder and Reviewer use the same ACR image pinned by SHA-256 digest.
- A real `gpt-5.6-sol` request returned
  `KARS_BYO_GPT_5_6_SOL_OK FORMAT-482 STOP_FOR_HUMAN_REVIEW`.
- Router audit-chain verification, Agent credential isolation, and the BYO
  Agent exec-denial test passed.

## Do not overclaim Mesh or A2A

kars `0.1.25` exposes `mesh`, `pair`, and `a2a` CLI surfaces, and current
upstream blueprints describe federation. This experiment intentionally uses
`registryMode: local` plus a reviewed application handoff contract.

It does not claim that cross-cluster pairing, Entra mesh trust, public A2A,
encrypted relay transport, token expiry, replay defense, or dual-cluster audit
was executed. Those require a separate deployment with two independently
controlled trust domains and explicit negative tests.

## Platform support

The deployment command ran from macOS arm64, but ACR Tasks explicitly built
the workload as Linux amd64 and both AKS nodes report `amd64`. macOS amd64 and
Linux amd64 use the same scripts. Windows amd64 runs inside Ubuntu WSL2 with
Docker Desktop WSL integration and all CLIs installed inside WSL2.

## Definition of done

The AKS promotion is ready only when the OpenClaw-derived requirement remains
traceable, Builder cannot self-approve, Reviewer cannot edit source, both
runtime and policy artifacts are digest-pinned, Day-0 AKS choices are reviewed,
the GitOps resources pass admission, external audit and rollback are prepared,
and post-deployment tests prove one allowed workflow and one denied authority
violation.

## Official references

- [kars getting started](https://github.com/Azure/kars/blob/main/docs/getting-started.md)
- [Enterprise self-hosted blueprint](https://github.com/Azure/kars/blob/main/docs/blueprints/03-enterprise-self-hosted.md)
- [Cross-org federation blueprint](https://github.com/Azure/kars/blob/main/docs/blueprints/05-cross-org-federation.md)
- [kars CRD reference](https://github.com/Azure/kars/blob/main/docs/api/crd-reference.md)
- [Microsoft Agent Framework GitHub Copilot samples](https://github.com/microsoft/agent-framework/tree/main/python/samples/02-agents/providers/github_copilot)
- [Microsoft Agent Framework Build Your Own Claw](https://github.com/microsoft/agent-framework/tree/main/python/samples/02-agents/harness/build_your_own_claw)
- [Azure CNI Overlay](https://learn.microsoft.com/azure/aks/azure-cni-overlay)
## Sandbox-escape checkpoint: hand off digests, not mutable workspaces

The AKS promotion stage adds an artifact-manifest digest to the patch and test
digests. `code/07` denies review of an unpinned envelope and validates that
Builder and Reviewer have strict egress, disposable writable paths, and no
shell, Docker, exec, or settings capability.

KARS makes each role a separate governed workload. The advantage over one
multi-role Agent is that identity, tools, budgets, egress, and lifecycle can be
different for Builder and Reviewer and verified from Kubernetes state.

```bash
cd code/07
make unit
make validate
```

The Reviewer verifies an immutable claim without inheriting the Builder's
workspace or its possible hooks and configuration.
