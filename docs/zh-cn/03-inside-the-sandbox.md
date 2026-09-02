# 3. 开发：保护客户代码仓库

> **交付阶段：** 开发环境
> **新问题：** Forge 如何执行客户代码，却看不到无关源码、开发者凭据或不受限制
> 的网络？
> **交付物：** 经过测试的 Sandbox 边界与一次性 Workspace 设计。
> **配套实验：** [`code/02`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/02)

## “Sandbox”背后的问题

ByteCraft 的 Design Partner 愿意提供一个小型私有仓库，但前提是团队解释源码
存放位置和访问主体。完成本地实验后，Maya 说：“Forge 现在已经运行在 Sandbox
中。”

Lina 提出了一个看似简单的问题：

> Sandbox 到底保护什么，又不保护什么？

Sandbox 不是一个有魔力的标签。对 Forge 而言，它必须保护私有源码、隔离 Agent
与凭据、限制网络目标，并留下足够证据来解释失败或恶意操作。如果团队说不清这些
边界，就无法测试它们。

本章暂停功能开发，逐层打开 Sandbox。

## `karsSandbox` 是工作单元

在 kars 中，一个 `karsSandbox` 代表一个 Agent 工作负载。它连接：

- OpenClaw、Hermes、其他 Adapter 或 BYO Runtime；
- 必需的 `InferencePolicy`；
- Sandbox 隔离与安全设置；
- 网络策略和可选 Approval；
- 自动生成的 Kubernetes 资源；
- 协调状态与 Conditions。

自定义资源是期望状态契约，运行中的 Pod 是该契约产生的结果之一。直接修改 Pod
不会重新定义 Sandbox；Controller 可能在协调期间替换它。

在 Forge 故事中，一个 Sandbox 表示一个研发角色的一次受限执行上下文。这不代表
所有开发者、仓库和 Agent 都应该共享一个长期 Workspace。

## 打开接近生产形态的 Pod

在本地 Kubernetes 与 AKS 中，关键 Pod 形态如下：

```text
karsSandbox: forge
└── Pod
    ├── init: egress-guard  UID 0，仅初始化期间拥有 NET_ADMIN
    ├── openclaw           UID 1000
    └── inference-router  UID 1001
```

### Agent Container 技术结构

`openclaw` Container 被刻意视为 Pod 中信任等级最低的 Container。KARS Controller
根据 `KarsSandbox.spec.runtime` 与 `spec.sandbox` Contract 生成它，而不是要求应用
自己在代码中写死全部安全设置。

| Kubernetes/Runtime 细节 | Forge 配置 | Agent Container 内的结果 |
| --- | --- | --- |
| `runAsNonRoot` / Runtime UID | `true` / UID `1000` | Agent 不能依赖 Root Ownership |
| `readOnlyRootFilesystem` | `true` | Image Layer、Binary 与系统配置不可写 |
| `allowPrivilegeEscalation` | `false` | Setuid 或 Process Transition 不能增加权限 |
| Linux Capability | Drop `ALL` | 没有环境 Network、Mount 或 Process-management Capability |
| Writable Path | `/sandbox`、`/tmp` | State 与 Cache 具有明确的清理边界 |
| Volume | 没有 `hostPath` 或 Docker Socket | Agent 无法到达开发者 Home 或 Container Daemon |
| Service Account | `automountServiceAccountToken: false` | Filesystem 中不会出现隐式 Kubernetes API Bearer Token |
| Provider Environment | 没有 GitHub/Copilot Token Reference | Prompt-injected Code 无法从 `env` 读取模型凭据 |
| Repository Access | 该 Pod 不挂载 Checkout | 读写必须通过 Router 到受限 Workspace MCP Service |
| Network Namespace | 与 Router 共享，并使用 UID-aware Egress Control | Loopback 可用，独立外部出口不可用 |
| Operator Access | Exec Admission Policy | 普通 `pods/exec` 与 Attach 路径不能进入 Agent Runtime |

Container 仍然拥有完成任务所需的能力：运行 OpenClaw、在批准的 Writable Path 中保存
Conversation State、调用 `127.0.0.1:8443`，以及请求受治理工具。Sandbox 并不表示一个
空进程，而是所有超出 Runtime Envelope 的副作用都必须跨越独立执行的边界。

### KARS 提供什么，平台仍负责什么

KARS 提供 Runtime Adapter、Controller Reconciliation、Router Sidecar、UID 分离、
Sandbox Security Context、Egress Guard Integration、NetworkPolicy Intent、Policy
Reference、Condition 与 Exec Admission Boundary。平台团队仍需负责 Image、
MCP Implementation、Secret Selection、Allowed Endpoint、Writable Data，以及任何会
消费 Agent Artifact 的外部系统。

这正是 ByteCraft 场景中的实际优势：安全控制不需要在 OpenClaw 内重复实现；同时
KARS 也不会声称一个不安全 Tool Server 或错误挂载的 Secret 因为旁边运行着 Router
就自动变得安全。

### `egress-guard`

Init Container 安装网络规则，使 Agent UID 可以通过 Loopback 到达路由器，却无法
建立独立外部路径。它是 Safety Net，而不是策略决策点。

### `agent`

Forge 与 OpenClaw Runtime 以 UID 1000 运行。在
[`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01) 的实际实现中，
OpenClaw 不会直接挂载代码仓库，而是调用本地 Router，由 Router 代理访问独立的
Workspace MCP Service。OpenClaw 既不持有 Provider 凭据，也没有直接出口。

### `inference-router`

Rust 路由器以 UID 1001 运行。面向模型的 HTTP Endpoint 使用端口 `8443`，
Forward Proxy 路径使用 `8444`。它负责评估策略、预算、身份、出口、治理和审计。

UID 分离十分重要：Forge 解释或执行的代码，不会以持有外部权限的路由器用户运行。

## 围绕一次代码修改的五层边界

Maya 给 Forge 分配包含 Issue #482 的 Workspace。团队沿任务检查五层边界。

### 1. 进程边界

Forge 以非 root Agent 进程运行，路由器使用不同 UID。研发 Agent 执行的命令
不应读取路由器的进程环境或凭据材料。

本地 Kubernetes 与 AKS 的边界强于单容器 Docker 开发模式。Docker 模式中 Agent
和路由器位于同一容器，UID 与网络隔离不等同于生产。

### 2. 文件系统边界

Agent 只获得任务需要的 Runtime 文件。良好的研发 Sandbox 使用固定 Revision 的
临时 Checkout 或 Worktree，不会挂载开发者 Home、SSH 目录、全局 Git Credential
Store 或无关仓库。

Forge 采用了更强的分离：经过加固的 `forge-workspace-mcp` Pod 使用有大小限制的
`emptyDir` 管理固定 Revision 仓库；OpenClaw Pod 没有仓库或 `hostPath` 挂载。
MCP Deployment 同时关闭自动 Service Account Token 挂载，并且只暴露七个受限工具。

kars 定义 Runtime Sandbox，但平台团队仍需谨慎设计 Volume 与 Secret。
NetworkPolicy 无法保护被错误挂载到 Agent 容器中的 Secret。

### 3. 网络边界

Agent 把受控请求发送到 `127.0.0.1:8443` 或文档规定的 Proxy 路径。Egress Guard
与 Kubernetes NetworkPolicy 阻止独立路径，路由器执行真正的策略决定。

必须区分：

- 网络控制回答：“这个 Packet 能否从其他路径离开？”
- 路由器策略回答：“这个模型、工具、主机或操作是否允许？”

纵深防御同时需要两者。

### 4. 身份边界

生产环境中，路由器根据部署模式使用 Workload Identity 或每 Sandbox Entra
Agent ID。Forge 不会得到对应 Azure 凭据。

本地 Kubernetes 会复现 Pod 与网络形态，但使用静态提供商凭据进行开发。它拥有
接近生产的基础设施形态，却不是生产身份。

### 5. 生命周期与证据边界

Controller 观察 `karsSandbox`、创建或更新资源，并报告 Conditions。路由器记录
请求期间的决定。任务结束后，可以删除 Workspace，同时把审计证据独立导出。

临时执行可以降低持久化风险，但在导出证据前删除 Pod，也可能破坏重要事故上下文。

## 检查 Sandbox，而不是假设

先启动第 2 章的 Forge 部署，再运行可执行实验：

```bash
cd code/02
make inspect
```

脚本会从 `KarsSandbox/forge` 自动发现生成的 Namespace 与 Pod，不会写死 Pod 名称。
它会导出：

- Sandbox 期望状态与 Conditions；
- Pod Spec 与精简的 UID/挂载摘要；
- NetworkPolicy；
- Workspace MCP Deployment；
- kars Exec Admission Policy；
- 最近的 Controller 与 Router 日志。

输出保存在 Kubernetes 外部的 `.evidence/<UTC timestamp>/`，因此 Pod 重新协调或
Workspace 清理后，证据仍然存在。

普通运维人员也不能假设自己拥有交互式 Shell：

```bash
kubectl -n kars-forge exec <forge-pod> -c openclaw -- id
```

kars 会通过 `kars-sandbox-exec-ban` 拒绝该请求。完整实验可以短时启用可审计的
Namespace Break-glass Label，只执行范围明确的只读探测，并通过 Shell Trap 删除标签。

## 使用 Forge 测试边界

[`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01)
中的 Fixture 仓库就是专门准备的一次性测试仓库。绝不要使用生产 Checkout
进行以下实验。

| 测试 | 预期结果 |
| --- | --- |
| 检查 Forge 与分配的 Workspace | 通过 kars 资源和受限 MCP 工具允许 |
| 读取开发者 Home 中的 Secret | 没有挂载 Host 文件系统或 Home 目录 |
| 通过路由器调用模型 | 在推理策略范围内允许 |
| 从 OpenClaw 直接访问未知主机 | 超时并返回 HTTP `000` |
| 从 OpenClaw 写入 `/etc` | 被只读根文件系统拒绝 |
| 在 OpenClaw 中查找 Copilot 凭据 | 不存在 Provider 凭据变量 |
| 对 OpenClaw 使用普通 `kubectl exec` | 被 kars Admission Policy 拒绝 |
| 重启 Agent | Controller 将工作负载恢复到期望状态 |
| 引用不存在的推理策略 | 得到 `Degraded/InferencePolicyNotFound` |

运行非破坏性检查：

```bash
make test
```

运行完整实验，包括短时 Break-glass 探测与 Forge Pod 替换：

```bash
make test-full
```

经过验证的 macOS arm64 运行结果包括：OpenClaw UID 1000、Router UID 1001、
根文件系统写入被拒绝、OpenClaw 中没有 Provider 凭据、直接 HTTPS 被阻断、
通过 `127.0.0.1:8443` 返回 HTTP 200、缺失 Policy 时出现 Degraded Condition，
以及删除 Forge Pod 后 Controller 成功创建替代 Pod。

实验开始前会强制检查
[`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01)
使用的 Microsoft Package Feed Proxy：

```text
https://packagefeedproxy.microsoft.io/npm/
https://packagefeedproxy.microsoft.io/pypi/simple/
https://packagefeedproxy.microsoft.io/nuget/v3/index.json
```

## 选择正确隔离级别

kars 使用安全的 Sandbox 默认值，包括 Enhanced Isolation、严格 Seccomp Profile
和 Default-Deny 网络。AKS 可以选择由 Kata/AMD SEV-SNP 支持的 Confidential
Isolation，进一步加强工作负载隔离。

当 Forge 处理未发布源码或高价值构建输入时，机密隔离可能合适。但它不能取代
最小权限身份、签名镜像、工具策略、出口策略或代码审查。

## Sandbox 不承诺什么

团队把以下限制写入威胁模型：

- 它不能证明生成的 Patch 一定正确。
- 它不会让不可信代码自动变得可以合并。
- 它无法保护被错误挂载到 Agent 中的凭据。
- 它不会把 Docker 开发模式变成生产边界。
- 它不能取代租户级 RBAC、配额、镜像策略或审计导出。
- 如果策略明确允许任意 Shell 和不受限出口，它也无法补偿。

Sandbox 负责限制权限；测试、评估、评审和部署策略仍然决定变更是否可接受。

## Forge Sandbox 设计记录

继续之前，团队记录：

```text
Workload：一次 Forge Builder 任务
Source：Workspace MCP Pod 的 emptyDir 中保存固定 Revision Checkout
Agent User：UID 1000
Router User：UID 1001
外部路径：仅 Router
Agent 中的凭据：无
OpenClaw 可写范围：/sandbox 与 /tmp
仓库写入：仅受限 Workspace MCP 工具
生命周期 Owner：kars Controller
证据目标：code/02/.evidence，然后进入外部 Audit Store
清理：删除 Pod 或 Workspace 前先导出证据
```

下一章会把已经理解的 Runtime 边界转化为可评审的 Kubernetes 契约。

## 完成定义

只有固定 Revision 的一次性 Checkout 被隔离在 Workspace MCP Pod、OpenClaw 没有
仓库挂载或可复用 Git/模型凭据、直接访问未知目标失败、UID 分离与 Exec 限制清晰
可见、Controller Reconciliation 得到验证，并且导出的证据在 Workspace 清理后仍然
保留时，开发环境才算 Ready。

## 官方参考

- [架构与部署模式](https://github.com/Azure/kars/blob/main/docs/architecture.md)
- [karsSandbox CRD 参考](https://github.com/Azure/kars/blob/main/docs/api/crd-reference.md#karssandbox--the-agent)
- [Runtime 契约](https://github.com/Azure/kars/blob/main/docs/runtimes.md)
- [安全模型](https://github.com/Azure/kars/blob/main/docs/security.md)
## Sandbox Escape 检查点：移除环境权限

第一个 Containment 检查点是结构性的。Forge 只能写入 `/sandbox` 与 `/tmp`，
不会得到 Host Mount、Docker Socket、Provider Credential 或自动挂载的 Kubernetes
ServiceAccount Token。普通 Agent Runtime Exec 会被拒绝，Break-glass 则必须显式
启用并接受审计。

在 [`code/02`](../../code/02) 中运行：

```bash
make test
```

本阶段不假设模型总能识别 Prompt Injection，而是移除把错误决定升级为宿主机或集群
控制权所需的进程级能力。
