# 4. 平台：把 Forge 变成 Kubernetes API 契约

> **交付阶段：** 共享开发平台
> **新问题：** 每位工程师和 CI Job 如何复现并评审同一个 Forge 环境？
> **交付物：** 版本化的 `KarsSandbox`、`InferencePolicy` 契约与可执行生命周期证据。
> **配套实验：** [`code/03`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/03)

## 用期望状态取代终端记忆

[`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01)
已经证明 OpenClaw 可以完成受约束的 Issue-to-Patch 工作流，
[`code/02`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/02)
进一步打开生成的 Pod 并测试隔离边界。但这些结果都不应依赖某个人记得 Maya
输入过哪些命令。

共享平台需要可评审的 API 契约：

- Git 保存预期的 Workload 与权限；
- Kubernetes 验证 Object Shape；
- kars 协调请求状态；
- `status.conditions` 解释请求是否成功；
- `metadata.generation` 与 `status.observedGeneration` 显示 Controller 是否已经
  处理最新变更。

[`code/03`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/03)
会在正在运行的 `kars-dev` 集群中执行完整生命周期。

## 使用准确的 kars API 标识

Kubernetes API 名称区分大小写。已经安装的 CRD 是：

```text
apiVersion: kars.azure.com/v1alpha1
kind: KarsSandbox
```

之前出现的 `karsSandbox` 并不是 Alias。Kind 大小写错误时，Server-side Validation
会返回 `no matches for kind`。

不要假设某个字段一定存在，应直接检查当前集群 Schema：

```bash
kubectl explain karssandbox.spec --recursive
kubectl explain inferencepolicy.spec --recursive
kubectl get crd karssandboxes.kars.azure.com -o yaml
```

实验会把三个输出全部保存到集群外部。

## 分离 Workload 与推理权限

最小可部署 kars Agent 包含：

1. 同一个 Namespace 中的 `InferencePolicy`。
2. 一个 `KarsSandbox`，其必需字段 `spec.inferenceRef.name` 指向该 Policy。

系统不存在不受约束的 Inline Inference Fallback。Reference 只在 Sandbox 所在
Namespace 中解析。

[`code/03/manifests/contract-v1.yaml`](https://github.com/kinfey/LetsLearnMicrosoftKars/blob/main/code/03/manifests/contract-v1.yaml)
包含第一版契约：

```yaml
apiVersion: kars.azure.com/v1alpha1
kind: InferencePolicy
metadata:
  name: forge-contract-inference
  namespace: kars-system
spec:
  appliesTo:
    sandboxName: forge-contract
  modelPreference:
    primary:
      provider: azure-openai
      deployment: __MODEL__
  tokenBudget:
    perRequestTokens: 1024
    dailyTokens: 4096
---
apiVersion: kars.azure.com/v1alpha1
kind: KarsSandbox
metadata:
  name: forge-contract
  namespace: kars-system
spec:
  runtime:
    kind: OpenClaw
    openclaw:
      config:
        agent:
          model: azure/__MODEL__
  sandbox:
    isolation: enhanced
    seccompProfile: kars-strict
    readOnlyRootFilesystem: true
    runAsNonRoot: true
    allowPrivilegeEscalation: false
    writablePaths:
      - /sandbox
      - /tmp
  inferenceRef:
    name: forge-contract-inference
  networkPolicy:
    defaultDeny: true
    egressMode: Strict
    allowedEndpoints: []
```

`__MODEL__` 不会作为账号专属值提交到 Git。实验会读取
[`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01)
中正在运行的 Forge Sandbox 所选择的模型，并把 Manifest 渲染到
`code/03/.generated/`。

独立的 `forge-contract` Sandbox 可以避免 API 实验修改正常工作的 `forge` Agent。

## 持久化之前先验证

运行：

```bash
cd code/03
make validate
```

脚本使用真实 API Server，而不只是 YAML Parser：

```bash
kubectl apply \
  --server-side \
  --dry-run=server \
  --field-manager=code03-lab \
  -f .generated/contract-v1.yaml
```

同一个实验还证明两个负向场景：

| 无效契约 | API 结果 |
| --- | --- |
| `kind: karsSandbox` | 因 Kind 区分大小写而被拒绝 |
| `runtime.kind: UnsupportedRuntime` | 被当前 CRD Enum 拒绝 |

这些错误发生在 Object 持久化之前，Controller 也不会创建 Workload。

## 使用单一 Field Owner

实验采用 Server-side Apply：

```bash
kubectl apply \
  --server-side \
  --field-manager=code03-lab \
  -f .generated/contract-v1.yaml
```

Kubernetes 会在 `metadata.managedFields` 中记录 `code03-lab`，让字段所有权可见，
也让 GitOps 工具能够检测冲突。

规则仍然是：

> 一个声明式字段只有一个 Owner。

紧急情况下可能需要 `kubectl patch`，但之后必须用经过评审的 Manifest 恢复期望状态。
实验会临时破坏 `inferenceRef`，然后使用原 Field Manager 重新应用 V2。

## 把 Status 看成 Controller 的回答

应用 V1 后，实验会等待以下事实同时成立：

```text
status.phase == Running
metadata.generation == status.observedGeneration
status.conditions[type=Ready].status == True
```

已经验证的结果是：

```text
generation=1 observedGeneration=1 phase=Running
```

实验还确认 kars 添加了 Finalizer：

```text
kars.azure.com/namespace-cleanup
```

并生成：

```text
Namespace/kars-forge-contract
Deployment/forge-contract
```

Owner Resource 才是 Source of Truth。运维人员应先查看其 Conditions，再调试生成的
Deployment 或 Pod。

## 使用 `kubectl diff` 评审契约变更

V2 同时修改 OpenClaw Instructions 与推理预算：

```yaml
tokenBudget:
  perRequestTokens: 2048
  dailyTokens: 8192
```

应用前，实验执行：

```bash
kubectl diff \
  --server-side \
  --field-manager=code03-lab \
  -f .generated/contract-v2.yaml
```

因为存在待评审变更，Diff 返回状态码 1。完成 Server-side Apply 后，验证状态变为：

```text
generation=2 observedGeneration=2 phase=Running
```

这比“看到一个新 Pod”更可靠：它证明 Owner Resource 已变化，并且 Controller 已观察
到同一个 Generation。

## 测试依赖错误与恢复

### 缺失同 Namespace Policy

实验会临时修改：

```yaml
inferenceRef:
  name: intentionally-missing-policy
```

Sandbox 报告：

```text
phase: Degraded
reason: InferencePolicyNotFound
```

重新应用经过评审的 V2 Manifest 后，`forge-contract-inference` 引用恢复，Sandbox
重新进入 `Running`。

### Policy 位于另一个 Namespace

[`code/03/manifests/cross-namespace.yaml`](https://github.com/kinfey/LetsLearnMicrosoftKars/blob/main/code/03/manifests/cross-namespace.yaml)
在 `code03-policy-other` 中创建
`InferencePolicy`，但 Sandbox 仍位于 `kars-system`。

Policy Name 确实存在，但 `inferenceRef` 是 Namespace-local Reference，因此无法解析。
Condition 会明确说明不支持 Cross-namespace Reference，也不会创建
`kars-forge-cross-namespace` Workload Namespace 或 Pod。

### 无效 Provider Deployment

对 Kubernetes API 而言，Provider Deployment Name 只是一个不透明字符串。因此，
`intentionally-invalid-model` 可以通过 CRD Validation，Sandbox 也能进入 `Running`。

只有真正发起推理请求时才会验证它是否可用。已经验证的 Router 请求返回：

```text
HTTP 400
```

这一区别可以避免错误的调试假设：

- Schema 与 Reconciliation 只能证明契约结构可以部署；
- 只有真实推理请求才能证明配置的 Provider Deployment 可以使用。

## 运行完整契约实验

```bash
cd code/03
make test
```

该命令依次执行：

1. Microsoft Package Source 强制检查。
2. 根据当前模型渲染 Manifest。
3. Server-side Schema Validation。
4. V1 Server-side Apply 与 Readiness 检查。
5. Managed Field、Finalizer、Namespace 与 Deployment 检查。
6. Idempotence 与 V1-to-V2 Diff。
7. V2 Generation 与 Budget Reconciliation。
8. 缺失 Policy 错误与恢复。
9. Cross-namespace Reference 错误。
10. 无效 Provider 请求测试。
11. 通过 Finalizer 清理资源。

证据保存在：

```text
code/03/.evidence/<UTC timestamp>/
```

其中包含 CRD Schema、Owner Resource、生成的 Deployment、Diff、Conditions、
Request Status、Events 与完整 Transcript。该目录位于 Kubernetes 外部，并通过
Git Ignore 排除。

## 强制使用 Microsoft Package Source

实验开始前会应用并检查：

```text
https://packagefeedproxy.microsoft.io/npm/
https://packagefeedproxy.microsoft.io/pypi/simple/
https://packagefeedproxy.microsoft.io/nuget/v3/index.json
```

退出时会恢复上游 kars 与 OpenClaw 源码文件。

## 只根据需求增加资源

当前安装的 kars API 提供以下相关 Resource Kind：

| 需求 | Resource Kind |
| --- | --- |
| 运行 Agent Workload | `KarsSandbox` |
| 选择模型并限制推理 | `InferencePolicy` |
| 治理工具 | `ToolPolicy` |
| 注册 MCP Service | `McpServer` |
| 保存允许的 Memory | `KarsMemory` |
| 运行 Evaluation | `KarsEval` |
| 描述可信 Peer | `TrustGraph` |
| 临时批准 Egress | `EgressApproval` |
| 治理 SRE 操作 | `KarsSREAction` |
| 暴露 A2A Endpoint | `A2AAgent` |

不要为了“完整”而创建所有 CRD。每个 Object 都必须对应真实的产品或运维需求，并根据
当前安装的 kars Revision 检查成熟度。

## 完成定义

当 Server-side Validation 能拒绝错误 Object、一个 Field Manager 管理经过评审的
字段、`kubectl diff` 能显示权限变化、Controller 报告当前 Generation、依赖错误产生
可操作 Conditions、真实推理验证 Provider 配置、Finalizer 清理生成资源，并且 CI
可以在不依赖开发者 Shell History 的情况下重复同一实验时，平台契约才算 Ready。

## 官方参考

- [kars CRD 参考](https://github.com/Azure/kars/blob/main/docs/api/crd-reference.md)
- [kars Basic Agent 示例](https://github.com/Azure/kars/tree/main/examples/basic-agent)
- [kars 架构](https://github.com/Azure/kars/blob/main/docs/architecture.md)
- [kars 源码仓库](https://github.com/Azure/kars)
## Sandbox Escape 检查点：权限是有 Owner 的 API Field

第二个检查点防止 Workload 改写自身权限。`code/03` 使用 Server-side Apply
Ownership，证明 `agent-self-modification` Manager 不能替换已经评审的
`inferenceRef`。随后通过 Generation、`observedGeneration`、Finalizer 与 Condition
确认评审后的 Contract 是否真正完成 Reconcile。

KARS 在本步骤中的价值是让权限声明化且可观察。普通 Agent Container 也可以拥有配置
文件，但它本身不会提供 Controller 来恢复经过评审的状态，也不会解释 Workload 为何
处于 `Running` 或 `Degraded`。

```bash
cd code/03
make test
```

模型选择、Policy Reference、预算与 Runtime Setting 属于平台 API State，不是 Agent
可以编辑的配置文件。
