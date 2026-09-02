# kars 安全与运维实验

[English](README.md) | [简体中文](README.zh.md)

本实验从
[`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01)
的 OpenClaw Forge Workflow 开始，并直接运维
[`code/05`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/05)
已部署的 GPT-5.6-Sol kars BYO Runtime：

```text
OpenClaw Issue-to-Patch Contract
    -> 受限 Repair Loop
    -> kars BYO Agent（UID 1000）
    -> Localhost Inference Router（UID 1001）
    -> GitHub Copilot GPT-5.6-Sol
    -> Audit、Policy、Metrics、Recovery、Release Evidence
```

实验不会模拟第二套应用。它会修改真实 Policy、替换真实
`forge-byo-copilot-claw` Pod、验证恢复，并把原始 1024 Token 限额恢复。

## 实验要证明什么

- 确定性的 Repair Guard 会在重复等价 Patch、超过尝试次数或任务过期时停止，
  不再发起下一次模型调用。
- Host-side Microsoft Agent Framework `GitHubCopilotAgent` Canary 仍然调用
  GPT-5.6-Sol。
- Sandbox ServiceAccount 不能读取 Secret，也不能创建 Pod。
- Agent Environment 中不存在 GitHub/Copilot Provider Credential 名称。
- Agent 直接出口仍被拒绝。
- 上游 Exec Admission Policy 针对名为 `openclaw` 的 Container；
  [`code/06`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/06)
  为 BYO `agent` Container 安装补充 Policy，并证明 `kubectl exec` 被拒绝。
- `/agt/audit/verify` 返回有效 Router Hash Chain，`/agt/status` 返回 Native
  Governance 和已加载 Policy。
- 临时 16 Token Policy 会拒绝声明 `max_tokens: 17` 的 Chat Completions
  请求，返回 HTTP 429 和 `per_request_tokens_exceeded`。
- 当前环境中，运行中的 Router Pod 没有自动刷新生成的 Policy ConfigMap。
  因此 Incident Procedure 在应用临时 Policy 和恢复 Policy 后都会执行明确的
  Deployment Rollout。
- 删除当前 Pod 后，Deployment 创建新的 Ready Pod，GPT-5.6-Sol 通过
  `/v1/responses` 再次成功。
- Pod 替换后，本地 Router Audit 数量立即从 2 变为 0。下一次请求会启动新的
  Valid Chain，但生产历史必须外送到独立 Audit Backend。
- Release Record 固定 Repository Commit、kars Version、Model、Runtime、
  Image ID 和 Loaded Policy Digest。

## Microsoft Package Source

实验会应用并检查：

- npm：`https://packagefeedproxy.microsoft.io/npm/`
- PyPI：`https://packagefeedproxy.microsoft.io/pypi/simple/`
- NuGet：`https://packagefeedproxy.microsoft.io/nuget/v3/index.json`

运行退出时会恢复从
[`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01)
继承的 Source Rewrite。

## 前置条件

- 先完成 [`code/05`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/05)，
  `forge-byo-copilot-claw` 必须处于
  `Running`。
- Docker Desktop、kind、kubectl、jq、curl、Python 3.11+ 和 Node.js 22。
- GitHub Copilot CLI 已安装并认证。
- kars Provider 是 `github-copilot`，并可使用 `gpt-5.6-sol`。

## 运行

```bash
cd code/06
make test
```

测试会执行真实 Pod Rollout，并短暂把
`forge-byo-inference.spec.tokenBudget.perRequestTokens` 从 `1024` 改为
`16`。如果后续 Assertion 失败，Exit Trap 也会恢复原始值。

成功输出最后是：

```text
All security and operations checks passed.
Evidence: .../code/06/.evidence/<UTC timestamp>
```

可单独执行：

```bash
make unit
make inspect
make clean
```

`make clean` 会删除
[`code/06`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/06)
的 BYO Exec Admission Guard，并确认
[`code/05`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/05)
Runtime 和原始 Inference Budget 健康；它不会删除
[`code/05`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/05)
Sandbox。

## Incident 顺序

1. 检查 Microsoft Source 和确定性 Repair Guard Unit Test。
2. 运行 MAF GitHub Copilot GPT-5.6-Sol Canary。
3. 安装 BYO `agent` Exec/Attach Admission Guard。
4. 收集脱敏 Sandbox、Policy、Deployment、Pod、Event 与 RBAC 数据。
5. 验证 Credential Isolation、Direct-Egress Denial 和 Exec Denial。
6. 生成真实 GPT-5.6-Sol Audit Record，并收集 Audit、Status 与 Metrics。
7. 应用临时 Token Budget、滚动 Pod、要求 HTTP 429、恢复 Policy、再次
   Rollout，并执行模型 Smoke Test。
8. 按准确名称删除当前 Pod，等待 Deployment Recovery。
9. 比较 Pod 替换前后的 Audit 数量，并启动新的 Verified Chain。
10. 写入 Release Record。

## 证据

每次运行会在 `.evidence/<UTC timestamp>/` 保存：

```text
transcript.log
host-copilot-agent.json
sandbox-rbac.json
exec-admission-policies.json
exec-denial.txt
baseline-model-response.json
audit-before-restart.json
audit-verify-before-restart.json
governance-status-before-restart.json
metrics-before-restart.txt
budget-denial.json
restart.json
audit-persistence.json
audit-verify-after-restart.json
post-restart-model-response.json
release-record.json
```

不会导出 Secret Value；Deployment Evidence 只保留 Environment Variable
名称。

## 运维边界

- Repair Guard 和 Router Token Budget 解决不同问题：应用停止错误循环，平台限制
  故障成本。
- 已验证的 Fast-fail Budget 路径是 `/v1/chat/completions`，字段为
  `max_tokens` 或 `max_completion_tokens`。BYO 应用 Smoke Path 使用
  `/v1/responses`；本实验不会声称两个 Route 有相同的 Preflight Enforcement。
- 有效 In-memory Audit Chain 证明当前生命周期内可以发现篡改，不代表 Pod 丢失后
  仍可保留历史。
- 实验验证的是 Pod Self-healing，不是完整 kars Controller Upgrade 或 Database
  Restore。
- GitHub Copilot 有 Provider-side Safety Control，但此 Router 路径不会暴露
  Azure AI Foundry 风格的 `prompt_filter_results`。

## 平台支持

完整运行已经在 macOS arm64 验证。继承的脚本也支持 macOS amd64 和 Linux amd64。
Windows amd64 请在 Ubuntu WSL2 中运行，并启用 Docker Desktop WSL Integration；
在 WSL2 内使用 Linux Path 与工具。

## 参考

- [kars Security](https://github.com/Azure/kars/blob/main/docs/security.md)
- [kars Maturity](https://github.com/Azure/kars/blob/main/docs/maturity.md)
- [kars Operations](https://github.com/Azure/kars/tree/main/docs/operations)
- [kars SRE Runbook](https://github.com/Azure/kars/blob/main/docs/runbooks/sre.md)
- [Microsoft Agent Framework GitHub Copilot Samples](https://github.com/microsoft/agent-framework/tree/main/python/samples/02-agents/providers/github_copilot)
- [Microsoft Agent Framework Build Your Own Claw Samples](https://github.com/microsoft/agent-framework/tree/main/python/samples/02-agents/harness/build_your_own_claw)
## Sandbox Escape 递进：调查每一种出口通道

即使 HTTP 请求没有成功，Containment Failure 仍然属于安全事件。
`boundary_denial` 会把 HTTPS、DNS、Metadata Service、Local Daemon 与 Exec 尝试
写入防篡改 Audit Chain。任何 Break-glass Event 如果没有 Incident ID 都是无效的。

本阶段的 KARS 优势是可以在平台层关联 Runtime Denial、Controller State、Router
Decision、Budget 与 Recovery，而不是从每种 Agent Framework 的不兼容日志中重新
拼接事件。

运行 `make unit` 查看确定性的 Channel/Audit 测试，再运行 `make test` 检查真实
Exec Admission 与 Direct Egress 边界。运维结论不能只写“网络被阻止”，而必须说明
尝试了哪个 Channel、由哪一层拒绝。
