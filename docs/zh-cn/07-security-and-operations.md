# 7. 安全与运维：限制、观测并恢复 Forge

> **交付阶段：** 运维第 6 章的 BYO 生产候选
> **起点：** OpenClaw Forge 行为，现在运行于 kars BYO Workload，并使用
> GitHub Copilot GPT-5.6-Sol
> **可执行实验：** [`code/06`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/06)

## 一切仍然从 OpenClaw 开始

第 1 章定义 OpenClaw Issue-to-Patch Workflow；第 2 到第 5 章依次限制 Filesystem、
Kubernetes API、Tool 与 Policy；第 6 章保留相同 Forge Contract，同时加入
Host-side Microsoft Agent Framework Canary 和 Cluster 内 kars BYO Runtime。

第 7 章直接运维这套真实 Runtime：

```text
OpenClaw FORMAT-482 Workflow
    -> Application Repair Guard
    -> BYO Agent，UID 1000，无 Provider Credential
    -> Localhost kars Router，UID 1001
    -> GitHub Copilot GPT-5.6-Sol
    -> Policy Decision、Audit Chain、Metrics、Recovery Evidence
```

目标不是证明 Agent 永不失败，而是确保失败的 Agent 会停止、留下证据、不越过权限
边界，并通过明确的 Procedure 恢复。

## 运行真实实验

先完成 [`code/05`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/05)，然后执行：

```bash
cd code/06
make test
```

完整运行已经在 macOS arm64 验证。脚本也支持 macOS amd64 和 Linux amd64。
Windows amd64 请使用启用 Docker Desktop WSL Integration 的 Ubuntu WSL2。

实验强制 npm、PyPI、NuGet 使用 Microsoft Package Feed Proxy，复用已认证的
GitHub Copilot CLI，并固定模型为 `gpt-5.6-sol`。

## 在应用层停止 Repair Loop

Platform Budget 可以限制成本，但不能判断两个 Patch 是否等价，也不能判断任务是否
超过业务 Deadline。
[`code/06/operations/repair_guard.py`](https://github.com/kinfey/LetsLearnMicrosoftKars/blob/main/code/06/operations/repair_guard.py)
的 `RepairGuard` 会在以下
情况返回明确的 Human Escalation Decision：

- 同一个 Patch Digest 出现两次；
- 超过配置的 Repair Attempt；
- 新尝试开始前任务已到 Deadline。

确定性测试会在任何 Live Model Call 之前运行。源自 OpenClaw 的 Workflow 仍然结束
于 `STOP_FOR_HUMAN_REVIEW`，不会加入 Merge 或 Deploy Action。

## 改变 Workload 前先收集证据

Incident Inventory 会记录：

- `KarsSandbox` 与 `InferencePolicy` 状态；
- 脱敏 Deployment Security Context 和 Environment Variable 名称；
- Pod Image ID、UID、Readiness 与 Restart Count；
- Namespace Event；
- Admission Policy；
- Least-privilege RBAC 结果。

Live Sandbox ServiceAccount 返回：

```json
{
  "canGetSecrets": "no",
  "canCreatePods": "no"
}
```

Evidence 不包含 Secret Value。

## 补齐 BYO Exec Policy 缺口

已安装的上游 `kars-sandbox-exec-ban` 匹配 OpenClaw Container 名称
`openclaw`。第 6 章 BYO Runtime 使用 Container 名称 `agent`，因此最初无副作用的
`kubectl exec ... -- true` 可以成功。

[`code/06/manifests/byo-agent-exec-ban.yaml`](https://github.com/kinfey/LetsLearnMicrosoftKars/blob/main/code/06/manifests/byo-agent-exec-ban.yaml)
为标记
`kars.azure.com/isolated=strict` 的 Namespace 中 `agent` Container 加入同等的
Fail-closed 控制。没有 Break-glass Label 时，API Server 返回：

```text
ValidatingAdmissionPolicy 'kars-byo-agent-exec-ban' ... denied request:
exec/attach into the BYO agent runtime is denied
```

这说明安全测试必须针对真实 Runtime Shape，不能只检查最初的 OpenClaw Container
名称。

## 验证 Mediated Path

Boundary Phase 证明：

- Runtime Contract 仍然指定 `gpt-5.6-sol`；
- Agent Environment 中没有 Provider Credential 名称；
- Agent 直接访问 Internet 会 Timeout；
- 对 BYO Agent 的 Exec/Attach 被拒绝；
- 正常请求仍通过 `127.0.0.1:8443` 成功。

Router 提供以下运维证据：

```bash
curl http://127.0.0.1:18444/agt/audit
curl http://127.0.0.1:18444/agt/audit/verify
curl http://127.0.0.1:18444/agt/status
curl http://127.0.0.1:18444/metrics
```

完成的运行返回 `integrity: valid`、`Hash chain verified`、Native
Governance、Loaded Policy，以及 kars Audit/Inference Metrics。

## 演练 Token Budget Incident

实验临时修改：

```yaml
spec:
  tokenBudget:
    perRequestTokens: 16
```

当前 Router Fast-fail 实现会在 Chat Completions Path 检查请求声明的输出上限。
带有 `max_tokens: 17` 的请求返回：

```json
{
  "error": {
    "message": "Requested max_tokens=17 exceeds InferencePolicy tokenBudget.perRequestTokens=16",
    "type": "token_budget_exceeded",
    "code": "per_request_tokens_exceeded"
  }
}
```

HTTP Status 是 429。实验随后恢复 `1024`，并通过 BYO 应用的
`/v1/responses` Path 再次运行 GPT-5.6-Sol。

这是两个独立且已验证的结论；本实验不会声称 Responses Route 有完全相同的声明
Token Preflight Enforcement。

## 把 Policy Activation 当作 Rollout

实验中生成的 ConfigMap 已更新，但运行中的 Router Pod 继续使用旧 Mounted
Profile，因此 Loaded Digest 在 Pod 重启前不会收敛。

Runbook 执行：

```bash
kubectl -n kars-forge-byo-copilot-claw rollout restart \
  deployment/forge-byo-copilot-claw
kubectl -n kars-forge-byo-copilot-claw rollout status \
  deployment/forge-byo-copilot-claw
```

随后等待：

- Policy Generation 等于 `status.observedGeneration`；
- `compiledDigest` 等于 `loadedDigest`；
- Phase 是 `Ready`。

恢复原始 Policy 时使用相同 Procedure；即使后续步骤失败，Exit Trap 也会执行恢复与
Rollout。

## 从 Pod 丢失中恢复

收集 Volatile Evidence 后，实验只按准确名称删除当前 Pod。Deployment 创建具有新
UID 的 Replacement 并恢复 Ready。Port-forward 重新建立后，BYO Endpoint 再次调用
GPT-5.6-Sol，Router 验证一条新的 Audit Chain。

这证明的是 Pod Self-healing，不代表已经验证 Controller Upgrade、Cluster Restore
或跨区域 Disaster Recovery；这些场景需要独立 Runbook 和测试。

## Audit Integrity 不等于 Audit Persistence

Pod 替换前 Router 有 2 条 Audit Entry，替换后立即变成 0：

```json
{
  "beforeRestart": 2,
  "immediatelyAfterRestart": 0,
  "persisted": false
}
```

下一次请求启动新的 Chain，`/agt/audit/verify` 再次返回 Valid。这证明当前
In-memory Chain 生命周期内可以检测篡改，但不能在 Pod 丢失后保存 Incident
History。

生产运维必须在删除可疑 Pod 前，把 Audit Record 持续输出到独立控制的 Durable
Backend。Chain-head Signing 与更强 Non-repudiation 也必须结合 kars Maturity
文档评估。

## 记录 Release，而不只记录 Response

最终记录包含：

| 字段 | 已验证值 |
| --- | --- |
| kars | `0.1.25` |
| Model | `gpt-5.6-sol` |
| Runtime | `BYO` |
| Repository | 准确 Git Commit |
| Workload | 准确 Image Digest |
| Policy | 准确 Loaded Digest |

Agent 说“测试通过”不是 Release Evidence。必须关联 Response、Policy Decision、
Runtime Identity、Image 和 Source Revision。

## Provider Telemetry 限制

GitHub Copilot 会应用 Provider-side Safety Control，但本实验使用的 Router Path
不会收到 Azure AI Foundry 风格、具有相同 Category 与 Severity 可见性的
`prompt_filter_results`。运维 Dashboard 必须展示所选 Provider 实际提供的
Telemetry，不能假设所有 Provider 一致。

## 生产 Checklist

- 除 Platform Budget 外，保留应用层 Attempt、Deadline 与 Duplicate Guard。
- 新 Runtime 改变 Container 名称或 Resource Shape 时，扩展 Admission Control。
- 执行破坏性响应前，把 Audit 与 Metrics 外送到 Workload 之外。
- 针对 Denial Pattern 和 Budget Exhaustion 告警，而不是对每次成功拒绝告警。
- 使用 Workload Identity 或 Router-owned Credential，不把 Credential 交给 Agent。
- 固定 kars、Image、Model 与 Policy Artifact。
- 分别测试 Policy Activation、Rollback、Pod Recovery、Upgrade 与 Restore。
- Merge、Release 或 Deploy 前继续保留 Human Approval。

## 完成定义

当源自 OpenClaw 的 Workflow 能停止错误 Repair Loop，真实 BYO Runtime 不越过
Credential、Network 与 Exec Boundary，超预算流量返回机器可验证的 Denial，
Audit Integrity 已检查且没有与 Persistence 混淆，Workload 使用新 Pod UID
恢复，GPT-5.6-Sol 在恢复后成功，并且 Release Record 固定准确 Software 与 Policy
输入时，安全与运维测试才算完成。

## 官方参考

- [kars Security](https://github.com/Azure/kars/blob/main/docs/security.md)
- [kars Maturity](https://github.com/Azure/kars/blob/main/docs/maturity.md)
- [kars Operations](https://github.com/Azure/kars/tree/main/docs/operations)
- [Secret Rotation](https://github.com/Azure/kars/blob/main/docs/operations/secret-rotation.md)
- [Upgrades](https://github.com/Azure/kars/blob/main/docs/operations/upgrades.md)
- [Chaos Tier](https://github.com/Azure/kars/blob/main/docs/operations/chaos-tier.md)
- [SRE Runbook](https://github.com/Azure/kars/blob/main/docs/runbooks/sre.md)
- [Microsoft Agent Framework GitHub Copilot Samples](https://github.com/microsoft/agent-framework/tree/main/python/samples/02-agents/providers/github_copilot)
- [Microsoft Agent Framework Build Your Own Claw](https://github.com/microsoft/agent-framework/tree/main/python/samples/02-agents/harness/build_your_own_claw)
## Sandbox Escape 检查点：调查隐蔽通道

Incident Response 必须区分 HTTPS、DNS、Metadata Service、Local Daemon 与 Exec
尝试。`code/06` 会把每一种 Denied Channel 写入 Hash-linked Audit Chain，并拒绝
没有 Incident ID 的 Break-glass Record。

KARS 为不同 Runtime 提供共同的 Control 与 Evidence Plane：Controller Condition、
Router Denial、Policy Budget、Admission Decision 与 Workload Recovery 可以作为同一
事件序列进行调查。

```bash
cd code/06
make unit
make test
```

这样可以避免在实际尝试了其他 Egress Channel 或 Operator Bypass 时，只留下无法证明
的“网络已经阻止”结论。
