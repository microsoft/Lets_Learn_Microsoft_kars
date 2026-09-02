# 5. 治理：控制 Token 与工具

> **交付阶段：** 功能开发
> **起点：** OpenClaw 协调 FORMAT-482，但 kars 决定这条工作流可以使用哪些推理和
> Workspace Capability。
> **可执行实验：** [`code/04`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/04)

## 一切从 OpenClaw 工作流开始

Forge 示例不是从通用 Shell 开始。OpenClaw 接收 FORMAT-482 Issue、规划任务，再通过
kars Router 和 Workspace MCP 委派受限操作：

```text
FORMAT-482
    |
    v
OpenClaw Coordinator（KarsSandbox/forge）
    |-- 推理 --> 127.0.0.1:8443 kars Router
    |-- MCP --> forge-workspace-mcp:8931/mcp
    `-- Specialist -> 只有推理和 Mesh
```

Workspace MCP 拥有一次性的 `/workspace`；OpenClaw 不直接挂载仓库。通过这种分离，
Policy 可以回答四个不同问题：

1. 哪个 MCP Server 可以注册给 Forge？
2. Coordinator 可以使用哪些准确的 Tool Capability？
3. Workspace MCP 实现接受哪些输入？
4. 单次请求和每日最多可以消耗多少推理 Token？

可运行定义位于
[`policies.yaml`](https://github.com/kinfey/LetsLearnMicrosoftKars/blob/main/code/01/k8s/policies.yaml)
和
[`workspace-mcp.yaml`](https://github.com/kinfey/LetsLearnMicrosoftKars/blob/main/code/01/k8s/workspace-mcp.yaml)。

## 三层控制，而不是一个 Allow-list

| 层 | Forge 配置 | 防止的问题 |
| --- | --- | --- |
| `McpServer` | 七个 `allowedTools`，以及 Label 为 `forge` 的 `allowedSandboxes` | 注册意外工具面，或把服务暴露给无关 Sandbox |
| `ToolPolicy` | 明确 AGT Capability、`rps: 2`、`burst: 20`、`window: 1m` | 调用者使用加载 Profile 中不存在的 Capability |
| Workspace MCP 实现 | 标准化路径、准确替换、固定测试 ID、CI 和大小限制 | 合法工具名称被危险参数滥用 |

这些控制彼此互补。工具出现在 MCP `tools/list` 中，不代表每个 Agent 都获得调用授权；
同样，`ToolPolicy` 中存在 Capability，也不代表任意路径或命令是安全的。

### MCP 粗粒度注册

Forge 只注册七个工具：

```yaml
spec:
  allowedTools:
    - workspace_get_task
    - workspace_read_file
    - workspace_search
    - workspace_apply_patch
    - workspace_run_test
    - workspace_get_diff
    - workspace_reset
  allowedSandboxes:
    matchLabels:
      kars.azure.com/sandbox: forge
```

工具面没有 Shell、上传、任意网络请求、环境变量 Dump 或自由命令执行。

### Coordinator 与 Specialist Capability

Coordinator Profile 明确列出每个允许操作：

```yaml
allowed_actions:
  - "inference:chat_completions:*"
  - "inference:responses:*"
  - "inference:content_safety:*"
  - "spawn:*"
  - "mesh:*"
  - "tool:workspace_get_task:*"
  - "tool:workspace_read_file:*"
  - "tool:workspace_search:*"
  - "tool:workspace_apply_patch:*"
  - "tool:workspace_run_test:*"
  - "tool:workspace_get_diff:*"
  - "tool:workspace_reset:*"
```

Specialist 只有推理和 Mesh Capability。Specialist Pod 仍可能包含
`KARS_MCP_SERVERS=forge-workspace`；隐藏 Server Registration 不是安全边界。真正的
限制是 Specialist AGT Profile 中没有任何 `tool:workspace_*` Capability。

## 验证 Policy 已加载，而不只是已提交

kars 会把内联 AGT Profile 编译为 ConfigMap。Router 回报已加载 Digest，Controller
显示：

```text
ToolPolicy/forge-workspace-tools
phase: Ready
condition: Ready=True
reason: RouterEnforcing
```

[`code/04`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/04)
要求 `status.agtProfileDigest` 与编译 ConfigMap Annotation 完全一致，同时
验证 Selector、Rate Limit、Approval Mode 和七个 Capability 字符串。仅仅
`kubectl apply` 成功不能作为充分证据。

Rate Limit 通过编译并加载的契约来证明。实验不会为了耗尽 Token Bucket 而对正在运行
的 Router 发起洪泛。

## 在请求路径强制推理预算

Forge 同时使用单请求和每日限制：

```yaml
spec:
  tokenBudget:
    perRequestTokens: 20000
    dailyTokens: 100000
```

实验先检查 InferencePolicy 的 Compiled Digest 与 Loaded Digest 一致，再发送
`max_completion_tokens: 20001` 的请求。因为超过 20,000 Token 单请求限制，Router
返回 HTTP 429。

这比只查看 YAML 更有说服力，因为它证明了请求路径上的实际强制行为。Azure Quota、
成本告警和任务级循环限制仍然是额外保护层。

## 把仓库指令当作不可信数据

一次性 Fixture 中包含一条提到 `collect.example` 的恶意 README 指令。
`workspace_read_file` 可以读取这些文字，但读取文字不会产生新的 Capability。

直接 MCP 实验通过 Streamable HTTP/SSE JSON-RPC 请求验证：

| 尝试 | 已验证结果 |
| --- | --- |
| 读取 `../../etc/passwd` | Tool Result 为 `isError: true`，路径穿越被拒绝 |
| 调用 `does_not_exist` | JSON-RPC Error `-32602`，未知工具被拒绝 |
| 运行测试 ID `npm-test` | Tool Result 为 `isError: true`，测试未批准 |
| 修改 `.github/workflows/ci.yml` | Tool Result 为 `isError: true`，禁止修改 CI |
| 使用准确预期文本修改 `src/formatUser.js` | Patch 成功 |
| 运行具名测试 `format-user` | Patch 前失败，Patch 后通过 |
| 获取 Diff | 准确的 Unified Diff 包含批准的 `UNKNOWN` Fallback |

具名测试在 MCP 实现中映射为固定参数向量。OpenClaw 无法把仓库中的文字转换为
`npm test`、`curl` 或任意 Shell 命令。

## 让依赖故障明确可见

实验会先停止本地 Port-forward，再把 `Deployment/forge-workspace-mcp` 缩容到零，
并检查 Service 没有 Ready Endpoint；之后恢复一个 Replica，等待 Deployment
重新 Ready。

预期行为是明确不可用，而不是伪造 Patch 或测试结果。脚本安装了 Exit Trap，因此运行
中断时也会尝试恢复 MCP Replica。

## 运行实验

保持 [`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01)
Forge Deployment 运行，然后执行：

```bash
cd code/04
make test
```

已经验证的 Host 是 macOS arm64。继承的平台设置还支持 macOS amd64、Linux amd64，
以及通过 Ubuntu WSL2 运行的 Windows amd64。

实验配置并检查 Microsoft Package Feed Proxy：

```text
npm    https://packagefeedproxy.microsoft.io/npm/
PyPI   https://packagefeedproxy.microsoft.io/pypi/simple/
NuGet  https://packagefeedproxy.microsoft.io/nuget/v3/index.json
```

每次运行都会把 Policy Object、Compiled Profile、JSON-RPC Response、Budget Denial、
Controller 与 Router Log，以及准确 Patch Diff 保存到
`code/04/.evidence/<UTC timestamp>/`。

## 已验证验收矩阵

| 场景 | 决策 | 证据 |
| --- | --- | --- |
| MCP 工具面 | 只允许七个具名工具 | Runtime List 等于 `McpServer.allowedTools` |
| 批准的 Patch 与测试 | Allow | Patch Response、通过的 `format-user`、Unified Diff |
| 路径穿越、CI Patch、未知工具、未知测试 | Deny | MCP 与 JSON-RPC Error Evidence |
| Specialist Workspace Capability | 通过省略实现 Deny | Specialist AGT Profile 没有 `tool:workspace_*` |
| 请求超过 20,000 Tokens | Deny | Router HTTP 429 |
| 已配置工具速率 | 已加载并强制执行的 Profile | `Ready=True/RouterEnforcing` 与匹配 Digest |
| Workspace MCP 故障 | 明确失败并恢复 | Endpoint 变空，随后 Deployment Ready |

只有声明的 Policy、Router 加载的 Digest 和 Runtime 行为三者一致，治理才算完成。

## 官方参考

- [Azure/kars MCP Guide](https://github.com/Azure/kars/blob/main/docs/mcp.md)
- [Azure/kars CRD Reference](https://github.com/Azure/kars/blob/main/docs/api/crd-reference.md)
- [Azure/kars Security Model](https://github.com/Azure/kars/blob/main/docs/security.md)
## Sandbox Escape 检查点：Allowlist 必须覆盖参数

编辑工具仅仅出现在 Allowlist 中并不代表安全。`code/04` 的 Live MCP 实验会尝试
写入 Editor Setting、Agent/MCP 配置、Git Hook、CI 与 Package Metadata。Tool
Implementation 必须拒绝所有目标，同时保留批准的 `src/` Patch 路径。

KARS 把这项 Authorization 保留在 Agent Runtime 外部。即使模型、Prompt 或 Agent
Framework 改变，同一个 Router 与 `ToolPolicy` Decision 仍然有效。

```bash
cd code/04
make test
```

这会关闭公开 Coding Agent Sandbox Escape 中反复出现的 Self-configuration 与
Trust Handoff 路径。
