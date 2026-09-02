# 6. Runtime 与 BYO：从 OpenClaw 转向明确代码

> **交付阶段：** 生产实现
> **起点：** 保留已经验证的 OpenClaw 行为，再决定哪个应用循环运行在 kars Security
> Shell 内部或旁边。
> **可执行实验：** [`code/05`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/05)

## 一切仍然从 OpenClaw 开始

[`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01)
已经使用 OpenClaw 验证 FORMAT-482 用户路径：

```text
接收 Issue -> 检查仓库 -> Patch -> 具名测试 -> 证据
```

[`code/02`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/02)
验证 Sandbox Boundary，
[`code/03`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/03)
验证 Kubernetes API Contract，
[`code/04`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/04)
验证推理与工具 Policy。第 6 章只替换 Runtime Loop，不能削弱这些边界。

生产问题不是“哪个 Framework 最好”，而是：

> 另一个实现能否保留相同状态、权限、模型、失败行为和 Human Review Stop？

实验把 Workflow 转换为明确状态机：

```text
RECEIVE_REQUIREMENT
  -> VALIDATE_SCOPE
  -> INSPECT_REPOSITORY
  -> PROPOSE_PLAN
  -> APPLY_MINIMAL_PATCH
  -> RUN_TARGETED_TESTS
  -> SUMMARIZE_EVIDENCE
  -> STOP_FOR_HUMAN_REVIEW
```

其中故意没有 `MERGE` 或 `DEPLOY` 状态。

## 区分 Framework、Provider 与 Runtime

三个容易被混用的名称属于不同层：

| 层 | 本章示例 | 职责 |
| --- | --- | --- |
| Agent Framework | Microsoft Agent Framework | Agent API、Tool、Session 与应用结构 |
| Model Provider Path | GitHub Copilot / GPT-5.6-Sol | 模型访问与 Host-side Copilot Session |
| kars Runtime | `OpenClaw`、`MicrosoftAgentFramework` 或 `BYO` | Governed Sandbox 内的 Container Plan |

修改 `KarsSandbox.spec.runtime.kind` 会切换 Runtime Container Producer，但不会自动把
OpenClaw Prompt 转换为经过测试的 Python 代码。

## 两个引用示例之间存在真实接口差异

Microsoft
[Build Your Own Claw](https://github.com/microsoft/agent-framework/tree/main/python/samples/02-agents/harness/build_your_own_claw)
示例通过以下方式创建 Harness：

```python
create_harness_agent(client=chat_client, ...)
```

这个 Factory 需要 Chat Client。
[GitHub Copilot Provider](https://github.com/microsoft/agent-framework/tree/main/python/samples/02-agents/providers/github_copilot)
则提供 `GitHubCopilotAgent`：它已经是带有 Copilot CLI Session 和独立 Tool Loop 的
完整 Agent，不是 Chat Client，因此不能直接传给 `create_harness_agent`。

所以 [`code/05`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/05)
不会声称存在一个实际上不存在的 Drop-in Integration。实验保留 Claw
示例中的明确规划、受限工具、Approval、状态与 Human Review Stop，并验证两条真实
路径。

## 路径 A：Host-side MAF GitHub Copilot Canary

```text
Microsoft Agent Framework GitHubCopilotAgent
    -> 本机已认证 Copilot CLI
    -> GitHub Copilot GPT-5.6-Sol
```

实验通过 Microsoft Package Feed Proxy 安装准确版本：

```text
agent-framework-github-copilot==1.0.3
```

Agent 明确固定模型：

```python
GitHubCopilotOptions(
    model="gpt-5.6-sol",
    available_tools=["inspect_forge_contract"],
    on_permission_request=bounded_permission_handler,
)
```

Copilot SDK 仍然有自己的 Custom Tool Permission Layer。MAF
`approval_mode="never_require"` 不代表批准所有 Copilot Action。Permission Handler
只批准一次 `inspect_forge_contract`，并拒绝 Shell、File、URL、MCP、Write 和其他
所有请求。

Tool 会返回 Prompt 中不存在的随机 Nonce。通过结果必须包含这个 Nonce：

```text
COPILOT_GPT_5_6_SOL_OK FORMAT-482 <random-nonce> STOP_FOR_HUMAN_REVIEW
```

这样可以避免把只复述文字的回答误认为 Tool 已经执行。

路径 A 使用 Host 已认证的 Copilot CLI；它是 Framework/Provider Canary，不是
kars 隔离工作负载。

## 路径 B：kars BYO 生产候选

```text
KarsSandbox/runtime.kind=BYO
    -> BYO Python Application
    -> http://127.0.0.1:8443/v1/responses
    -> kars Router
    -> GitHub Copilot GPT-5.6-Sol
```

模型仍由 `InferencePolicy` 选择：

```yaml
spec:
  modelPreference:
    primary:
      provider: azure-openai
      deployment: gpt-5.6-sol
  tokenBudget:
    perRequestTokens: 1024
    dailyTokens: 4096
```

在本教程的 Local kars 配置中，Router Provider Override 是 `github-copilot`，
`deployment` 承载模型 ID。BYO Agent 可以看到 `KARS_MODEL=gpt-5.6-sol`，但不会
获得 Copilot Token。

Runtime 声明是：

```yaml
spec:
  runtime:
    kind: BYO
    byo:
      image: forge-byo-copilot-claw:dev
      contractVersion: v1
```

## BYO Image Contract

Image 必须声明并实现 Contract：

```dockerfile
LABEL org.kars.runtime.contract="v1"
USER 1000
```

kars 会在 `/sandbox` 挂载 `emptyDir`。不可变应用代码不能写入会被 Runtime Mount
覆盖的路径。
[`code/05`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/05)
把代码放在 `/app`，只把 `/sandbox` 和 `/tmp` 用作可写
Runtime State。

实验验证：

- OCI Contract Label `v1`；
- Image User 与 Agent Container UID 1000；
- Router UID 1001；
- Read-only Root Filesystem；
- Agent Drop 全部 Capability；
- 特权操作只存在于短生命周期 `egress-guard` Init Container；
- `KARS_RUNTIME_KIND=BYO`；
- `KARS_RUNTIME_CONTRACT_VERSION=v1`；
- Agent Environment 中没有 GitHub/Copilot Provider Credential 名称。

## Localhost 是 Provider Boundary

BYO 应用直接连接 `example.com:443` 时发生 Timeout。同一个进程随后调用
`127.0.0.1:8443` Router，并获得真实 GPT-5.6-Sol 响应：

```text
KARS_BYO_GPT_5_6_SOL_OK FORMAT-482 STOP_FOR_HUMAN_REVIEW
```

在已验证运行中，这个结果通过 30 个 Responses API Event 返回。InferencePolicy
显示 Compiled 与 Loaded Digest 一致，Phase 为 `Ready`。

这证明替换 Agent Loop 不会自动获得直接模型或 Internet 访问能力。

## Live CRD 实际接受什么

实验对已经安装的 CRD 执行 Server-side Dry-run：

| Runtime Shape | 结果 |
| --- | --- |
| `MicrosoftAgentFramework` + `language: python` | 接受 |
| `MicrosoftAgentFramework` + `language: dotnet` | 拒绝：支持值只有 `python` |
| 没有 `contractVersion` 的 `BYO` | 拒绝：Required Value |

部分上游说明仍把 MAF .NET 描述为进入 Degraded Condition 的 Deferred Runtime，但本
教程实际安装的 CRD 会在 Admission 阶段直接拒绝它，不会进入 Reconcile。Live Schema
才是当前行为的权威依据。

第一方 MAF Python Schema 是有效的；但
[`code/05`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/05)
部署 Self-contained BYO Image，
以确保 Custom Application Artifact 与 Entry Point 可以被完全控制和直接测试。

## 运行

保持 [`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01)
运行，并确保 Copilot CLI 已认证：

```bash
jq -r .provider ~/.kars/config.json
# github-copilot

cd code/05
make test
```

已经验证的 Host 是 macOS arm64。继承的平台设置还支持 macOS amd64、Linux amd64，
以及通过 Ubuntu WSL2 运行的 Windows amd64。

实验强制使用：

```text
npm    https://packagefeedproxy.microsoft.io/npm/
PyPI   https://packagefeedproxy.microsoft.io/pypi/simple/
NuGet  https://packagefeedproxy.microsoft.io/nuget/v3/index.json
```

## 已验证结果

完整运行证明：

| 检查 | 结果 |
| --- | --- |
| Framework-neutral Workflow Test | 通过 |
| MAF `GitHubCopilotAgent` Model | `gpt-5.6-sol` |
| Bounded Custom Tool | 调用一次并回显随机 Nonce |
| MAF Python CRD Shape | 接受 |
| MAF .NET CRD Shape | 拒绝 |
| 缺少 BYO Contract Version | 拒绝 |
| BYO Image | arm64、UID 1000、Contract Label `v1` |
| BYO Direct Egress | Timeout Deny |
| BYO Provider Credential | Agent Environment 中不存在 |
| BYO Router Inference | GPT-5.6-Sol 响应成功 |
| InferencePolicy | Compiled Digest 等于 Loaded Digest |
| 最终 Workflow State | `STOP_FOR_HUMAN_REVIEW` |

证据保存在 `code/05/.evidence/<UTC timestamp>/`，不包含 Secret Value。

## 官方参考

- [Azure/kars Runtime Catalog](https://github.com/Azure/kars/blob/main/docs/runtimes.md)
- [Azure/kars Runtime Contract](https://github.com/Azure/kars/blob/main/docs/runtimes/CONTRACT.md)
- [Azure/kars BYO Quickstart](https://github.com/Azure/kars/tree/main/examples/byo-quickstart)
- [Microsoft Agent Framework GitHub Copilot Samples](https://github.com/microsoft/agent-framework/tree/main/python/samples/02-agents/providers/github_copilot)
- [Microsoft Agent Framework Build Your Own Claw](https://github.com/microsoft/agent-framework/tree/main/python/samples/02-agents/harness/build_your_own_claw)
## Sandbox Escape 检查点：固定 Host-to-Runtime Handoff

Agent Image 在集群外构建时，Artifact 本身就是新的信任边界。`code/05` 只接受位于
不可变 `/app` 下、不是 Symlink 且具有 SHA-256 Digest 的 Runtime Code。可写
`/sandbox` 配置和 Floating Label 会 Fail Closed。

KARS 在变化的 Application Artifact 外提供稳定边界：Runtime Adapter 可以改变，
Inference Routing、Credential Placement、Network Restriction 与 Governance 仍由
平台持有。

```bash
cd code/05
make unit
```

Runtime 必须执行经过评审的 Artifact，而不是只信任一个同名路径。
