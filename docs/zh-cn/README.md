# 一起学习 Microsoft kars

本教程以九章连续故事跟随四人创业团队 **ByteCraft AI**：他们必须在不赌上公司
现金流和首位客户源码安全的前提下，发布从 Issue 到 Pull Request 的研发 Agent
Forge。每章从一个新的交付问题开始，以工程决策或可验证产物结束。

团队有意识地采用两个框架：

- 使用 **OpenClaw** 快速完成对话式原型和工具迭代。
- 当流程需要成为明确、可测试的应用代码时，切换到
  **Microsoft Agent Framework（MAF）Python**。

应用框架发生变化时，kars 仍保持一致的 Sandbox、Router、Policy、Audit 和网络
控制。

## kars 的运行原理

kars 把每个 Agent 视为受治理的 Kubernetes 工作负载。Agent 不拥有独立的外部
网络路径，也不持有生产 Azure 凭据。Sidecar Router 会在转发前评估每项外部操作。

```text
开发者 / CI
      |
      | 提交 karsSandbox 与 Policy CRD
      v
Kubernetes API <------> kars Controller
                            |
                            | 持续协调
                            v
                  独立 Sandbox Namespace
                 +--------------------------------------+
                 | egress-guard（Init Container）       |
                 |                                      |
任务 / 源码 ---->| Agent Runtime，UID 1000              |
                 | OpenClaw 或 MAF Python               |
                 |          |                           |
                 |          | localhost:8443/8444       |
                 |          v                           |
                 | Inference Router，UID 1001           |
                 |   | Policy | Budget | Audit | Auth   |
                 +---|----------------------------------+
                     |
                     | 只转发经过批准的外部请求
                     v
          模型提供商 / MCP / 经过批准的服务
```

### 组件职责

| 组件 | 负责什么 | 不负责什么 |
| --- | --- | --- |
| `karsSandbox` | 声明一个 Agent Runtime、隔离、资源和 Policy 引用 | 不直接决定某次请求是否允许 |
| kars Controller | 监听 CRD，创建 Namespace、Pod、配置、身份资源与 NetworkPolicy | 不位于模型/工具请求数据路径中 |
| Agent Container | 以 UID 1000 运行 OpenClaw、MAF Python 或其他支持的 Runtime | 不应持有生产提供商凭据或直接出口 |
| Egress Guard | 安装规则，强制 Agent 流量进入本地 Router | 是 Safety Net，而不是语义策略引擎 |
| Inference Router | 执行推理、工具、Token 预算、身份、出口与审计决定 | 不判断生成代码是否正确 |
| `InferencePolicy` | 选择模型行为，定义每日与单请求 Token 预算 | 不取代提供商配额或应用循环限制 |
| `ToolPolicy` / `McpServer` | 控制具名工具、身份元数据、速率限制和 MCP 访问 | 不会让所有已安装工具自动变安全 |
| NetworkPolicy | 限制 Kubernetes 网络影响范围 | 不取代 Router 的主机/操作策略 |

### 一次请求的完整路径

1. 开发者向 Agent Runtime 提交需求。
2. Runtime 把推理或受治理工具流量发送到 Localhost Router。
3. Router 检查相关 Policy；模型、工具、主机或操作未获允许时立即拒绝。
4. 对于推理请求，Router 检查单请求与每日 Token 预算。
5. 在 AKS 中，Router 通过 Workload Identity 或每 Sandbox Entra Agent ID 获取
   平台身份；Agent 不会得到该凭据。
6. Router 只把经过批准的请求转发到配置的提供商或服务。
7. Router 把决定、Token、延迟和请求元数据写入 Audit Chain，再把响应返回 Agent。
8. Kubernetes Status 与 Conditions 显示声明的 Sandbox 和 Policy 是否成功协调。

本地 Docker 模式使用相同 Router 决策代码，但 Agent 与 Router 位于同一容器，
因此它是 Inner Loop 开发界面，而非生产安全边界。本地 Kubernetes
（`--target local-k8s`）会复现多容器 Pod、UID 分离、Egress Guard、
NetworkPolicy、Controller 与 CRD 模型。AKS 则增加生产身份和可选机密隔离。

资料来源：[架构](https://github.com/Azure/kars/blob/main/docs/architecture.md)、
[CRD 参考](https://github.com/Azure/kars/blob/main/docs/api/crd-reference.md) 与
[Runtime Catalog](https://github.com/Azure/kars/blob/main/docs/runtimes.md)。

## 目录

1. [需求：演示之前先约束产品](01-why-kars.md)
2. [原型：一切从 OpenClaw 开始](02-local-quickstart.md)
3. [开发：保护客户代码仓库](03-inside-the-sandbox.md)
4. [平台：把演示变成 Kubernetes 契约](04-kubernetes-api.md)
5. [治理：控制 Token、工具和出口](05-policies-and-tools.md)
6. [框架：从 OpenClaw 切换到 MAF Python](06-runtimes-and-byo.md)
7. [测试：阻止 Forge 无限修复同一个测试](07-security-and-operations.md)
8. [部署：把 Forge 推广到 AKS](08-aks-and-multi-agent.md)
9. [发布：交付 Issue 到 PR 的完整流程](09-applied-project.md)

## 创业团队

| 成员 | 创业团队角色 | 核心关注 |
| --- | --- | --- |
| Maya | 联合创始人兼 AI 工程师 | 交付有用的 Agent 行为 |
| Arun | 产品负责人 | 解决客户的研发瓶颈 |
| Ethan | 平台工程师 | 让环境可重复、可运维 |
| Lina | 安全工程师 | 限制源码、身份、工具、成本与出口 |

## 约定

- 命令使用兼容 POSIX 的 Shell。
- 请替换 `<尖括号>` 中的值。
- 示例使用 `kars-system` 命名空间。
- 默认学习环境为本地 Kubernetes。
- 生产建议以 AKS 为基础。

[English edition](../en/README.md)
