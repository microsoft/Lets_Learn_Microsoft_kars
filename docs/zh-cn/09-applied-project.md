# 9. 应用项目：在 AKS 发布 Issue-to-PR Pilot

> **交付阶段：** 客户发布
> **起点：** OpenClaw Intake、第 6 章 MAF 模式、第 7 章安全控制，以及第 8
> 章 AKS 环境
> **可执行项目：** [`code/08`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/08)

## 一切从 OpenClaw 开始

应用项目仍从 Fabrikam Requirement 开始：

```text
修复 FAB-482：请求没有可选 customer note 时返回 500。
执行最小安全修改、运行目标测试，并停在人工评审之前。
```

OpenClaw Intake 没有 Source Write Authority。Builder 开始前，它必须验证 Issue、
Acceptance Criteria、Customer 与固定 Revision：

```text
OPENCLAW_INTAKE
  -> PIN_REQUIREMENT_AND_REVISION
  -> MAF_BUILDER_INSPECT
  -> PROPOSE_MINIMAL_PATCH
  -> RUN_TARGETED_TESTS
  -> CREATE_DIGEST_PINNED_HANDOFF
  -> INDEPENDENT_REVIEW
  -> STOP_FOR_HUMAN_PR_APPROVAL
```

Pilot 不会 Merge 或部署 Source。它只生成 Patch、目标测试 Evidence 和按 Digest
固定的 Handoff，交给独立 Reviewer 与人类批准。

## [`code/08`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/08) 增加的能力

项目把前面实验组合成一个可运维 Release Unit：

- 非 root `MicrosoftAgentFramework/python` Runtime；
- 真实 MAF `Agent`、`OpenAIChatClient` 与唯一一个使用 `@tool` 装饰的
  `inspect_release_contract` Function；
- kars MAF Adapter 把 MAF Client 固定到 Local Router，再调用 GitHub Copilot
  GPT-5.6-Sol；
- 独立 `InferencePolicy`，包含单请求与每日 Token Budget；
- 只允许具名工具的 `ToolPolicy`，不包含 Shell、Merge 或 Deployment；
- Strict Egress 与第 7 章 Execution Guard；
- Task Concurrency 与每日 Task Limit；
- Per-customer Usage Report；
- Application 与 Router Tamper-evident Audit；
- 使用 `spec.suspended`、不删除 CR/Evidence 的 Kill Switch；
- Digest-based Rollback；
- 内部 Development MCP 声明与 kars Eval 声明。

GitHub Copilot Provider Credential 仍只在 Router Path 中。Agent Contract 检查确认
Agent Container 不包含 Copilot 或 GitHub Token/Key Environment Variable。

```text
OpenClaw Intake
  -> MAF Agent
  -> inspect_release_contract @tool
  -> kars MAF Python Adapter
  -> 127.0.0.1:8443 kars Router
  -> GitHub Copilot GPT-5.6-Sol
```

应用代码中不存在直接访问 `/v1/responses` 的 `httpx` 调用。
MAF Agent 设置 `store: false`，让 Responses API Function Loop 内联 Tool
History，避免 kars `v0.1.25` 在 Tool 执行后的 Model Turn 中不支持
`previous_response_id` 的兼容性问题。一个范围严格的 MAF Client 兼容子类会在
内联重放前移除 Provider 过长的加密 Function Call Item ID，同时保留标准
`call_id`。

## Azure 参数仍由用户选填

只有需要覆盖默认值时才复制：

```bash
cd code/08
cp config/azure.env.example config/azure.env
```

| 参数 | 值 | 含义 |
| --- | --- | --- |
| `AZURE_RESOURCE_GROUP` | 必填 | 你的现有 Azure Resource Group |
| `AKS_NAME` | 必填 | 你的现有 AKS Cluster |
| `KARS_ACR_NAME` | 必填 | 你的现有 ACR |
| `AZURE_LOCATION` | 空 | 与现有 AKS Location 比对 |
| `KARS_SANDBOX_NAME` | `fabrikam-release-pilot` | 新 Pilot Sandbox |
| `GITHUB_COPILOT_MODEL` | `gpt-5.6-sol` | 指定模型 |
| `SUPPORT_OWNER` | `forge-operations` | 运维负责人 |
| `TASK_CONCURRENCY_LIMIT` | `2` | 并发 Task 上限 |
| `DAILY_TASK_LIMIT` | `20` | 应用每日 Task 上限 |
| `DEPLOY_AZURE` | `false` | 明确 Azure 变更开关 |

请在 Git Ignore 的 `config/azure.env` 中填写必填值。部署会复用现有 Cluster 的
Location；如果选填的 `AZURE_LOCATION` 与现有 AKS 不一致，脚本会拒绝。教程不会
公开真实 Azure Resource 名称，也不会把它们作为默认值。

## 运行安全验证

```bash
cd code/08
make test
```

它会通过 Microsoft Package Feed Proxy 安装 Python Package、运行控制测试、渲染
kars Resource，并使用 Live CRD Server-side Dry-run 验证，不修改 Azure。

三个生态统一使用 Microsoft Source：

```text
npm   https://packagefeedproxy.microsoft.io/npm/
PyPI  https://packagefeedproxy.microsoft.io/pypi/simple/
NuGet https://packagefeedproxy.microsoft.io/nuget/v3/index.json
```

## 部署到现有 AKS

在 Git Ignore 的配置中设置：

```text
DEPLOY_AZURE=true
```

然后运行：

```bash
make deploy
```

脚本不会重建 AKS。它会：

1. 验证目标 AKS 与 kars Controller 已 Ready；
2. 使用 ACR Tasks 和 `--platform linux/amd64` 构建 `pilot_agent`；
3. 解析 SHA-256 Image Digest；
4. 把 kars Controller 的 `MAF_RUNTIME_IMAGE` 固定到该 Digest；
5. 渲染并执行 First-class MAF Sandbox 的 Server-side Validation；
6. 部署 Pilot、MCP Metadata 和 Eval 声明；
7. 运行一个真实成功流程与三个拒绝流程。

kars `v0.1.25` 会把 `agentCode.oci` 传入 Runtime Plan，但还不会在 Pod 中实际生成
Code Mount。因此本实验扩展官方 kars MAF Python Image，把应用烘焙到
`/opt/fabrikam-agent`，启动时由 UID 1000 复制到 Writable `/sandbox/agent`
Volume。这是当前版本的 Packaging Workaround；Sandbox Runtime 仍是
`MicrosoftAgentFramework`，不是 BYO。

## 调用 Azure Pilot

Pilot 不公开公网 Endpoint。先创建已认证 Tunnel：

```bash
kubectl -n kars-fabrikam-release-pilot port-forward \
  deployment/fabrikam-release-pilot 18088:8080
```

OpenClaw Intake：

```bash
curl -sS -H 'content-type: application/json' \
  --data '{
    "issue_id":"FAB-482",
    "customer":"fabrikam",
    "requirement":"Missing optional customer note must not return 500"
  }' \
  http://127.0.0.1:18088/intake | jq
```

运行受治理的 Builder：

```bash
curl -sS -H 'content-type: application/json' \
  --data '{
    "issue_id":"FAB-482",
    "customer":"fabrikam",
    "scenario":"normal"
  }' \
  http://127.0.0.1:18088/run | jq
```

已验证的 Response 包含：

```text
KARS_APPLIED_PROJECT_GPT_5_6_SOL_OK FAB-482 READY_FOR_HUMAN_REVIEW
```

Response 还包含 Patch、目标测试和 Handoff Envelope 各自的 SHA-256 Digest，
并明确返回：

```json
{
  "mafAgent": "FabrikamReleaseBuilder",
  "mafTool": "inspect_release_contract",
  "mafToolCalls": 1
}
```

## 执行负向控制

`make verify` 执行：

| 场景 | 预期结果 |
| --- | --- |
| 正常 FAB-482 Workflow | GPT-5.6-Sol Patch Evidence；停在人工评审 |
| `unknown_tool` | HTTP 403；Shell 不在批准 Tool 中 |
| `unknown_host` | HTTP 403；未知 Package Host 被拒绝 |
| `builder_self_approve` | HTTP 403；Separation of Duties 生效 |

Runtime 还为重复 Repair Loop、Development MCP 不可用、Reviewer 修改 Source 和
不可信 Peer Draft 定义了明确失败结果。

## 已验证的 Azure 结果

真实运行已在配置的现有 AKS Cluster 完成：

- `fabrikam-release-pilot` 在 amd64 `clawpool` 中为 `Running`；
- Sandbox 报告 `MicrosoftAgentFramework/python`；
- ACR Image 按 SHA-256 Digest 固定；
- MAF Builder 恰好调用一次受限 `@tool`；
- GPT-5.6-Sol 返回预期 Release Marker；
- Application Audit Chain 与 Router Audit Chain 均为 Valid；
- Agent 不包含 Provider Credential Environment Variable；
- Per-customer Usage Report 包含一条 Fabrikam Task；
- InferencePolicy Compiled/Loaded Digest 一致，Router 报告
  `RouterEnforcing`；
- OpenClaw Intake、一个允许 Workflow 与三个拒绝 Workflow 全部通过；
- Suspension、Evidence 保留、Resume 和恢复后验证全部通过。

## Kill Switch 与 Rollback

停止新任务但不删除 kars Resource：

```bash
make suspend
```

恢复：

```bash
make resume
make verify
```

Rollback 必须明确填写之前批准的 ACR Digest：

```text
ROLLBACK_IMAGE=<acr>.azurecr.io/fabrikam-release-pilot@sha256:<digest>
```

```bash
make rollback
make verify
```

Ownership 与 Evidence Procedure 请参阅
[`code/08/RUNBOOK.md`](https://github.com/kinfey/LetsLearnMicrosoftKars/blob/main/code/08/RUNBOOK.md)。

## KarsEval 兼容性 Evidence

`KarsEval` CR 与 `jailbreak-baseline` Corpus 可以成功解析，但上游 kars
`v0.1.25` 生成的 Eval Runner Job 被当前 AKS Namespace 的 `restricted` Pod
Security 拒绝，因为 Runner 缺少：

- `runAsNonRoot: true`；
- `allowPrivilegeEscalation: false`；
- `capabilities.drop: ["ALL"]`；
- RuntimeDefault 或 Localhost Seccomp Profile。

失败 Job 已暂停，没有为了运行 Eval 而降低 Namespace Security。可执行的
Application Evaluation Matrix 仍全部通过。在把 KarsEval Runner 作为 Production
Promotion Gate 前，需要先解决这个上游兼容性问题。

## 平台支持

Operator Command 从 macOS arm64 执行。ACR Tasks 明确构建 Linux amd64，Azure
Pod 也运行在 amd64 Node。macOS amd64 与 Linux amd64 使用相同脚本。Windows
amd64 请在 Ubuntu WSL2 中运行，并把 Azure、Kubernetes 与 kars CLI 全部安装在
WSL2 内。

## 官方参考

- [kars](https://github.com/Azure/kars)
- [kars Examples](https://github.com/Azure/kars/tree/main/examples)
- [Microsoft Agent Framework GitHub Copilot Samples](https://github.com/microsoft/agent-framework/tree/main/python/samples/02-agents/providers/github_copilot)
- [Microsoft Agent Framework Build Your Own Claw](https://github.com/microsoft/agent-framework/tree/main/python/samples/02-agents/harness/build_your_own_claw)
## 最终 Sandbox Escape 门禁

应用项目汇总完整递进链。`code/08` 会明确拒绝 Self-modified Authority、Symlink
Escape、Host Trust Handoff 与 DNS Egress 场景。成功的 Release Handoff 同时包含
Patch、Test 与 Artifact Manifest Digest，并且仍停止在 Human Approval。

最终的 KARS 优势是 Release Safety 不会嵌入某一个 Agent Implementation。项目可以
替换 Builder Runtime，同时保留相同的外部 Policy、Credential、Egress、Audit、
Suspend 与 Rollback Contract。

```bash
cd code/08
make test
make validate
```

发布门禁现在同时要求业务行为正确和 Containment 完整。只有测试通过不能作为发布证据。
