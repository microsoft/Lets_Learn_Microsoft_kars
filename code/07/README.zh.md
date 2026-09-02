# kars AKS 与 Multi-Agent Promotion 实验

[English](README.md) | [简体中文](README.zh.md)

本实验从
[`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01)
的 OpenClaw Forge Contract、
[`code/05`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/05)
的 GPT-5.6-Sol BYO Runtime，以及
[`code/06`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/06)
的安全与恢复证据开始。它准备一条经过评审的 AKS Promotion
路径，同时禁止同一个 Agent 编写并批准自己的变更：

```text
OpenClaw Intake
    -> 已批准 FORMAT-482 Contract
    -> Forge Builder（Patch + Targeted Test）
    -> Digest-pinned Handoff Envelope
    -> Forge Reviewer（读取证据 + Approve/Reject）
    -> Human-reviewed GitOps Promotion
    -> kars on AKS
```

默认运行有意采用 **Plan-only**。它执行 kars `up --dry-run`，用 Live Local kars
CRD 验证 GitOps Resource，不创建任何 Azure Resource。真实 AKS Deployment 必须
明确 Opt-in，因为它会创建产生费用的基础设施。

## 默认与可选 Azure 参数

| Variable | 值 | 含义 |
| --- | --- | --- |
| `AZURE_RESOURCE_GROUP` | 必填 | 你的 Azure Resource Group |
| `AKS_NAME` | 必填 | 你的 AKS Cluster 名称 |
| `KARS_ACR_NAME` | 必填 | 你的全局唯一 ACR 名称 |
| `LOG_ANALYTICS_WORKSPACE` | 必填 | 你的 Log Analytics Workspace |
| `AZURE_LOCATION` | 已存在 Resource Group 的 Location，否则 `eastus2` | Azure Region |
| `KARS_SANDBOX_NAME` | `forge-intake` | `kars up` 创建的初始 OpenClaw Sandbox |
| `KARS_RELEASE` | `v0.1.25` | 固定 kars Release |
| `KARS_ISOLATION` | `enhanced` | kars Isolation Level |
| `KARS_MESH_TRUST` | `anonymous` | 初始 Mesh Trust Mode |
| `GITHUB_COPILOT_MODEL` | `gpt-5.6-sol` | 指定模型 |
| `DEPLOY_AKS` | `false` | 真实 Azure 创建开关 |
| `FORGE_IMAGE` | Local Development Image | Plan-only Image Placeholder；真实部署会在 ACR 构建并固定 Digest |

如需提供 Azure 参数但不提交：

```bash
cp config/aks.env.example config/aks.env
```

`config/aks.env` 已加入 Git Ignore。

## Plan-only 实验要证明什么

- [`code/05`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/05)
  仍为 `Running`，并保持原始 1024 Token Policy。
- [`code/06`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/06)
  的 BYO Exec Admission Guard 已安装。
- npm、PyPI 和 NuGet 使用 Microsoft Package Feed Proxy。
- Promotion 前，Host-side Microsoft Agent Framework
  `GitHubCopilotAgent` 会执行真实 GPT-5.6-Sol Tool Call。
- Handoff Contract 固定 Patch 与 Test Evidence SHA-256 Digest。
- Builder 可以提出 Patch，但不能批准 Release。
- Reviewer 可以读取和评审 Builder Evidence，但不能修改 Source，也不能批准自己
  生成的 Artifact。
- Builder 和 Reviewer 使用独立的 `KarsSandbox`、`InferencePolicy` 与
  `ToolPolicy`。
- Reviewer 的 Inference Budget 更小。
- 两个角色都保留 BYO v1 Contract、Strict Egress、Enhanced Isolation、
  Read-only Root Filesystem 与 GPT-5.6-Sol。
- Live kars API Server 使用 `kubectl apply --dry-run=server` 接受全部六个
  Resource。
- kars `0.1.25` 针对目标 Azure 参数完成 `kars up --dry-run`。
- 真实部署必须明确启用，并提供上游 kars Source Checkout，否则会被拒绝。
- Promotion Record 关联 Source Git Commit、
  [`code/05`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/05)
  Image Digest、
  [`code/06`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/06)
  Loaded Policy Digest 与目标 AKS 参数。

## 不创建 Azure Resource 的运行方式

```bash
cd code/07
make test
```

已完成的默认运行解析为：

```text
Resource group: <your-resource-group>
AKS cluster:    <your-aks-cluster>
Location:       <your-azure-region>
Model:          gpt-5.6-sol
kars release:   v0.1.25
Azure created:  no
```

成功输出最后是：

```text
All plan-only AKS and multi-agent checks passed.
No Azure resources were created.
Evidence: .../code/07/.evidence/<UTC timestamp>
```

可单独执行：

```bash
make unit
make plan
make validate
```

## GitOps 权限拆分

渲染后的文件是 `rendered/multi-agent.yaml`。

| 控制 | Builder | Reviewer |
| --- | --- | --- |
| Sandbox | `forge-builder` | `forge-reviewer` |
| Per-request Budget | 2048 | 512 |
| Daily Budget | 8192 | 2048 |
| Patch Source | 通过 Named Workspace Action 允许 | 不存在 |
| Review Decision | 不存在 | Named Review Action |
| Approval Mode | Tool Gate 为 `never` | `always` |
| Trust Threshold | 700 | 800 |

传递 Handoff Envelope 不会把 Builder 的 Workspace、Credential 或 Tool
Authority 交给 Reviewer。

## AKS Day-0 与 Day-1 决策

计划把基础设施创建交给当前 kars `up` Workflow。Dry-run 报告它会处理 AKS、ACR、
Key Vault、Model Infrastructure、Azure Monitor、Workload Identity、Firewall、
Helm 和初始 Sandbox。

真实部署前必须评审：

- **Day 0：** Azure Location、Address Space/Network Architecture、API
  Exposure、Isolation Level、Node/Region Quota 与 Identity Topology。
- **Day 1：** GitOps Reconciliation、External Audit Export、Monitoring、
  Maintenance Window、Policy Rollout、Rollback 与
  [`code/06`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/06)
  Recovery
  Procedure。

生产环境默认建议 Azure CNI Overlay/Cilium 与 Workload Identity，除非环境有明确
记录的原因选择其他 Day-0 Design。必须检查 kars 实际创建的 Cluster，不能把 CLI
Plan 当作每个 Network Setting 已经验证。

## 真实 Azure Deployment

先评审 `.evidence/<run>/aks-plan.json`、渲染后的 Manifest、Quota 与 Cost。
真实部署使用 Azure CLI，而不是非 Dry-run `kars up`，因为 kars `0.1.25` 会在
请求的 Cluster Name 后追加 `-aks`。

```bash
cp config/aks.env.example config/aks.env
# 编辑 config/aks.env：
# DEPLOY_AKS=true

make deploy
```

`make deploy` 会创建 `AKS_NAME` 指定名称的 Cluster，以及配置的 ACR 与 Log Analytics
Workspace；导入 kars `v0.1.25`；通过 ACR Tasks 和
`--platform linux/amd64` 构建 BYO Image；按 Digest 固定 Image；安装 kars 与
AGT；并应用经过评审的 Builder/Reviewer Resource。如果 `DEPLOY_AKS` 不严格
等于 `true`，脚本会拒绝部署。

Repository 和 Evidence 不保存 Subscription ID、Credential 或 Secret Value。

### 已验证的 Azure 结果

- 配置 Azure Location 中的 AKS Cluster 状态为 `Succeeded`。
- `system` Pool 使用一个 `Standard_D2as_v5` Node，`clawpool` 使用一个
  `Standard_D4as_v5` Node；两者均报告 `amd64`。
- Azure CNI Overlay、Cilium、OIDC Issuer 与 Workload Identity 已启用。
- kars Controller、AGT Registry/Relay、OpenClaw Intake、Builder 与 Reviewer
  均为 Running。
- Builder 与 Reviewer 使用相同的、按 Digest 固定的 Linux amd64 Image。
- 真实 Router 调用通过 `gpt-5.6-sol` 返回
  `KARS_BYO_GPT_5_6_SOL_OK`；Router Audit Integrity、Credential Isolation 与
  Exec Denial 也全部通过。

## Mesh 与 A2A 范围

已安装的 kars CLI 提供 `mesh`、`pair` 与 `a2a` 命令，当前上游 kars 也记录
Cluster Federation 和 A2A Ingress。本实验使用 `registryMode: local` 和确定性的
Reviewed Handoff Envelope，不会声称已经执行 Cross-cluster Pairing、Public A2A
Ingress、Entra Mesh Trust 或 Encrypted Relay Delivery。

这些能力必须在独立验证 Trust、Expiry、Replay、Ingress、Dual-policy 和 Audit 后
才启用。Connectivity 不等于 Authorization。

## Evidence

每次运行会写入：

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

## 平台支持

完整运行已经在 macOS arm64 验证。继承的脚本支持 macOS amd64 和 Linux amd64。
Windows amd64 请在 Ubuntu WSL2 内运行，并启用 Docker Desktop WSL Integration；
Azure CLI、kubectl、Helm、Node.js 22 和 kars CLI 也应安装在 WSL2 内。

## 参考

- [Azure/kars Getting Started](https://github.com/Azure/kars/blob/main/docs/getting-started.md)
- [Azure/kars Enterprise Self-hosted Blueprint](https://github.com/Azure/kars/blob/main/docs/blueprints/03-enterprise-self-hosted.md)
- [Azure/kars Cross-org Federation Blueprint](https://github.com/Azure/kars/blob/main/docs/blueprints/05-cross-org-federation.md)
- [Azure/kars CRD Reference](https://github.com/Azure/kars/blob/main/docs/api/crd-reference.md)
- [Microsoft Agent Framework GitHub Copilot Samples](https://github.com/microsoft/agent-framework/tree/main/python/samples/02-agents/providers/github_copilot)
- [Microsoft Agent Framework Build Your Own Claw](https://github.com/microsoft/agent-framework/tree/main/python/samples/02-agents/harness/build_your_own_claw)
- [Azure CNI Overlay](https://learn.microsoft.com/azure/aks/azure-cni-overlay)
## Sandbox Escape 递进：评审 Artifact，而不是继承 Workspace

Builder-to-Reviewer Handoff 现在除 Patch 与 Test Evidence Digest 外，还携带
`artifact_manifest_digest`。三者任何一个未固定，Review Authorization 都会失败。
GitOps Validation 还要求 Default-deny Egress、没有任意 Endpoint、可写路径严格等于
临时目录，并且两个角色都不能拥有 Shell、Exec、Docker 或 Settings Capability。

本阶段的 KARS 优势是 Builder 与 Reviewer 获得相互独立、由 Controller 管理的
Sandbox 和 Policy。职责分离由平台资源执行，而不是要求同一个多角色 Agent 记住
自己当前“戴着哪顶帽子”。

运行 `make unit` 与 `make validate`。Reviewer 只接收 Digest-pinned Envelope，
不会继承 Builder 的可变 Workspace，从而防止 Trust Handoff Artifact 在 Promotion
过程中获得权限。
