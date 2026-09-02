# kars Runtime 与 BYO 实验

[English](README.md) | [简体中文](README.zh.md)

本实验把第 6 章转换为两条可执行 Runtime 路径，并以
[`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01)
已经建立的
OpenClaw Forge 行为作为共同起点：

```text
路径 A：Host-side Framework/Provider Canary
Microsoft Agent Framework GitHubCopilotAgent
    -> 本机已认证 Copilot CLI
    -> GitHub Copilot GPT-5.6-Sol

路径 B：Cluster 内生产候选
kars KarsSandbox/runtime.kind=BYO
    -> 127.0.0.1:8443 kars Inference Router
    -> GitHub Copilot GPT-5.6-Sol
```

两条路径有意不共享凭据。路径 A 使用 Host Copilot CLI Session；路径 B 的 Agent
容器没有 GitHub 或 Copilot Provider Credential，Provider 路径只属于 kars Router。

## 为什么需要两条路径

引用的 Microsoft Agent Framework 示例提供两个不同抽象：

- `create_harness_agent(...)` 需要 Chat Client。
- `GitHubCopilotAgent` 已经是带有 Copilot CLI Session 和 Tool Loop 的完整 Agent。

`GitHubCopilotAgent` 不是 Chat Client，不能直接传给 `create_harness_agent`。因此本实验
复用 Claw 示例中的明确规划、受限工具、Approval 和操作前停止原则，但不会声称存在
一个实际上不存在的 Drop-in 组合。

## 实验要证明什么

- 与 Framework 无关的 FORMAT-482 状态机结束于 `STOP_FOR_HUMAN_REVIEW`，不存在
  `MERGE` 或 `DEPLOY` 状态。
- `agent-framework-github-copilot==1.0.3` 从 Microsoft Package Feed Proxy 安装。
- 真实 `GitHubCopilotAgent` 调用使用 `gpt-5.6-sol`。
- Host Agent 只有一个 Custom Tool；Permission Handler 只批准一次
  `inspect_forge_contract`，其他权限全部拒绝。
- 模型回显只能由工具返回的随机 Run Nonce，证明工具确实执行。
- Live kars CRD 接受 MAF Python Shape，并拒绝 `language: dotnet`。
- Live kars CRD 拒绝没有 `contractVersion` 的 BYO。
- BYO Image 声明 `org.kars.runtime.contract=v1`，并以 UID 1000 运行。
- kars 注入 `KARS_MODEL=gpt-5.6-sol`、`KARS_RUNTIME_KIND=BYO` 和 Contract
  Version `v1`。
- BYO Agent Environment 中没有 GitHub/Copilot Token 或 Key 名称。
- BYO 直接访问 Internet 会 Timeout。
- 同一个 BYO Agent 通过 Localhost kars Router 成功调用 GPT-5.6-Sol。
- Router Loaded InferencePolicy Digest 与 Compiled Digest 一致。
- BYO Pod 保留 kars Security Shell：Agent UID 1000、Router UID 1001、只读
  Root Filesystem、Drop Capability 与 Egress Guard。

## BYO Image 布局

kars 会在 `/sandbox` 挂载一次性 `emptyDir`。如果把 Image 中的应用代码放在
`/sandbox`，代码会被这个 Mount 覆盖。本实验把不可变代码放在 `/app`，只把
`/sandbox` 和 `/tmp` 用作可写 Runtime State：

```dockerfile
WORKDIR /app
COPY app.py workflow.py ./
USER 1000
```

应用提供：

| Endpoint | 用途 |
| --- | --- |
| `GET /healthz` | Container Health |
| `GET /contract` | 脱敏 Runtime Contract 与 Environment 名称 |
| `GET /direct-egress` | 证明 UID 1000 不能直接连接 Internet |
| `POST /run` | 执行受限 Workflow，并调用 Router `/v1/responses` |

## Microsoft Package Source

实验会应用并检查：

- npm：`https://packagefeedproxy.microsoft.io/npm/`
- PyPI：`https://packagefeedproxy.microsoft.io/pypi/simple/`
- NuGet：`https://packagefeedproxy.microsoft.io/nuget/v3/index.json`

Host Virtual Environment 与 Container Image 都通过 Microsoft Package Feed Proxy
安装 Python Package。实验退出时会恢复上游 Source Rewrite。

## 前置条件

- [`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01)
  Forge 环境已经部署并处于 `Running`。
- Docker Desktop、kind、kubectl、jq、curl、Python 3.11+ 和 Node.js 22。
- GitHub Copilot CLI 已安装并完成认证。
- Copilot Plan 可以使用 GPT-5.6-Sol。
- kars Provider 已配置为 `github-copilot`。

检查 Provider：

```bash
jq -r .provider ~/.kars/config.json
```

必须输出：

```text
github-copilot
```

## 运行

```bash
cd code/05
make test
```

成功输出最后是：

```text
All runtime and BYO checks passed.
Evidence: .../code/05/.evidence/<UTC timestamp>
```

## 单独命令

```bash
make unit      # 与 Framework 无关的状态机测试
make copilot   # Host GitHubCopilotAgent 与 GPT-5.6-Sol 调用
make deploy    # 构建、验证并部署 kars BYO Image
make inspect   # 收集脱敏 kars 与 Pod 证据
./scripts/port-forward.sh  # 在另一个 Terminal 中保持运行
make runtime              # 测试转发后的 BYO Endpoint
make clean     # 删除 code/05 Sandbox 和 InferencePolicy
```

## 证据

每次完整运行会创建：

```text
.evidence/<UTC timestamp>/
├── transcript.log
├── host-copilot-agent.json
├── image-contract.json
├── maf-python-dry-run.txt
├── maf-dotnet-denial.txt
├── byo-contract-denial.txt
├── byo-sandbox.json
├── byo-inference-policy.json
├── byo-deployment-sanitized.json
├── byo-runtime-contract.json
├── byo-direct-egress.json
├── byo-model-response.json
└── byo-scope-denial.json
```

不会导出 Secret Value；Deployment 证据只保留 Environment Variable 名称。

## 平台支持

已经验证的环境是 macOS arm64。继承的平台检测也支持 macOS amd64、Linux amd64，
以及通过 Ubuntu WSL2 运行的 Windows amd64。

## 参考

- [Azure/kars Runtime Catalog](https://github.com/Azure/kars/blob/main/docs/runtimes.md)
- [Azure/kars Runtime Contract](https://github.com/Azure/kars/blob/main/docs/runtimes/CONTRACT.md)
- [Azure/kars BYO Quickstart](https://github.com/Azure/kars/tree/main/examples/byo-quickstart)
- [Microsoft Agent Framework GitHub Copilot Samples](https://github.com/microsoft/agent-framework/tree/main/python/samples/02-agents/providers/github_copilot)
- [Microsoft Agent Framework Build Your Own Claw Samples](https://github.com/microsoft/agent-framework/tree/main/python/samples/02-agents/harness/build_your_own_claw)
## Sandbox Escape 递进：固定 Runtime Artifact

前面章节约束了仓库修改和 Tool Call，本阶段继续约束宿主机交给 Runtime 的 Artifact。
`validate_runtime_artifact` 只接受位于不可变 `/app` 下、带 Digest、且不是 Symlink
的文件；可写 `/sandbox` 配置、路径穿越、Symlink 与 `latest` 等未固定标签全部
Fail Closed。

本阶段的 KARS 优势是在不同 Runtime 外保持稳定的 Security Shell：OpenClaw、
Host-side Framework Canary 与 BYO Container 可以使用不同应用代码，但继续复用
Router、Policy、Identity 与 Network Boundary。

运行 `make unit`。Workflow 在执行补丁前新增
`VERIFY_IMMUTABLE_RUNTIME_ARTIFACT`，避免 Host-to-Runtime Handoff 静默演变为
Sandbox Escape。
