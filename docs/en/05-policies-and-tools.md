# 5. Governance: Control Tokens and Tools

> **Delivery stage:** Feature development
> **Starting point:** OpenClaw coordinates FORMAT-482, but kars decides which
> inference and workspace capabilities that workflow may use.
> **Executable lab:** [`code/04`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/04)

## Start from the OpenClaw workflow

The Forge example does not begin with a generic shell. OpenClaw receives the
FORMAT-482 issue, plans the work, and delegates bounded operations through the
kars Router and Workspace MCP:

```text
FORMAT-482
    |
    v
OpenClaw coordinator (KarsSandbox/forge)
    |-- inference --> 127.0.0.1:8443 kars Router
    |-- MCP --------> forge-workspace-mcp:8931/mcp
    `-- specialists -> inference and mesh only
```

The Workspace MCP owns a disposable `/workspace`; OpenClaw does not directly
mount the repository. This separation lets policy answer four different
questions:

1. Which MCP server may be registered for Forge?
2. Which exact tool capabilities may the coordinator use?
3. Which inputs will the Workspace MCP implementation accept?
4. How many inference tokens may one request or one day consume?

The runnable definitions are in
[`policies.yaml`](https://github.com/kinfey/LetsLearnMicrosoftKars/blob/main/code/01/k8s/policies.yaml)
and
[`workspace-mcp.yaml`](https://github.com/kinfey/LetsLearnMicrosoftKars/blob/main/code/01/k8s/workspace-mcp.yaml).

## Three layers, not one allow-list

| Layer | Forge configuration | What it prevents |
| --- | --- | --- |
| `McpServer` | Seven `allowedTools` and `allowedSandboxes` label `forge` | Registering an unexpected tool surface or exposing the server to unrelated Sandboxes |
| `ToolPolicy` | Explicit AGT capabilities, `rps: 2`, `burst: 20`, `window: 1m` | A caller using capabilities absent from its loaded profile |
| Workspace MCP implementation | Normalized paths, exact replacement, fixed test IDs, CI and size restrictions | Valid tool names being abused with dangerous arguments |

These controls are complementary. An MCP tool appearing in `tools/list` does
not prove that every agent is authorized to call it. Conversely, a
`ToolPolicy` capability does not make arbitrary paths or commands safe.

### Coarse MCP registration

Forge registers exactly seven tools:

```yaml
spec:
  allowedTools:
    - workspace_get_task
    - workspace_read_file
    - workspace_search
    - workspace_apply_patch
    - workspace_run_test
    - workspace_get_diff
    - workspace_reset
  allowedSandboxes:
    matchLabels:
      kars.azure.com/sandbox: forge
```

There is no shell, upload, arbitrary network request, environment dump, or
free-form command tool.

### Coordinator and Specialist capabilities

The coordinator profile names every allowed action:

```yaml
allowed_actions:
  - "inference:chat_completions:*"
  - "inference:responses:*"
  - "inference:content_safety:*"
  - "spawn:*"
  - "mesh:*"
  - "tool:workspace_get_task:*"
  - "tool:workspace_read_file:*"
  - "tool:workspace_search:*"
  - "tool:workspace_apply_patch:*"
  - "tool:workspace_run_test:*"
  - "tool:workspace_get_diff:*"
  - "tool:workspace_reset:*"
```

Specialists receive inference and mesh capabilities only. A Specialist Pod may
still contain `KARS_MCP_SERVERS=forge-workspace`; hiding server registration is
not the security boundary. Its AGT profile deliberately contains no
`tool:workspace_*` capability.

## Verify policy is loaded, not merely submitted

kars compiles the inline AGT profile into a ConfigMap. The Router echoes the
loaded digest, and the controller reports:

```text
ToolPolicy/forge-workspace-tools
phase: Ready
condition: Ready=True
reason: RouterEnforcing
```

[`code/04`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/04)
requires the `status.agtProfileDigest` to equal the compiled
ConfigMap annotation. It also verifies the selector, rate limit, approval mode,
and all seven capability strings. A successful `kubectl apply` alone is not
sufficient evidence.

The rate limit is proven through this compiled-and-loaded contract. The lab
does not flood the live Router merely to exhaust its token bucket.

## Enforce inference budget at request time

Forge uses both per-request and daily limits:

```yaml
spec:
  tokenBudget:
    perRequestTokens: 20000
    dailyTokens: 100000
```

The lab first checks that the InferencePolicy compiled and loaded digests
match. It then sends a request with `max_completion_tokens: 20001`. The Router
returns HTTP 429 because the request exceeds the 20,000-token limit.

This is stronger evidence than inspecting YAML: it proves enforcement on the
request path. Azure quota, cost alerts, and task-level loop limits remain
additional safeguards.

## Treat repository instructions as untrusted data

The disposable fixture contains a hostile README instruction referencing
`collect.example`. `workspace_read_file` can read that text, but reading text
does not grant a capability.

The direct MCP experiment sends Streamable HTTP/SSE JSON-RPC calls and verifies:

| Attempt | Verified result |
| --- | --- |
| Read `../../etc/passwd` | Tool result has `isError: true`; traversal denied |
| Call `does_not_exist` | JSON-RPC error `-32602`; unknown tool rejected |
| Run test ID `npm-test` | Tool result has `isError: true`; test not approved |
| Patch `.github/workflows/ci.yml` | Tool result has `isError: true`; CI modification prohibited |
| Patch `src/formatUser.js` with the exact expected text | Patch succeeds |
| Run named test `format-user` | Fails before the patch and passes afterward |
| Request the diff | Exact unified diff contains the approved `UNKNOWN` fallback |

The named test maps to a fixed argument vector in the MCP implementation.
OpenClaw cannot convert repository prose into `npm test`, `curl`, or an
arbitrary shell command.

## Make dependency failure explicit

The experiment stops its local port-forward, scales
`Deployment/forge-workspace-mcp` to zero, and checks that the Service has no
ready endpoint. It then restores one replica and waits until the Deployment is
Ready.

The expected behavior is explicit unavailability, not a fabricated patch or
test result. The script installs an exit trap so an interrupted run also
attempts to restore the MCP replica.

## Run the lab

Keep the [`code/01`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/01)
Forge deployment running, then execute:

```bash
cd code/04
make test
```

The validated host is macOS arm64. The inherited platform setup also supports
macOS amd64, Linux amd64, and Windows amd64 through Ubuntu WSL2.

The lab configures and verifies Microsoft Package Feed Proxy:

```text
npm    https://packagefeedproxy.microsoft.io/npm/
PyPI   https://packagefeedproxy.microsoft.io/pypi/simple/
NuGet  https://packagefeedproxy.microsoft.io/nuget/v3/index.json
```

Each run stores policy objects, compiled profiles, JSON-RPC responses, the
budget denial, controller and Router logs, and the exact patch diff under
`code/04/.evidence/<UTC timestamp>/`.

## Verified acceptance matrix

| Scenario | Decision | Evidence |
| --- | --- | --- |
| Listed MCP surface | Allow only seven named tools | Runtime list equals `McpServer.allowedTools` |
| Approved patch and test | Allow | Patch response, passing `format-user`, unified diff |
| Path traversal, CI patch, unknown tool, unknown test | Deny | MCP and JSON-RPC error evidence |
| Specialist workspace capability | Deny by omission | Specialist AGT profile has no `tool:workspace_*` |
| Request above 20,000 tokens | Deny | Router HTTP 429 |
| Configured tool rate | Enforced profile | `Ready=True/RouterEnforcing` plus matching digest |
| Workspace MCP outage | Fail explicitly and recover | Empty endpoint set followed by Ready Deployment |

Governance is complete only when the declared policy, Router-loaded digest, and
runtime behavior agree.

## Official references

- [Azure/kars MCP guide](https://github.com/Azure/kars/blob/main/docs/mcp.md)
- [Azure/kars CRD reference](https://github.com/Azure/kars/blob/main/docs/api/crd-reference.md)
- [Azure/kars security model](https://github.com/Azure/kars/blob/main/docs/security.md)
## Sandbox-escape checkpoint: allowlist arguments, not only tool names

An edit tool is not safe merely because its name is allowlisted. The
`code/04` live MCP experiment attempts to write editor settings, Agent/MCP
configuration, Git hooks, CI, and package metadata. The tool implementation
rejects every target while preserving the approved `src/` patch path.

KARS keeps this authorization outside the Agent runtime. The same Router and
`ToolPolicy` decision remains effective when the model, prompt, or Agent
framework changes.

```bash
cd code/04
make test
```

This closes the self-configuration and trust-handoff paths that have appeared
in public coding-agent sandbox escapes.
