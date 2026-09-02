# Forge Sandbox 边界实验

[English](README.md) | [简体中文](README.zh.md)

本实验把第 3 章中的 Sandbox 结论转换为针对
[`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01)
Forge 部署的
可执行检查。设计依据包括
[Azure/kars 安全模型](https://github.com/Azure/kars/blob/main/docs/security.md)
与 [Runtime Contract](https://github.com/Azure/kars/blob/main/docs/runtimes.md)。

## 实验要证明什么

| 边界 | 可执行证据 |
|------|------------|
| 期望状态 | `KarsSandbox/forge` 为 `Running`；删除 Pod 后 Controller 会重新协调 |
| 进程 | OpenClaw 使用 UID 1000，Inference Router 使用 UID 1001 |
| 运维访问 | kars Admission Policy 拒绝普通 `kubectl exec` 进入 OpenClaw |
| 文件系统 | OpenClaw 根文件系统只读且没有 hostPath；仓库位于 MCP Pod 的一次性 `emptyDir` |
| 身份 | OpenClaw 没有 GitHub/Copilot Provider 凭据引用，凭据只属于 Router |
| 网络 | Agent 直接 HTTPS 失败，但通过 `127.0.0.1:8443` 推理成功 |
| Policy 协调 | 缺少 `InferencePolicy` 时得到 `Degraded/InferencePolicyNotFound` |
| 证据生命周期 | YAML、JSON 和日志被复制到 Sandbox 外部的 `.evidence/` |

真实部署对章节内容有一个重要修正：Forge 不会直接挂载代码仓库。经过加固的
`forge-workspace-mcp` Pod 管理固定 Revision 的一次性 Workspace，并且只暴露七个
窄接口工具。

## KARS 优势与 Agent Container 技术细节

KARS 把安全要求转换为自动生成、持续 Reconcile 的 Pod State，而不是 OpenClaw 内部
的开发约定：

| Agent Container 细节 | 可执行检查 |
| --- | --- |
| Agent UID `1000`、Router UID `1001` | 检查 Pod `securityContext` |
| Read-only Root、禁止提权、Drop Capability | `scripts/test-static.sh` |
| Writable Path 严格等于 `/sandbox` 与 `/tmp` | 断言 `KarsSandbox.spec.sandbox` |
| 没有 `hostPath`、Docker Socket 或自动 ServiceAccount Token | Pod Volume 与 Identity 检查 |
| 没有 Provider Credential Reference | 对比 Agent 与 Router Environment Name |
| Default-deny Egress，同时允许 Loopback Router | Sandbox 与生成的 NetworkPolicy Evidence |
| 普通 Exec 被拒绝 | `kars-sandbox-exec-ban` Probe |

Agent Container 可以进行推理并调用 Loopback Service，但不能持有完成这些调用所需的
Credential 或外部 Route。这就是 KARS 相比把 OpenClaw、Key、Tool 与无限制网络放在
同一个应用 Container 中的具体优势。

## 前置条件

1. 部署并验证 [`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01)。
2. 保持 `kars-dev` kind 集群运行。
3. 安装 `kubectl`、`jq`、`curl`、Docker 和 Node.js 22。

实验运行前会检查
[`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01)
中的所有依赖源：

- npm：`https://packagefeedproxy.microsoft.io/npm/`
- PyPI：`https://packagefeedproxy.microsoft.io/pypi/simple/`
- NuGet：`https://packagefeedproxy.microsoft.io/nuget/v3/index.json`

## 运行

非破坏性测试会检查资源、验证 Exec 拒绝，并创建一个临时的缺失 Policy Sandbox：

```bash
cd code/02
make test
```

完整实验还会执行短时、可审计的 Break-glass 探测，并重启 Forge Pod：

```bash
make test-full
```

`test-full` 会临时给 `kars-forge` Namespace 添加
`kars.azure.com/break-glass=true`，只检查 UID、文件系统可写性、凭据变量名称、
直接 HTTPS 与 Loopback Router，然后通过 Shell Trap 立即删除标签。脚本不会输出
任何凭据值。

Pod 重启只删除当前 Forge Pod。kars 管理的 Deployment 会创建替代 Pod，脚本随后
验证新的 Pod UID 与 Sandbox 的 `Running` 状态。

## 证据

每次运行都会写入带 UTC 时间戳的目录：

```text
.evidence/<UTC timestamp>/
├── README.md
├── transcript.log
├── forge-sandbox.yaml
├── forge-pod.json
├── pod-summary.json
├── network-policies.yaml
├── workspace-deployment.yaml
├── exec-admission-policy.yaml
├── controller.log
├── router.log
├── missing-policy-sandbox.json
└── reconciliation.json
```

该目录位于 Kubernetes 外部，并通过 Git Ignore 排除。即使 Pod 与 Workspace 已被
清理，证据仍然保留，同时不会把集群专属日志提交到仓库。

## 单独运行实验

```bash
make inspect
make degraded
make reconcile
make clean
```

`make reconcile` 已通过 Makefile Target 显式设置重启许可。`make clean` 会删除实验
产生的临时集群状态，但保留本地证据。

## 平台说明

已经验证的环境是 macOS arm64。脚本复用
[`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01)
的平台检测，同时支持 macOS
amd64、Linux amd64，以及通过 Ubuntu WSL2 运行的 Windows amd64。Windows 用户应在
WSL2 内运行命令，而不是直接使用原生 PowerShell 或 CMD。
## Sandbox Escape 递进：先约束进程

`code/01` 已证明恶意仓库文本无法获得有用工具。本阶段下沉一层，证明即使 Agent
进程做出错误决定，也缺少逃逸所需的基础能力。`make test` 现在检查可写路径只包含
`/sandbox` 与 `/tmp`、没有 Host Filesystem 或容器 Daemon Socket、没有自动挂载的
Kubernetes ServiceAccount Token，并且普通 `kubectl exec` 会被拒绝。只有
`make test-full` 才会启用经过审计的 Break-glass 探测。

这会阻断常见的路径、Docker Socket 与 Runtime Control 逃逸前提。路径真实解析由
`code/01` 验证，本章则证明应用层即使漏掉一次检查，也不能直接获得宿主机或集群权限。
