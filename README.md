# Let's Learn Microsoft kars

[English](README.md) | [简体中文](README.zh.md) | [GitHub Pages](https://kinfey.github.io/LetsLearnMicrosoftKars/)

An OpenClaw-first, bilingual, executable guide to
[Azure kars](https://github.com/Azure/kars), the Agent Reference Stack for
Kubernetes. The repository follows a startup team as it turns an
issue-to-pull-request prototype into a governed Microsoft Agent Framework
application running on AKS with GitHub Copilot GPT-5.6-Sol.

This is not only conceptual documentation. Each stage has runnable source,
policy, tests, and evidence under
[`code/01`–`code/08`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code).

> This guide tracks kars `v0.1.25` and was last reviewed on 2026-08-29. kars is
> an alpha reference implementation, not an officially supported Microsoft
> product. Confirm commands against `kars --help` when using another version.

## What this repository demonstrates

- Start with **OpenClaw** to prove a bounded conversational workflow.
- Move the workflow into **Microsoft Agent Framework (MAF) Python** when it
  needs explicit application code, typed tools, repeatable tests, and bounded
  model iterations.
- Route model traffic through the local **kars Inference Router**, rather than
  giving the Agent direct provider credentials or unrestricted egress.
- Apply `KarsSandbox`, `InferencePolicy`, `ToolPolicy`, and `McpServer`
  contracts through the Kubernetes API.
- Enforce model selection, token budgets, tool allowlists, egress rules,
  separation of duties, audit chains, repair limits, Kill Switch, rollback,
  and human review.
- Promote Linux amd64 workloads to an existing or newly created AKS
  environment without publishing real Azure resource names.
- Run real GitHub Copilot **GPT-5.6-Sol** inference through both OpenClaw/BYO
  and first-class MAF runtime paths.

## Key kars characteristics

kars is a Kubernetes reference stack for running AI Agents with authority
separated from the Agent application. Its main characteristics are:

| Characteristic | How it works | Value in the Forge scenario |
| --- | --- | --- |
| Declarative Agent workloads | `KarsSandbox` describes runtime, isolation, resources, governance, network policy, and lifecycle | Forge is reviewed and reproduced as Kubernetes desired state instead of an ad hoc process |
| Mediated inference | A local Inference Router receives Agent requests before calling the model provider | OpenClaw or MAF can use a model without receiving the production provider credential |
| Runtime-independent governance | OpenClaw, Microsoft Agent Framework, BYO images, and other adapters use the same external policy boundary | Changing Agent frameworks does not require rebuilding the complete security model |
| Policy-controlled models and budgets | `InferencePolicy` selects providers/deployments and applies per-request and daily token limits | A prompt loop cannot silently change models or consume an unlimited inference budget |
| Governed tools and MCP | `ToolPolicy` and `McpServer` restrict tool names, target Sandboxes, approvals, rate limits, and capabilities | Repository content cannot turn a bounded patch tool into arbitrary shell or release authority |
| Credential and identity separation | Provider credentials or workload identity remain on the Router/platform path | Prompt-injected Agent code cannot read reusable GitHub, Copilot, or Azure credentials from its environment |
| Defense-in-depth sandboxing | Non-root runtime, read-only root filesystem, explicit writable paths, UID separation, Egress Guard, NetworkPolicy, and exec admission | A bad Agent decision lacks common host, filesystem, cluster, and direct-network escape primitives |
| Reconciliation and status | The Controller converts desired state into Pods and reports Conditions and observed generations | Deleted or drifted workloads return to reviewed state, while failures become visible as `Degraded` rather than hidden application errors |
| Audit and operational controls | Router decisions, policy digests, evidence export, suspension, repair limits, break-glass, and rollback provide operational boundaries | Security teams can explain denied actions, stop a runaway workflow, and recover without granting the Agent permanent operator access |
| Multi-Agent separation | Builder, Reviewer, or specialist Agents can have separate Sandboxes, tools, budgets, identities, and trust requirements | Separation of duties is enforced by platform resources rather than role instructions inside one Agent prompt |

The central design principle is:

> The Agent may decide what it wants to do, but it does not independently own
> the credentials, network path, tools, or policy required to perform that
> action.

kars does not make an unsafe image, MCP server, or Agent-generated artifact
automatically safe. Platform teams must still review those components and use
the maturity guidance appropriate for an alpha reference implementation.

## Architecture

```text
Requirement / Issue
        |
        v
OpenClaw Intake and prototype
        |
        v
MAF Agent + bounded tools
        |
        v
kars Sandbox
  +--------------------------------------+
  | Agent runtime, UID 1000              |
  |        | localhost:8443/8444         |
  |        v                             |
  | Inference Router, UID 1001           |
  | policy | budget | identity | audit   |
  +--------------------------------------+
        |
        v
GitHub Copilot GPT-5.6-Sol / approved MCP
        |
        v
Digest-pinned evidence and human review
```

The Agent does not own the production provider credential. kars keeps
inference, tool, network, identity, and audit controls consistent while the
application evolves from OpenClaw to MAF Python.

## Learning path and executable labs

| Chapter | Outcome | Sandbox-escape checkpoint | Executable lab |
| --- | --- | --- | --- |
| [1. Why kars](https://kinfey.github.io/LetsLearnMicrosoftKars/en/01-why-kars/) | Bound the product and threat model before implementation | Identify self-configuration, symlink, trust-handoff, and covert-egress risks | Architecture and delivery contract |
| [2. Local quickstart](https://kinfey.github.io/LetsLearnMicrosoftKars/en/02-local-quickstart/) | Build the first OpenClaw Issue-to-Patch workflow | Reject hostile repository actions with layered controls | [`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01) |
| [3. Inside the Sandbox](https://kinfey.github.io/LetsLearnMicrosoftKars/en/03-inside-the-sandbox/) | Inspect UID, filesystem, network, and credential boundaries | Remove ambient host, daemon, and cluster authority | [`code/02`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/02) |
| [4. Kubernetes API](https://kinfey.github.io/LetsLearnMicrosoftKars/en/04-kubernetes-api/) | Make Sandbox and policy state reproducible through CRDs | Prevent the workload from rewriting its authority | [`code/03`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/03) |
| [5. Policies and tools](https://kinfey.github.io/LetsLearnMicrosoftKars/en/05-policies-and-tools/) | Enforce token, tool, MCP, dependency, and egress policy | Validate tool arguments and security-sensitive paths | [`code/04`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/04) |
| [6. Runtimes and BYO](https://kinfey.github.io/LetsLearnMicrosoftKars/en/06-runtimes-and-byo/) | Compare a host-side MAF canary with a kars BYO runtime | Pin immutable runtime artifacts | [`code/05`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/05) |
| [7. Security and operations](https://kinfey.github.io/LetsLearnMicrosoftKars/en/07-security-and-operations/) | Test repair limits, admission controls, audit, and recovery | Audit DNS, metadata, daemon, exec, and HTTPS channels | [`code/06`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/06) |
| [8. AKS and multi-agent](https://kinfey.github.io/LetsLearnMicrosoftKars/en/08-aks-and-multi-agent/) | Separate Builder and Reviewer and promote to AKS | Hand off digest-pinned artifacts, not mutable workspaces | [`code/07`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/07) |
| [9. Applied project](https://kinfey.github.io/LetsLearnMicrosoftKars/en/09-applied-project/) | Run an OpenClaw-first, first-class MAF release pilot | Enforce the complete release containment gate | [`code/08`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/08) |

## Start here

Read the bilingual tutorial:

- [English documentation](https://kinfey.github.io/LetsLearnMicrosoftKars/en/)
- [简体中文文档](https://kinfey.github.io/LetsLearnMicrosoftKars/zh-cn/)

Run the first local lab:

```bash
git clone https://github.com/kinfey/LetsLearnMicrosoftKars.git
cd LetsLearnMicrosoftKars/code/01
make test
```

The labs are cumulative. Complete each predecessor before running a later lab,
because later stages verify live Sandbox, policy, image, and audit evidence
created by earlier stages.

## Platform and package requirements

- Verified development host: macOS arm64.
- Also documented: macOS amd64, Linux amd64, and Windows amd64 through Ubuntu
  WSL2.
- Azure workload target: Linux amd64.
- Node.js: 22.
- Required tools vary by lab and include Docker Desktop, kind, kubectl, Helm,
  Azure CLI, Python 3.11+, jq, curl, kars CLI, and authenticated GitHub Copilot
  CLI.

All package restoration uses Microsoft Package Feed Proxy:

| Ecosystem | Source |
| --- | --- |
| npm | `https://packagefeedproxy.microsoft.io/npm/` |
| PyPI | `https://packagefeedproxy.microsoft.io/pypi/simple/` |
| NuGet | `https://packagefeedproxy.microsoft.io/nuget/v3/index.json` |

## Azure deployment

The repository does not publish or bind examples to real Azure resource names.
Before an Azure deployment, copy the relevant ignored environment template and
provide your own values:

```bash
export AZURE_RESOURCE_GROUP="<your-resource-group>"
export AKS_NAME="<your-aks-cluster>"
export KARS_ACR_NAME="<your-acr-name>"
export AZURE_LOCATION="<your-azure-region>"
```

Real deployment remains an explicit opt-in. Review the plan, expected cost,
architecture, policies, and rollback procedure before enabling the deployment
switch in the selected lab.

## Important implementation notes

- kars `v0.1.25` accepts `agentCode.oci` in the MAF runtime plan but does not
  materialize that code mount in the generated Pod. The applied project keeps
  immutable code outside `/sandbox` and copies it into the writable runtime
  volume at startup.
- GPT-5.6-Sol uses the Responses API. The MAF implementation disables stored
  response continuation and replays bounded tool history inline for
  compatibility with the kars GitHub Copilot adapter.
- `KarsEval` corpus resolution is demonstrated, but the upstream `v0.1.25`
  Runner Job does not satisfy AKS restricted Pod Security. The examples do not
  weaken the namespace policy to make that Job run.
- Generated evidence and local Azure configuration remain uncommitted. Do not
  place credentials, tokens, subscription IDs, or customer source in the
  repository.

## Official references

- [Azure kars repository](https://github.com/Azure/kars)
- [kars architecture](https://github.com/Azure/kars/blob/main/docs/architecture.md)
- [kars getting started](https://github.com/Azure/kars/blob/main/docs/getting-started.md)
- [kars CRD reference](https://github.com/Azure/kars/blob/main/docs/api/crd-reference.md)
- [kars security](https://github.com/Azure/kars/blob/main/docs/security.md)
- [Microsoft Agent Framework](https://github.com/microsoft/agent-framework)
- [GitHub Copilot provider samples](https://github.com/microsoft/agent-framework/tree/main/python/samples/02-agents/providers/github_copilot)
- [Build Your Own Claw sample](https://github.com/microsoft/agent-framework/tree/main/python/samples/02-agents/harness/build_your_own_claw)

## License

Unless stated otherwise, this tutorial is released under the
[MIT License](LICENSE).
