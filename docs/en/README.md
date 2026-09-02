# Let's Learn Microsoft kars

This nine-chapter course follows **ByteCraft AI**, a four-person startup racing
to launch Forge, an issue-to-pull-request development Agent, without gambling
its runway or its first customer's source code. Every chapter starts with a new
delivery problem and ends with an engineering decision or testable artifact.

The team deliberately uses two frameworks:

- **OpenClaw** for the first conversational prototype and fast tool iteration.
- **Microsoft Agent Framework (MAF) Python** when the workflow must become
  explicit, testable application code.

kars keeps the sandbox, router, policy, audit, and network controls consistent
while the application framework changes.

## How kars works

kars treats each Agent as a governed Kubernetes workload. The Agent does not
own an independent external network path or production Azure credential.
Instead, a sidecar Router evaluates each outbound action before forwarding it.

```text
Developer / CI
      |
      | applies karsSandbox + policy CRDs
      v
Kubernetes API <------> kars Controller
                            |
                            | reconciles
                            v
                 Dedicated Sandbox namespace
                 +--------------------------------------+
                 | egress-guard (init container)        |
                 |                                      |
Task / source -->| Agent runtime, UID 1000              |
                 | OpenClaw or MAF Python               |
                 |          |                           |
                 |          | localhost:8443/8444       |
                 |          v                           |
                 | Inference Router, UID 1001           |
                 |   | policy | budget | audit | auth   |
                 +---|----------------------------------+
                     |
                     | approved outbound request only
                     v
          Model provider / MCP / approved service
```

### Component responsibilities

| Component | What it does | What it does not do |
| --- | --- | --- |
| `karsSandbox` | Declares one Agent runtime, isolation, resources, and policy references | Does not itself decide whether a request is allowed |
| kars Controller | Watches CRDs and creates namespaces, pods, configuration, identity resources, and NetworkPolicies | Is not in the model/tool request data path |
| Agent container | Runs OpenClaw, MAF Python, or another supported runtime as UID 1000 | Should not hold production provider credentials or direct egress |
| Egress Guard | Installs rules that force the Agent toward the local Router | Is a safety net, not the semantic policy engine |
| Inference Router | Enforces inference, tool, token-budget, identity, egress, and audit decisions | Does not decide whether generated code is correct |
| `InferencePolicy` | Selects model behavior and defines daily/per-request token budgets | Does not replace provider quotas or application loop limits |
| `ToolPolicy` / `McpServer` | Controls named tools, authentication metadata, rate limits, and MCP access | Does not make every installed tool implicitly safe |
| NetworkPolicy | Restricts the Kubernetes network blast radius | Does not replace Router-level host/action policy |

### One request, step by step

1. A developer submits a requirement to the Agent runtime.
2. The runtime sends inference or governed tool traffic to the Router on
   localhost.
3. The Router checks the relevant policy and returns a denial immediately if
   the model, tool, host, or action is not allowed.
4. For inference, the Router checks the per-request and daily token budgets.
5. In AKS, the Router obtains platform identity through Workload Identity or a
   per-Sandbox Entra Agent ID; the Agent does not receive that credential.
6. The Router forwards only the approved request to the configured provider or
   service.
7. The Router records decision, token, latency, and request metadata in the
   audit chain, then returns the response to the Agent.
8. Kubernetes status and conditions show whether the declared Sandbox and
   policies reconciled successfully.

Local Docker mode keeps the same Router decision code but co-locates Agent and
Router, so it is an inner-loop development surface rather than a production
security boundary. Local Kubernetes (`--target local-k8s`) reproduces the
multi-container pod, UID split, Egress Guard, NetworkPolicy, Controller, and CRD
model. AKS adds production identity and optional confidential isolation.

Sources: [Architecture](https://github.com/Azure/kars/blob/main/docs/architecture.md),
[CRD reference](https://github.com/Azure/kars/blob/main/docs/api/crd-reference.md),
and [Runtime catalog](https://github.com/Azure/kars/blob/main/docs/runtimes.md).

## Contents

1. [Requirement: Bound the Product Before the Demo](01-why-kars.md)
2. [Prototype: Start with OpenClaw](02-local-quickstart.md)
3. [Development: Protect the Customer Repository](03-inside-the-sandbox.md)
4. [Platform: Turn the Demo into a Kubernetes Contract](04-kubernetes-api.md)
5. [Governance: Control Tokens, Tools, and Egress](05-policies-and-tools.md)
6. [Framework: Move from OpenClaw to MAF Python](06-runtimes-and-byo.md)
7. [Testing: Stop Forge from Fixing the Same Test Forever](07-security-and-operations.md)
8. [Deployment: Promote Forge to AKS](08-aks-and-multi-agent.md)
9. [Release: Deliver an Issue-to-PR Workflow](09-applied-project.md)

## The startup team

| Person | Startup role | Main concern |
| --- | --- | --- |
| Maya | Co-founder and AI engineer | Ship useful Agent behavior |
| Arun | Product lead | Solve the customer's development bottleneck |
| Ethan | Platform engineer | Make environments reproducible and operable |
| Lina | Security engineer | Bound source, identity, tools, cost, and egress |

## Conventions

- Commands use a POSIX-compatible shell.
- Replace values in `<angle-brackets>`.
- Examples use the `kars-system` namespace.
- Local Kubernetes is the default learning environment.
- Production guidance assumes AKS.

[简体中文版本](../zh-cn/README.md)
