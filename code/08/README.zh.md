# 第 9 章实验：OpenClaw-first MAF 应用发布项目

本实验把第 6 章 MAF 模式、第 7 章安全控制和第 8 章 AKS Promotion 组合成可由
其他运维人员复现的 Issue-to-PR Pilot，并部署到现有 AKS：

```text
OpenClaw Intake
  -> MAF Agent + OpenAIChatClient + inspect_release_contract @tool
  -> kars MAF Adapter
  -> Local kars Router
  -> GitHub Copilot GPT-5.6-Sol
```

应用代码不直接调用 Router HTTP API。kars Adapter 把 MAF OpenAI Client 固定到
`127.0.0.1:8443`，Provider Credential 仍只存在于 Router Path。MAF Agent 设置
`store: false`，让 Responses API Function Loop 内联 Tool History，而不是发送
kars `v0.1.25` GitHub Copilot Adapter 不支持的 `previous_response_id` 字段。一个
小型 MAF Client 兼容子类还会在内联重放前移除 Provider 过长的加密 Function
Call Item ID，同时保留标准 `call_id`。

安全本地验证：

```bash
cd code/08
make test
```

部署到现有环境：

```bash
cp config/azure.env.example config/azure.env
# 填写 AZURE_RESOURCE_GROUP、AKS_NAME 与 KARS_ACR_NAME。
# 然后设置 DEPLOY_AZURE=true。
make deploy
```

Azure Resource 名称是用户必填参数，Repository 不会绑定或公开真实部署名称。
脚本会验证现有 AKS 的实际 Location。ACR Task 明确构建 Linux amd64，并按
Digest 选择 MAF Runtime。

kars `v0.1.25` 已在 CRD/Runtime Plan 中提供 `agentCode.oci`，但还没有把该 Code
Mount 真正生成到 Pod。本实验因此扩展官方 kars MAF Python Image，把应用烘焙到
`/opt/fabrikam-agent`，启动时由 UID 1000 复制到 Writable `/sandbox/agent`
Volume，并通过 Controller 的 `MAF_RUNTIME_IMAGE` 指向 Digest。Sandbox 仍是正式
的 `MicrosoftAgentFramework/python` Runtime，不是 BYO。

`make verify` 会运行 OpenClaw Intake、一个真实 GPT-5.6-Sol 成功流程、验证恰好
一次受限 MAF Tool Call，以及 Shell/未知工具、未知 Egress 与 Builder
Self-approval 三个拒绝场景。暂停、Evidence 保留和 Rollback 请参阅
`RUNBOOK.md`。

Azure 部署已在 amd64 `clawpool` 验证。Application 与 Router Audit Chain 通过，
InferencePolicy Compiled/Loaded Digest 已收敛。`KarsEval` 声明可以解析 Corpus，
但上游 `v0.1.25` Runner Job 因生成的 Pod 缺少 Restricted Security Context 而
被 AKS Restricted Pod Security 阻止。失败 Job 已暂停，没有降低 Namespace
Security。
## 完整 Sandbox Escape 发布门禁

最终阶段汇总前面所有控制。Release API 会明确拒绝
`self_modify_authority`、`symlink_escape`、`host_trust_handoff` 与
`dns_egress` 场景。成功路径只接受规范化的 `src/` Artifact、拒绝 Symlink，并把
Artifact Manifest Digest 加入 Builder-to-Reviewer Handoff。

完整场景中的 KARS 优势是一致性：从本地 Validation 到 AKS Release，同一套声明式
Runtime、Inference、Tool、Network、Identity、Suspend 与 Audit 边界持续生效。

运行 `make test` 执行本地门禁，运行 `make validate` 检查 Render 后的 KARS
Contract。测试通过并不等于可以发布；Authority、Artifact、Egress、角色分离、
Audit、Suspend 与 Rollback 边界必须同时保持完整。
