# kars Kubernetes API 契约实验

[English](README.md) | [简体中文](README.zh.md)

本实验把第 4 章转换为可执行的 Kubernetes API 生命周期，并复用
[`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01)
的 Forge 环境与
[`code/02`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/02)
的证据方法。设计参考
上游 [kars CRD Reference](https://github.com/Azure/kars/blob/main/docs/api/crd-reference.md)、
[Basic Agent Example](https://github.com/Azure/kars/tree/main/examples/basic-agent)
和 [Architecture](https://github.com/Azure/kars/blob/main/docs/architecture.md)。

## 实验内容

| API 行为 | 实验 |
|----------|------|
| 准确的 API 标识 | `KarsSandbox` 成功，大小写错误的 `karsSandbox` 被拒绝 |
| CRD Schema | Server-side Validation 拒绝不支持的 Runtime |
| 必需的同 Namespace 引用 | `spec.inferenceRef.name` 只能解析 Sandbox 所在 Namespace 的 Policy |
| Server-side Apply | `managedFields` 记录 Field Manager `code03-lab` |
| 期望状态与观察状态 | `status.observedGeneration` 必须追上 `metadata.generation` |
| 生成资源 | Controller 创建 `kars-forge-contract` Namespace 与 Deployment |
| 可评审变更 | `kubectl diff` 显示 V1 到 V2 的指令与 Token Budget 变化 |
| 可操作错误 | 缺失 Policy 产生 `Degraded/InferencePolicyNotFound` |
| 自动恢复 | 重新应用经过评审的 V2 Manifest 后返回 `Running` |
| Finalizer 所有权 | Owner Resource 包含 `kars.azure.com/namespace-cleanup` |
| Provider 验证边界 | 无效 Deployment 可通过 Kubernetes API，但在推理请求时失败 |

实验使用独立的 `forge-contract` Sandbox，不会修改第 2 章的 `forge` Sandbox。

## Microsoft Package Source

运行任何测试之前，实验会应用并检查
[`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01)
中的 Package Source：

- npm：`https://packagefeedproxy.microsoft.io/npm/`
- PyPI：`https://packagefeedproxy.microsoft.io/pypi/simple/`
- NuGet：`https://packagefeedproxy.microsoft.io/nuget/v3/index.json`

实验退出时会恢复上游源码文件。

## 运行

保持已经验证的
[`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01)
kind 环境运行，然后执行：

```bash
cd code/03
make test
```

该命令会：

1. 读取当前 Forge Contract 选择的模型。
2. 将 V1、V2 与跨 Namespace Manifest 渲染到 `.generated/`。
3. 执行 Server-side Schema Validation。
4. 使用 Field Manager `code03-lab` 应用 V1。
5. 等待 `Running`，并确认 `observedGeneration` 已追上。
6. 记录生成资源、Finalizer 与 Managed Fields。
7. Diff 并应用 V2。
8. 破坏并恢复 `inferenceRef`。
9. 证明跨 Namespace 引用无法解析。
10. 证明无效 Provider Deployment 只会在调用推理时失败。
11. 通过 kars Finalizer 删除所有临时资源。

## 证据

结果保存在 Kubernetes 外部：

```text
.evidence/<UTC timestamp>/
├── transcript.log
├── karssandbox-schema.txt
├── inferencepolicy-schema.txt
├── karssandbox-crd.yaml
├── contract-v1-sandbox.json
├── contract-v1-policy.json
├── contract-v1-deployment.json
├── contract-v1.diff
├── contract-v1-to-v2.diff
├── contract-v2-sandbox.json
├── contract-v2-policy.json
├── contract-missing-policy.json
├── contract-recovered.json
├── cross-namespace-sandbox.json
├── invalid-runtime.txt
├── invalid-kind-case.txt
├── invalid-provider-sandbox.json
├── invalid-provider-request.txt
└── kars-system-events.txt
```

`.evidence/` 与 `.generated/` 已通过 Git Ignore 排除。

## 单独运行

```bash
make render
make validate
make clean
```

应用 Contract 变更前，应先执行
`kubectl diff --server-side --field-manager=code03-lab`。一个字段只能有一个声明式
Owner；紧急 Patch 必须重新同步回经过评审的 Manifest。

## 平台支持

已经验证的环境是 macOS arm64。平台检测继承自
[`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01)，
同时支持 macOS amd64、
Linux amd64，以及通过 Ubuntu WSL2 运行的 Windows amd64。
## Sandbox Escape 递进：权限配置不能自我改写

`code/02` 移除了宿主机与集群的环境权限后，本阶段把 Kubernetes Resource Spec
本身视为权限边界。Lifecycle 测试会使用独立的
`agent-self-modification` Server-side Apply Field Manager 尝试修改
`inferenceRef`。Kubernetes 必须先以 Managed-field Conflict 拒绝该操作，再由经过
评审的 Manifest 完成 Reconcile。

本阶段的 KARS 优势是：模型、预算、Runtime 与 Policy Reference 都是由 Controller
Reconcile、具有可观察 Condition 的 API State，而不是 Agent Framework 自己拥有的
可写配置。

运行 `make test` 并检查
`.evidence/<run>/self-modified-authority.txt`。即使 Workload 内某个目录可写，也不能
据此修改模型、Policy Reference、预算或 Controller Contract。
