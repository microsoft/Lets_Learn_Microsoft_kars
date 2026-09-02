# kars Policy 与工具实验

[English](README.md) | [简体中文](README.zh.md)

本实验把第 5 章转换为针对
[`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01)
Forge 环境的可执行治理检查，并复用
[`code/02`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/02)
与 [`code/03`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/03)
的边界和证据模式。设计参考上游
[kars MCP Guide](https://github.com/Azure/kars/blob/main/docs/mcp.md)、
[CRD Reference](https://github.com/Azure/kars/blob/main/docs/api/crd-reference.md)
和 [Security Model](https://github.com/Azure/kars/blob/main/docs/security.md)。

## 三层独立工具边界

| 层 | 职责 |
|----|------|
| `McpServer` | 注册服务、准确的 `allowedTools` 与允许的 Sandbox Selector |
| `ToolPolicy` | AGT Capability、Approval Mode、Rate Limit 与 Router 加载的 Policy Digest |
| Workspace MCP 实现 | 路径标准化、Patch 范围、测试 ID Allow-list、固定 argv 与 Diff 大小限制 |

这些层有意形成纵深防御。工具被注册不代表调用者已经获得授权，Prompt 指令也不能取代
输入验证。

## 实验要证明什么

- `forge-workspace-tools` 为 `Ready=True/RouterEnforcing`。
- ToolPolicy Status Digest 与编译后的 ConfigMap Digest 一致。
- 协调器获得全部七个 `tool:workspace_*` Capability。
- Specialist Policy 只有推理和 Mesh Capability，没有 Workspace Tool Capability。
- `McpServer/forge-workspace` 只选择 Forge Label。
- Runtime `tools/list` 与七个 `allowedTools` 完全一致。
- 没有暴露 Shell、上传、任意网络或环境变量读取工具。
- 路径穿越、CI 修改、未知工具和未批准测试全部失败。
- 批准的最小 Patch 与 `format-user` 测试成功。
- 请求 20,001 Tokens 超过 20,000 单请求预算，返回 HTTP 429，不产生成功模型调用。
- 短时 MCP 故障会让 Service Endpoint 变空，之后 Deployment 恢复 Ready。

Rate Limit 通过编译 Profile 与 `RouterEnforcing` Digest 回报进行验证。实验不会为了
耗尽 Token Bucket 而对正在运行的 Router 发起破坏性洪泛。

## Microsoft Package Source

实验会应用并检查：

- npm：`https://packagefeedproxy.microsoft.io/npm/`
- PyPI：`https://packagefeedproxy.microsoft.io/pypi/simple/`
- NuGet：`https://packagefeedproxy.microsoft.io/nuget/v3/index.json`

实验退出时会恢复上游源码文件。

## 运行

保持经过验证的
[`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01)
Forge 环境运行：

```bash
cd code/04
make test
```

命令会把内部 MCP Service 临时转发到 `127.0.0.1:18931`，执行 JSON-RPC 请求，在
Patch 测试前后重置一次性 Fixture，并通过 Shell Trap 关闭 Port-forward。

故障测试只会把 `forge-workspace-mcp` 缩容到零，验证 Service 没有 Ready Endpoint，
随后恢复一个 Replica 并等待 Rollout 完成。

## 证据

每次运行都会把证据保存到：

```text
.evidence/<UTC timestamp>/
├── transcript.log
├── inference-policy.json
├── coordinator-tool-policy.json
├── specialist-tool-policy.json
├── mcp-server.json
├── compiled-tool-profile.json
├── compiled-inference-profile.json
├── mcp-tools-list.json
├── mcp-runtime-tools.txt
├── mcp-declared-tools.txt
├── denied-traversal.json
├── denied-unknown-tool.json
├── denied-test.json
├── denied-ci-patch.json
├── allowed-patch.json
├── allowed-test.json
├── allowed-diff.json
├── budget-denial.json
├── controller.log
└── router.log
```

证据目录已通过 Git Ignore 排除。

## 单独运行

```bash
make inspect
make clean
```

`make clean` 会恢复一个 Ready 的 Workspace MCP Replica，并保留本地证据。

## 平台支持

已经验证的环境是 macOS arm64。平台检测继承自
[`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01)，
同时支持 macOS amd64、
Linux amd64，以及通过 Ubuntu WSL2 运行的 Windows amd64。
## Sandbox Escape 递进：工具参数仍是不可信输入

`code/03` 保护平台契约，本阶段保护每一次跨越工具边界的请求。Live MCP 测试现在会
读取扩展后的恶意 README，并尝试写入 VS Code、Agent、Git Hook 与 Package 配置
路径。所有攻击动作都必须返回 Tool Error，而批准的 `src/` Patch 与
`format-user` 测试仍应成功。

本阶段的 KARS 优势是：即使 OpenClaw 或其他 Runtime 决定请求某项能力，Router 与
`ToolPolicy` 仍可独立拒绝。Tool Authority 不依赖某个 Framework 的 Prompt 或
Approval UI。

因此 `make test` 不只验证 Tool Name，也验证参数。Allowlist 中的编辑工具并不代表
“可以编辑任何位置”，仓库数据也不能借此创建 Trust Handoff Artifact。
