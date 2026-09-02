# kars runtimes and BYO lab

[English](README.md) | [简体中文](README.zh.md)

This lab turns Chapter 6 into two executable runtime lanes built from the
OpenClaw Forge behavior established in
[`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01):

```text
Lane A: host-side framework/provider canary
Microsoft Agent Framework GitHubCopilotAgent
    -> authenticated local Copilot CLI
    -> GitHub Copilot GPT-5.6-Sol

Lane B: in-cluster production candidate
kars KarsSandbox/runtime.kind=BYO
    -> 127.0.0.1:8443 kars inference router
    -> GitHub Copilot GPT-5.6-Sol
```

The two lanes deliberately do not share credentials. Lane A uses the host
Copilot CLI session. Lane B contains no GitHub or Copilot provider credential;
the kars Router owns the provider path.

## Why there are two lanes

The referenced Microsoft Agent Framework samples expose two different
abstractions:

- `create_harness_agent(...)` expects a chat client.
- `GitHubCopilotAgent` is already a complete agent with its own Copilot CLI
  session and tool loop.

`GitHubCopilotAgent` is not a chat client and cannot be passed directly to
`create_harness_agent`. This lab therefore reuses the claw sample's explicit
planning, bounded tools, approvals, and stop-before-action principles without
claiming a nonexistent drop-in combination.

## What the lab proves

- The framework-neutral FORMAT-482 state machine ends at
  `STOP_FOR_HUMAN_REVIEW` and contains no `MERGE` or `DEPLOY` state.
- `agent-framework-github-copilot==1.0.3` installs from Microsoft Package Feed
  Proxy.
- A real `GitHubCopilotAgent` call uses model `gpt-5.6-sol`.
- The host agent has one custom tool. Its permission handler approves only
  `inspect_forge_contract` once and denies every other permission.
- A random run nonce returned only by that tool is echoed by the model, proving
  the tool actually ran.
- The live kars CRD accepts the MAF Python shape and rejects `language: dotnet`.
- The live kars CRD rejects BYO without `contractVersion`.
- The BYO image declares `org.kars.runtime.contract=v1` and runs as UID 1000.
- kars injects `KARS_MODEL=gpt-5.6-sol`,
  `KARS_RUNTIME_KIND=BYO`, and contract version `v1`.
- No GitHub/Copilot token or key name is present in the BYO agent environment.
- Direct BYO internet egress times out.
- The same BYO agent reaches GPT-5.6-Sol successfully through the localhost
  kars Router.
- The Router-loaded InferencePolicy digest matches the compiled digest.
- The BYO Pod keeps the kars security shell: agent UID 1000, Router UID 1001,
  read-only root filesystem, dropped capabilities, and egress guard.

## BYO image layout

kars mounts a disposable `emptyDir` at `/sandbox`. Application code baked into
`/sandbox` would be hidden by that mount. This image keeps immutable code under
`/app` and reserves `/sandbox` and `/tmp` for writable runtime state:

```dockerfile
WORKDIR /app
COPY app.py workflow.py ./
USER 1000
```

The app exposes:

| Endpoint | Purpose |
| --- | --- |
| `GET /healthz` | Container health |
| `GET /contract` | Sanitized runtime contract and environment names |
| `GET /direct-egress` | Proves UID 1000 cannot connect directly to the Internet |
| `POST /run` | Executes the bounded workflow and calls `/v1/responses` on the Router |

## Microsoft package sources

The lab applies and verifies:

- npm: `https://packagefeedproxy.microsoft.io/npm/`
- PyPI: `https://packagefeedproxy.microsoft.io/pypi/simple/`
- NuGet: `https://packagefeedproxy.microsoft.io/nuget/v3/index.json`

The host virtual environment and the container image both install Python
packages through Microsoft Package Feed Proxy. Upstream source rewrites are
restored when the lab exits.

## Prerequisites

- The [`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01)
  Forge environment is deployed and `Running`.
- Docker Desktop, kind, kubectl, jq, curl, Python 3.11+, and Node.js 22.
- GitHub Copilot CLI installed and authenticated.
- A Copilot plan that exposes GPT-5.6-Sol.
- kars configured with provider `github-copilot`.

Check the provider:

```bash
jq -r .provider ~/.kars/config.json
```

It must print:

```text
github-copilot
```

## Run

```bash
cd code/05
make test
```

Successful output ends with:

```text
All runtime and BYO checks passed.
Evidence: .../code/05/.evidence/<UTC timestamp>
```

## Individual commands

```bash
make unit      # Framework-neutral state-machine tests
make copilot   # Host GitHubCopilotAgent and GPT-5.6-Sol call
make deploy    # Build, validate, and deploy the kars BYO image
make inspect   # Capture sanitized kars and Pod evidence
./scripts/port-forward.sh  # Keep this running in a separate terminal
make runtime              # Test the forwarded BYO endpoint
make clean     # Delete the code/05 Sandbox and InferencePolicy
```

## Evidence

Each full run creates:

```text
.evidence/<UTC timestamp>/
├── transcript.log
├── host-copilot-agent.json
├── image-contract.json
├── maf-python-dry-run.txt
├── maf-dotnet-denial.txt
├── byo-contract-denial.txt
├── byo-sandbox.json
├── byo-inference-policy.json
├── byo-deployment-sanitized.json
├── byo-runtime-contract.json
├── byo-direct-egress.json
├── byo-model-response.json
└── byo-scope-denial.json
```

Secret values are not exported. Deployment evidence retains environment
variable names only.

## Platform support

The validated environment is macOS arm64. The inherited platform detection
also supports macOS amd64, Linux amd64, and Windows amd64 through Ubuntu WSL2.

## References

- [Azure/kars runtime catalog](https://github.com/Azure/kars/blob/main/docs/runtimes.md)
- [Azure/kars runtime contract](https://github.com/Azure/kars/blob/main/docs/runtimes/CONTRACT.md)
- [Azure/kars BYO quickstart](https://github.com/Azure/kars/tree/main/examples/byo-quickstart)
- [Microsoft Agent Framework GitHub Copilot samples](https://github.com/microsoft/agent-framework/tree/main/python/samples/02-agents/providers/github_copilot)
- [Microsoft Agent Framework Build Your Own Claw samples](https://github.com/microsoft/agent-framework/tree/main/python/samples/02-agents/harness/build_your_own_claw)
## Sandbox-escape progression: pin the runtime artifact

Earlier stages bound repository edits and tool calls. The runtime boundary must
also reject a host-produced artifact that changes meaning after review.
`validate_runtime_artifact` accepts only digest-pinned, non-symlink files under
immutable `/app`; mutable `/sandbox` configuration, traversal, symlinks, and
unpinned labels such as `latest` fail closed.

The KARS advantage is a stable security shell around different runtimes:
OpenClaw, host-side framework canaries, and BYO containers can use different
application code while retaining the Router, policy, identity, and network
boundary.

Run `make unit`. The workflow now includes
`VERIFY_IMMUTABLE_RUNTIME_ARTIFACT` before patch execution. This prevents the
host-to-runtime handoff from silently becoming a sandbox escape.
