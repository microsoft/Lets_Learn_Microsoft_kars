# 6. Runtimes and BYO: From OpenClaw to Explicit Code

> **Delivery stage:** Production implementation
> **Starting point:** Keep the validated OpenClaw behavior, then decide which
> application loop runs inside or beside the kars security shell.
> **Executable lab:** [`code/05`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/05)

## Everything still starts from OpenClaw

[`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01)
proved the FORMAT-482 journey with OpenClaw:

```text
receive issue -> inspect repository -> patch -> named test -> evidence
```

[`code/02`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/02)
proved the Sandbox boundary,
[`code/03`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/03)
proved the Kubernetes API contract, and
[`code/04`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/04)
proved inference and tool policy. Chapter 6 changes the
runtime loop without weakening those boundaries.

The production question is not "Which framework is best?" It is:

> Can another implementation preserve the same states, permissions, model,
> failure behavior, and human-review stop?

The lab makes the workflow explicit:

```text
RECEIVE_REQUIREMENT
  -> VALIDATE_SCOPE
  -> INSPECT_REPOSITORY
  -> PROPOSE_PLAN
  -> APPLY_MINIMAL_PATCH
  -> RUN_TARGETED_TESTS
  -> SUMMARIZE_EVIDENCE
  -> STOP_FOR_HUMAN_REVIEW
```

There is deliberately no `MERGE` or `DEPLOY` state.

## Separate framework, provider, and runtime

Three names that sound interchangeable are different layers:

| Layer | Example in this chapter | Responsibility |
| --- | --- | --- |
| Agent framework | Microsoft Agent Framework | Agent API, tools, sessions, application structure |
| Model provider path | GitHub Copilot / GPT-5.6-Sol | Model access and host-side Copilot session |
| kars runtime | `OpenClaw`, `MicrosoftAgentFramework`, or `BYO` | Container plan inside the governed Sandbox |

Changing `KarsSandbox.spec.runtime.kind` changes the runtime container producer.
It does not automatically convert an OpenClaw prompt into tested Python code.

## A real incompatibility between the referenced samples

The Microsoft
[Build Your Own Claw](https://github.com/microsoft/agent-framework/tree/main/python/samples/02-agents/harness/build_your_own_claw)
sample builds a harness with:

```python
create_harness_agent(client=chat_client, ...)
```

That factory expects a chat client. The
[GitHub Copilot provider](https://github.com/microsoft/agent-framework/tree/main/python/samples/02-agents/providers/github_copilot)
instead exposes `GitHubCopilotAgent`, which is already a complete agent with a
Copilot CLI session and its own tool loop. It is not a chat client and cannot
be passed directly to `create_harness_agent`.

Therefore [`code/05`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/05)
does not claim a nonexistent drop-in integration. It keeps
the claw principles—explicit planning, bounded tools, approvals, state, and a
human-review stop—and tests two honest lanes.

## Lane A: host-side MAF GitHub Copilot canary

```text
Microsoft Agent Framework GitHubCopilotAgent
    -> authenticated local Copilot CLI
    -> GitHub Copilot GPT-5.6-Sol
```

The lab installs this exact package through Microsoft Package Feed Proxy:

```text
agent-framework-github-copilot==1.0.3
```

The agent fixes its model explicitly:

```python
GitHubCopilotOptions(
    model="gpt-5.6-sol",
    available_tools=["inspect_forge_contract"],
    on_permission_request=bounded_permission_handler,
)
```

The Copilot SDK still applies its own Custom Tool permission layer. MAF
`approval_mode="never_require"` is not permission to approve every Copilot
action. The handler approves `inspect_forge_contract` once and denies shell,
file, URL, MCP, write, and every other request.

The tool returns a random nonce unavailable in the prompt. A passing result
must contain that nonce:

```text
COPILOT_GPT_5_6_SOL_OK FORMAT-482 <random-nonce> STOP_FOR_HUMAN_REVIEW
```

This prevents a text-only response from being mistaken for proof that the tool
ran.

Lane A uses the host's authenticated Copilot CLI. It is a framework/provider
canary, not a kars-isolated workload.

## Lane B: kars BYO production candidate

```text
KarsSandbox/runtime.kind=BYO
    -> BYO Python application
    -> http://127.0.0.1:8443/v1/responses
    -> kars Router
    -> GitHub Copilot GPT-5.6-Sol
```

The model remains selected by `InferencePolicy`:

```yaml
spec:
  modelPreference:
    primary:
      provider: azure-openai
      deployment: gpt-5.6-sol
  tokenBudget:
    perRequestTokens: 1024
    dailyTokens: 4096
```

In this local kars configuration, the Router's provider override is
`github-copilot`; `deployment` carries the model ID. The BYO Agent sees
`KARS_MODEL=gpt-5.6-sol`, but it does not receive the Copilot token.

The runtime declaration is:

```yaml
spec:
  runtime:
    kind: BYO
    byo:
      image: forge-byo-copilot-claw:dev
      contractVersion: v1
```

## The BYO image contract

The image must declare and implement the contract:

```dockerfile
LABEL org.kars.runtime.contract="v1"
USER 1000
```

kars mounts an `emptyDir` at `/sandbox`. Immutable application code must not be
baked into a path that the runtime mount hides.
[`code/05`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/05)
keeps code under
`/app` and reserves `/sandbox` and `/tmp` for writable state.

The experiment verifies:

- OCI contract label `v1`;
- image user and Agent container UID 1000;
- Router UID 1001;
- read-only root filesystem;
- dropped Agent capabilities;
- privileged work confined to the short-lived `egress-guard` init container;
- `KARS_RUNTIME_KIND=BYO`;
- `KARS_RUNTIME_CONTRACT_VERSION=v1`;
- no GitHub/Copilot provider credential name in the Agent environment.

## Localhost is the provider boundary

The BYO app attempts a direct TCP connection to `example.com:443`; it times out.
The same process then calls the Router on `127.0.0.1:8443` and receives a real
GPT-5.6-Sol response:

```text
KARS_BYO_GPT_5_6_SOL_OK FORMAT-482 STOP_FOR_HUMAN_REVIEW
```

The response arrives as 30 Responses API events in the validated run. The
InferencePolicy reports matching compiled and loaded digests with phase
`Ready`.

This proves that replacing the agent loop does not grant direct model or
Internet access.

## What the live CRD actually accepts

The lab uses Server-side dry-run against the installed CRD:

| Runtime shape | Result |
| --- | --- |
| `MicrosoftAgentFramework` with `language: python` | Accepted |
| `MicrosoftAgentFramework` with `language: dotnet` | Rejected: supported value is `python` |
| `BYO` without `contractVersion` | Rejected: required value |

Some upstream narrative still describes MAF .NET as a deferred runtime that
reaches a degraded condition. The installed CRD used by this tutorial rejects
it at admission, before reconciliation. Treat the live schema as the
authoritative behavior.

The first-class MAF Python schema is valid, but
[`code/05`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/05)
deploys a
self-contained BYO image so the custom application artifact and entrypoint are
fully controlled and directly testable.

## Run

Keep [`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01)
running and ensure the Copilot CLI is authenticated:

```bash
jq -r .provider ~/.kars/config.json
# github-copilot

cd code/05
make test
```

The validated host is macOS arm64. The inherited setup supports macOS amd64,
Linux amd64, and Windows amd64 through Ubuntu WSL2.

The lab enforces:

```text
npm    https://packagefeedproxy.microsoft.io/npm/
PyPI   https://packagefeedproxy.microsoft.io/pypi/simple/
NuGet  https://packagefeedproxy.microsoft.io/nuget/v3/index.json
```

## Verified result

The full run proved:

| Check | Result |
| --- | --- |
| Framework-neutral workflow tests | Passed |
| MAF `GitHubCopilotAgent` model | `gpt-5.6-sol` |
| Bounded custom tool | Called once; random nonce echoed |
| MAF Python CRD shape | Accepted |
| MAF .NET CRD shape | Rejected |
| Missing BYO contract version | Rejected |
| BYO image | arm64, UID 1000, contract label `v1` |
| BYO direct egress | Denied by timeout |
| BYO provider credential | Absent from Agent environment |
| BYO Router inference | GPT-5.6-Sol response succeeded |
| InferencePolicy | Compiled digest equals loaded digest |
| Final workflow state | `STOP_FOR_HUMAN_REVIEW` |

Evidence is stored under `code/05/.evidence/<UTC timestamp>/` without secret
values.

## Official references

- [Azure/kars runtime catalog](https://github.com/Azure/kars/blob/main/docs/runtimes.md)
- [Azure/kars runtime contract](https://github.com/Azure/kars/blob/main/docs/runtimes/CONTRACT.md)
- [Azure/kars BYO quickstart](https://github.com/Azure/kars/tree/main/examples/byo-quickstart)
- [Microsoft Agent Framework GitHub Copilot samples](https://github.com/microsoft/agent-framework/tree/main/python/samples/02-agents/providers/github_copilot)
- [Microsoft Agent Framework Build Your Own Claw](https://github.com/microsoft/agent-framework/tree/main/python/samples/02-agents/harness/build_your_own_claw)
## Sandbox-escape checkpoint: pin the host-to-runtime handoff

When an Agent image is built outside the cluster, its artifact is another trust
boundary. `code/05` accepts runtime code only when it is under immutable
`/app`, is not a symlink, and has a SHA-256 digest. Mutable `/sandbox`
configuration and floating labels fail closed.

KARS provides the stable boundary around that changing application artifact:
the runtime adapter can change while inference routing, credential placement,
network restrictions, and governance remain platform-owned.

```bash
cd code/05
make unit
```

The runtime must execute the reviewed artifact, not merely a path with the same
name.
