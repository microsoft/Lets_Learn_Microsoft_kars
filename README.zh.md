# 一起学习 Microsoft kars

[English](README.md) | [简体中文](README.zh.md) | [GitHub Pages](https://kinfey.github.io/LetsLearnMicrosoftKars/zh-cn/)

这是一个 **OpenClaw-first**、中英双语、可执行的
[Azure kars](https://github.com/Azure/kars) 学习项目。Repository 通过一个创业
团队的连续故事，把 Issue-to-Pull-Request 原型逐步演进为运行在 AKS 上、由 kars
治理的 Microsoft Agent Framework 应用，并通过 GitHub Copilot GPT-5.6-Sol
完成真实推理。

本项目不只是概念文档。每个阶段都在
[`code/01`–`code/08`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code)
中提供可运行源码、Policy、测试和 Evidence。

> 本教程基于 kars `v0.1.25`，最后检查日期为 2026-08-29。kars 当前是 Alpha
> Reference Implementation，并非 Microsoft 正式支持的产品。使用其他版本时，请用
> `kars --help` 核对命令。

## Repository 展示的能力

- 一切从 **OpenClaw** 开始，先验证受约束的对话式 Workflow。
- 当 Workflow 需要明确应用代码、Typed Tool、重复测试和有限 Model Iteration 时，
  切换到 **Microsoft Agent Framework（MAF）Python**。
- Model Traffic 必须经过本地 **kars Inference Router**，Agent 不直接持有 Provider
  Credential，也没有不受限制的 Egress。
- 通过 Kubernetes API 应用 `KarsSandbox`、`InferencePolicy`、`ToolPolicy` 与
  `McpServer` Contract。
- 强制执行 Model Selection、Token Budget、Tool Allowlist、Egress、Separation of
  Duties、Audit Chain、Repair Limit、Kill Switch、Rollback 和 Human Review。
- 把 Linux amd64 Workload 推广到已有或新建 AKS 环境，同时不公开真实 Azure
  Resource 名称。
- 通过 OpenClaw/BYO 与第一方 MAF Runtime 路径调用真实 GitHub Copilot
  **GPT-5.6-Sol**。

## kars 的主要特点

kars 是一个在 Kubernetes 上运行 AI Agent 的 Reference Stack，其核心是把权限与
Agent Application 分离。主要特点包括：

| 特点 | 工作方式 | 在 Forge 场景中的价值 |
| --- | --- | --- |
| 声明式 Agent Workload | `KarsSandbox` 描述 Runtime、Isolation、Resource、Governance、Network Policy 与 Lifecycle | Forge 以可评审、可重复的 Kubernetes Desired State 运行，而不是临时进程 |
| 代理推理 | 本地 Inference Router 先接收 Agent Request，再调用 Model Provider | OpenClaw 或 MAF 可以使用模型，但不会得到生产 Provider Credential |
| 与 Runtime 解耦的治理 | OpenClaw、Microsoft Agent Framework、BYO Image 与其他 Adapter 复用相同外部 Policy Boundary | 更换 Agent Framework 时不需要重新构建完整安全模型 |
| 模型与预算 Policy | `InferencePolicy` 选择 Provider/Deployment，并设置单请求和每日 Token Limit | Prompt Loop 不能静默更换模型或无限消耗推理预算 |
| 受治理 Tool 与 MCP | `ToolPolicy` 和 `McpServer` 限制 Tool Name、目标 Sandbox、Approval、Rate Limit 与 Capability | 仓库内容不能把受限 Patch Tool 升级为任意 Shell 或 Release Authority |
| Credential 与 Identity 分离 | Provider Credential 或 Workload Identity 保留在 Router/Platform 路径 | Prompt-injected Agent Code 无法从 Environment 读取可复用的 GitHub、Copilot 或 Azure Credential |
| 纵深 Sandbox | Non-root Runtime、Read-only Root Filesystem、明确 Writable Path、UID 分离、Egress Guard、NetworkPolicy 与 Exec Admission | 错误 Agent 决定缺少常见的宿主机、Filesystem、Cluster 与直接网络逃逸能力 |
| Reconciliation 与 Status | Controller 将 Desired State 转换为 Pod，并报告 Condition 与 Observed Generation | 删除或 Drift 的 Workload 会恢复到评审状态；失败会显示为 `Degraded`，而不是隐藏在应用日志中 |
| Audit 与运维控制 | Router Decision、Policy Digest、Evidence Export、Suspend、Repair Limit、Break-glass 与 Rollback 构成运维边界 | 安全团队可以解释拒绝行为、停止失控 Workflow，并在不授予 Agent 永久运维权限的情况下恢复 |
| Multi-Agent 隔离 | Builder、Reviewer 或 Specialist 可以使用不同 Sandbox、Tool、Budget、Identity 与 Trust Requirement | Separation of Duties 由平台资源执行，而不是同一个 Agent Prompt 中的角色说明 |

核心设计原则是：

> Agent 可以决定它想做什么，但不会独立拥有完成该操作所需的 Credential、
> Network Path、Tool 或 Policy。

kars 不会自动让不安全的 Image、MCP Server 或 Agent-generated Artifact 变得安全。
平台团队仍需评审这些组件，并按照 Alpha Reference Implementation 的成熟度说明使用。

## 架构

```text
Requirement / Issue
        |
        v
OpenClaw Intake 与 Prototype
        |
        v
MAF Agent + 受限 Tool
        |
        v
kars Sandbox
  +--------------------------------------+
  | Agent Runtime，UID 1000              |
  |        | localhost:8443/8444         |
  |        v                             |
  | Inference Router，UID 1001           |
  | Policy | Budget | Identity | Audit   |
  +--------------------------------------+
        |
        v
GitHub Copilot GPT-5.6-Sol / 已批准 MCP
        |
        v
按 Digest 固定的 Evidence 与人工评审
```

Agent 不持有生产 Provider Credential。应用从 OpenClaw 演进到 MAF Python 时，kars
仍保持一致的 Inference、Tool、Network、Identity 与 Audit 控制。

## 学习路线与可执行实验

| 章节 | 目标 | Sandbox Escape 检查点 | 可执行实验 |
| --- | --- | --- | --- |
| [1. 为什么使用 kars](https://kinfey.github.io/LetsLearnMicrosoftKars/zh-cn/01-why-kars/) | 实现前先约束产品和 Threat Model | 识别自配置、Symlink、Trust Handoff 与隐蔽出站风险 | Architecture 与 Delivery Contract |
| [2. 本地快速开始](https://kinfey.github.io/LetsLearnMicrosoftKars/zh-cn/02-local-quickstart/) | 构建第一个 OpenClaw Issue-to-Patch Workflow | 通过纵深控制拒绝恶意仓库动作 | [`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01) |
| [3. Sandbox 内部](https://kinfey.github.io/LetsLearnMicrosoftKars/zh-cn/03-inside-the-sandbox/) | 检查 UID、Filesystem、Network 与 Credential Boundary | 移除宿主机、Daemon 与集群环境权限 | [`code/02`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/02) |
| [4. Kubernetes API](https://kinfey.github.io/LetsLearnMicrosoftKars/zh-cn/04-kubernetes-api/) | 通过 CRD 复现 Sandbox 与 Policy State | 防止 Workload 改写自身权限 | [`code/03`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/03) |
| [5. Policy 与 Tool](https://kinfey.github.io/LetsLearnMicrosoftKars/zh-cn/05-policies-and-tools/) | 强制执行 Token、Tool、MCP、Dependency 与 Egress Policy | 校验 Tool Argument 与安全敏感路径 | [`code/04`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/04) |
| [6. Runtime 与 BYO](https://kinfey.github.io/LetsLearnMicrosoftKars/zh-cn/06-runtimes-and-byo/) | 对比 Host-side MAF Canary 与 kars BYO Runtime | 固定不可变 Runtime Artifact | [`code/05`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/05) |
| [7. 安全与运维](https://kinfey.github.io/LetsLearnMicrosoftKars/zh-cn/07-security-and-operations/) | 测试 Repair Limit、Admission、Audit 与 Recovery | 审计 DNS、Metadata、Daemon、Exec 与 HTTPS Channel | [`code/06`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/06) |
| [8. AKS 与 Multi-agent](https://kinfey.github.io/LetsLearnMicrosoftKars/zh-cn/08-aks-and-multi-agent/) | 分离 Builder 与 Reviewer，并推广到 AKS | 传递 Digest-pinned Artifact，而不是可变 Workspace | [`code/07`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/07) |
| [9. 应用项目](https://kinfey.github.io/LetsLearnMicrosoftKars/zh-cn/09-applied-project/) | 运行 OpenClaw-first、第一方 MAF Release Pilot | 执行完整 Release Containment Gate | [`code/08`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/08) |

## 从这里开始

阅读双语教程：

- [简体中文文档](https://kinfey.github.io/LetsLearnMicrosoftKars/zh-cn/)
- [English documentation](https://kinfey.github.io/LetsLearnMicrosoftKars/en/)

运行第一个本地实验：

```bash
git clone https://github.com/kinfey/LetsLearnMicrosoftKars.git
cd LetsLearnMicrosoftKars/code/01
make test
```

实验采用累进方式。运行后续实验前请先完成其前置实验，因为后续阶段会验证前面阶段
创建的实时 Sandbox、Policy、Image 与 Audit Evidence。

## 平台与 Package 要求

- 已验证开发环境：macOS arm64。
- 同时提供 macOS amd64、Linux amd64，以及通过 Ubuntu WSL2 运行 Windows amd64
  的调整说明。
- Azure Workload Target：Linux amd64。
- Node.js：22。
- 不同实验会使用 Docker Desktop、kind、kubectl、Helm、Azure CLI、Python 3.11+、
  jq、curl、kars CLI，以及已认证的 GitHub Copilot CLI。

所有 Package Restore 均使用 Microsoft Package Feed Proxy：

| Ecosystem | Source |
| --- | --- |
| npm | `https://packagefeedproxy.microsoft.io/npm/` |
| PyPI | `https://packagefeedproxy.microsoft.io/pypi/simple/` |
| NuGet | `https://packagefeedproxy.microsoft.io/nuget/v3/index.json` |

## Azure 部署

Repository 不会公开真实 Azure Resource 名称，也不会把示例绑定到真实环境。部署到
Azure 前，请复制对应实验中被 Git Ignore 的 Environment Template，并填写自己的值：

```bash
export AZURE_RESOURCE_GROUP="<your-resource-group>"
export AKS_NAME="<your-aks-cluster>"
export KARS_ACR_NAME="<your-acr-name>"
export AZURE_LOCATION="<your-azure-region>"
```

真实部署必须明确 Opt-in。启用实验的 Deployment Switch 前，请评审 Plan、预期成本、
架构、Policy 与 Rollback Procedure。

## 重要实现说明

- kars `v0.1.25` 的 MAF Runtime Plan 接受 `agentCode.oci`，但生成 Pod 时尚未真正
  Materialize 该 Code Mount。应用项目会把 Immutable Code 保存在 `/sandbox` 之外，
  启动时再复制到 Writable Runtime Volume。
- GPT-5.6-Sol 使用 Responses API。MAF 实现会关闭 Stored Response Continuation，
  以内联方式重放受限 Tool History，从而兼容 kars GitHub Copilot Adapter。
- `KarsEval` 已验证 Corpus Resolution，但上游 `v0.1.25` Runner Job 不符合 AKS
  Restricted Pod Security。示例不会为了运行该 Job 而降低 Namespace Policy。
- Generated Evidence 与本地 Azure Configuration 不会提交。不要把 Credential、
  Token、Subscription ID 或 Customer Source 放入 Repository。

## 官方参考

- [Azure kars Repository](https://github.com/Azure/kars)
- [kars Architecture](https://github.com/Azure/kars/blob/main/docs/architecture.md)
- [kars Getting Started](https://github.com/Azure/kars/blob/main/docs/getting-started.md)
- [kars CRD Reference](https://github.com/Azure/kars/blob/main/docs/api/crd-reference.md)
- [kars Security](https://github.com/Azure/kars/blob/main/docs/security.md)
- [Microsoft Agent Framework](https://github.com/microsoft/agent-framework)
- [GitHub Copilot Provider Samples](https://github.com/microsoft/agent-framework/tree/main/python/samples/02-agents/providers/github_copilot)
- [Build Your Own Claw Sample](https://github.com/microsoft/agent-framework/tree/main/python/samples/02-agents/harness/build_your_own_claw)

## License

除非另有说明，本教程使用 [MIT License](LICENSE)。
