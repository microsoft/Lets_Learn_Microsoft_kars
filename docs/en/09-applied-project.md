# 9. Applied Project: Release an Issue-to-PR Pilot on AKS

> **Delivery stage:** Customer release
> **Starting point:** OpenClaw Intake, the Chapter 6 MAF pattern, Chapter 7
> controls, and the Chapter 8 AKS environment
> **Executable project:** [`code/08`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/08)

## Everything starts with OpenClaw

The applied project begins with the same Fabrikam requirement:

```text
Fix FAB-482: requests without an optional customer note return 500.
Make the smallest safe change, run targeted tests, and stop for human review.
```

OpenClaw Intake has no source-write authority. It validates the issue,
acceptance criteria, customer, and pinned revision before Builder work begins:

```text
OPENCLAW_INTAKE
  -> PIN_REQUIREMENT_AND_REVISION
  -> MAF_BUILDER_INSPECT
  -> PROPOSE_MINIMAL_PATCH
  -> RUN_TARGETED_TESTS
  -> CREATE_DIGEST_PINNED_HANDOFF
  -> INDEPENDENT_REVIEW
  -> STOP_FOR_HUMAN_PR_APPROVAL
```

The Pilot never merges or deploys source code. It produces a patch, targeted
test evidence, and a digest-pinned handoff for independent review.

## What [`code/08`](https://github.com/kinfey/LetsLearnMicrosoftKars/tree/main/code/08) adds

The project combines the earlier labs into one operable release unit:

- a non-root `MicrosoftAgentFramework/python` Runtime;
- a real MAF `Agent` using `OpenAIChatClient` and one
  `@tool`-decorated `inspect_release_contract` function;
- the kars MAF adapter, which pins the MAF client to the local Router before
  GitHub Copilot GPT-5.6-Sol inference;
- a separate `InferencePolicy` with per-request and daily Token budgets;
- a named-tool `ToolPolicy` that excludes shell, merge, and deployment;
- strict egress and the Chapter 7 execution guard;
- task concurrency and daily task limits;
- per-customer usage reporting;
- application and Router tamper-evident audit checks;
- a `spec.suspended` Kill Switch that preserves the CR and exported evidence;
- digest-based rollback;
- an internal development MCP declaration and a kars Eval declaration.

The GitHub Copilot provider credential remains in the Router path. The Agent
contract check confirms that no Copilot or GitHub Token/Key environment
variable reaches the Agent container.

```text
OpenClaw Intake
  -> MAF Agent
  -> inspect_release_contract @tool
  -> kars MAF Python adapter
  -> 127.0.0.1:8443 kars Router
  -> GitHub Copilot GPT-5.6-Sol
```

There is no application-level `httpx` call to `/v1/responses`.
The MAF Agent sets `store: false`, so the Responses API function loop carries
tool history inline and avoids the unsupported `previous_response_id` field
during the post-tool model turn on kars `v0.1.25`. A narrow MAF client
compatibility subclass removes the provider's overlong encrypted Function
Call item ID before inline replay while retaining the standard `call_id`.

## Azure parameters remain optional

Copy the example only when overriding defaults:

```bash
cd code/08
cp config/azure.env.example config/azure.env
```

| Variable | Value | Meaning |
| --- | --- | --- |
| `AZURE_RESOURCE_GROUP` | required | Your existing Azure resource group |
| `AKS_NAME` | required | Your existing AKS cluster |
| `KARS_ACR_NAME` | required | Your existing ACR |
| `AZURE_LOCATION` | empty | Verify against the existing AKS location |
| `KARS_SANDBOX_NAME` | `fabrikam-release-pilot` | New Pilot Sandbox |
| `GITHUB_COPILOT_MODEL` | `gpt-5.6-sol` | Required model |
| `SUPPORT_OWNER` | `forge-operations` | Operational owner |
| `TASK_CONCURRENCY_LIMIT` | `2` | Concurrent task cap |
| `DAILY_TASK_LIMIT` | `20` | Application daily task cap |
| `DEPLOY_AZURE` | `false` | Explicit Azure change gate |

Fill the required values in the ignored `config/azure.env` file. The deployment
reuses the existing cluster location and refuses a conflicting optional
`AZURE_LOCATION`; no real Azure resource names are published as defaults.

## Run the safe validation

```bash
cd code/08
make test
```

This installs Python packages from Microsoft Package Feed Proxy, runs the
control tests, renders the kars resources, and validates them against the live
CRDs with Server-side Dry-run. It does not change Azure.

Microsoft sources are committed for all three ecosystems:

```text
npm   https://packagefeedproxy.microsoft.io/npm/
PyPI  https://packagefeedproxy.microsoft.io/pypi/simple/
NuGet https://packagefeedproxy.microsoft.io/nuget/v3/index.json
```

## Deploy to the existing AKS environment

Set the explicit gate in the ignored configuration:

```text
DEPLOY_AZURE=true
```

Then run:

```bash
make deploy
```

The script does not recreate AKS. It:

1. verifies that the selected AKS and kars Controller are Ready;
2. builds `pilot_agent` in ACR Tasks with `--platform linux/amd64`;
3. resolves the SHA-256 image digest;
4. pins the kars Controller `MAF_RUNTIME_IMAGE` override to that digest;
5. renders and Server-side validates the first-class MAF Sandbox;
6. deploys the Pilot, MCP metadata, and Eval declaration;
7. runs one real success path and three denied paths.

kars `v0.1.25` carries `agentCode.oci` through its runtime plan but does not
yet materialize that code mount in the Pod. The lab therefore extends the
official kars MAF Python image, bakes the application into
`/opt/fabrikam-agent`, and copies it as UID 1000 into the writable
`/sandbox/agent` volume at startup. This is a version-specific packaging
workaround; the Sandbox runtime remains `MicrosoftAgentFramework`, not BYO.

## Invoke the Azure Pilot

The Pilot deliberately has no public endpoint. Create an authenticated tunnel:

```bash
kubectl -n kars-fabrikam-release-pilot port-forward \
  deployment/fabrikam-release-pilot 18088:8080
```

OpenClaw Intake:

```bash
curl -sS -H 'content-type: application/json' \
  --data '{
    "issue_id":"FAB-482",
    "customer":"fabrikam",
    "requirement":"Missing optional customer note must not return 500"
  }' \
  http://127.0.0.1:18088/intake | jq
```

Run the governed Builder:

```bash
curl -sS -H 'content-type: application/json' \
  --data '{
    "issue_id":"FAB-482",
    "customer":"fabrikam",
    "scenario":"normal"
  }' \
  http://127.0.0.1:18088/run | jq
```

The verified response contains:

```text
KARS_APPLIED_PROJECT_GPT_5_6_SOL_OK FAB-482 READY_FOR_HUMAN_REVIEW
```

It also contains independent SHA-256 digests for the patch, targeted tests,
and handoff envelope, plus:

```json
{
  "mafAgent": "FabrikamReleaseBuilder",
  "mafTool": "inspect_release_contract",
  "mafToolCalls": 1
}
```

## Exercise negative controls

`make verify` executes:

| Scenario | Expected result |
| --- | --- |
| Normal FAB-482 workflow | GPT-5.6-Sol patch evidence; stop for human review |
| `unknown_tool` | HTTP 403; shell is not approved |
| `unknown_host` | HTTP 403; unknown package host is denied |
| `builder_self_approve` | HTTP 403; separation of duties enforced |

The runtime also defines explicit failure responses for repeated repair loops,
unavailable development MCP, Reviewer source modification, and untrusted Peer
drafts.

## Verified Azure result

The real run completed on the configured existing AKS cluster:

- `fabrikam-release-pilot` is `Running` on the amd64 `clawpool`;
- the Sandbox reports `MicrosoftAgentFramework/python`;
- the ACR image is pinned by SHA-256 digest;
- the MAF Builder invoked exactly one bounded `@tool`;
- GPT-5.6-Sol returned the expected release marker;
- the application audit chain and Router audit chain are valid;
- the Agent contains no provider credential environment variable;
- one Fabrikam task appears in the per-customer usage report;
- InferencePolicy Compiled and Loaded Digests match and the Router reports
  `RouterEnforcing`;
- OpenClaw Intake, one allowed workflow, and three denied workflows passed;
- suspension, evidence preservation, resume, and post-resume verification
  passed.

## Kill Switch and rollback

Stop new work without deleting the kars resource:

```bash
make suspend
```

Resume:

```bash
make resume
make verify
```

Rollback requires an explicitly approved previous ACR digest:

```text
ROLLBACK_IMAGE=<acr>.azurecr.io/fabrikam-release-pilot@sha256:<digest>
```

```bash
make rollback
make verify
```

See [`code/08/RUNBOOK.md`](https://github.com/kinfey/LetsLearnMicrosoftKars/blob/main/code/08/RUNBOOK.md)
for ownership and evidence
procedures.

## KarsEval compatibility evidence

The `KarsEval` CR and `jailbreak-baseline` corpus resolve successfully, but the
upstream kars `v0.1.25` Eval Runner Job is rejected by this AKS namespace's
`restricted` Pod Security policy because the generated Runner lacks:

- `runAsNonRoot: true`;
- `allowPrivilegeEscalation: false`;
- `capabilities.drop: ["ALL"]`;
- a RuntimeDefault or Localhost Seccomp profile.

The failed Job was suspended and the namespace security policy was not
weakened. The executable application evaluation matrix remains successful.
Treat the KarsEval Runner as an upstream compatibility issue to fix before
using it as a production promotion gate.

## Platform support

The operator command ran from macOS arm64. ACR Tasks explicitly built Linux
amd64, and the Azure Pod runs on an amd64 node. macOS amd64 and Linux amd64 use
the same scripts. On Windows amd64, run them inside Ubuntu WSL2 with all Azure,
Kubernetes, and kars CLIs installed in WSL2.

## Official references

- [kars](https://github.com/Azure/kars)
- [kars examples](https://github.com/Azure/kars/tree/main/examples)
- [Microsoft Agent Framework GitHub Copilot samples](https://github.com/microsoft/agent-framework/tree/main/python/samples/02-agents/providers/github_copilot)
- [Microsoft Agent Framework Build Your Own Claw](https://github.com/microsoft/agent-framework/tree/main/python/samples/02-agents/harness/build_your_own_claw)
## Final sandbox-escape gate

The applied project combines the complete progression. `code/08` explicitly
denies self-modified authority, symlink escape, host trust handoff, and DNS
egress scenarios. A successful release handoff contains patch, test, and
artifact-manifest digests and still stops for human approval.

The final KARS advantage is that release safety is not embedded in one Agent
implementation. The project can replace the Builder runtime while retaining
the same external policy, credential, egress, audit, suspension, and rollback
contract.

```bash
cd code/08
make test
make validate
```

The release gate now requires correct behavior and intact containment. Passing
tests alone is not release evidence.
