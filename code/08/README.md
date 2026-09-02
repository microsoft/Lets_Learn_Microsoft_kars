# Chapter 9 lab: OpenClaw-first MAF release project

This lab combines the Chapter 6 MAF pattern, Chapter 7 controls, and Chapter 8
AKS promotion into a reproducible Issue-to-PR pilot on the existing AKS
cluster:

```text
OpenClaw Intake
  -> MAF Agent + OpenAIChatClient + inspect_release_contract @tool
  -> kars MAF adapter
  -> local kars Router
  -> GitHub Copilot GPT-5.6-Sol
```

The application contains no direct Router HTTP call. The kars adapter pins the
MAF OpenAI client to `127.0.0.1:8443`, while the provider credential remains
only in the Router path. The MAF Agent sets `store: false`, so its Responses
API function loop carries tool history inline instead of sending the
`previous_response_id` field that the kars `v0.1.25` GitHub Copilot adapter
does not support. A small MAF client compatibility subclass also removes the
provider's overlong encrypted Function Call item ID before inline replay while
preserving the standard `call_id`.

Safe local validation:

```bash
cd code/08
make test
```

Deploy to an existing environment:

```bash
cp config/azure.env.example config/azure.env
# Fill AZURE_RESOURCE_GROUP, AKS_NAME, and KARS_ACR_NAME.
# Then set DEPLOY_AZURE=true.
make deploy
```

Azure resource names are required user inputs and are never bound to a real
deployment in this repository. The script verifies the existing AKS location.
The ACR Task explicitly builds Linux amd64 and the MAF runtime is selected by
digest.

kars `v0.1.25` exposes `agentCode.oci` in the CRD/runtime plan but does not yet
materialize that code mount in the Pod. This lab therefore extends the official
kars MAF Python image, bakes the application into `/opt/fabrikam-agent`, copies
it as UID 1000 into the writable `/sandbox/agent` volume at startup, and sets
the Controller `MAF_RUNTIME_IMAGE` override. The Sandbox remains a first-class
`MicrosoftAgentFramework/python` runtime, not BYO.

`make verify` runs the OpenClaw Intake, one successful GPT-5.6-Sol workflow,
proves exactly one bounded MAF tool call, and checks denials for shell/unknown
tools, unknown egress, and Builder self-approval. See `RUNBOOK.md` for
suspension, evidence, and rollback.

The Azure deployment was verified on the amd64 `clawpool`. The application and
Router audit chains passed, and the InferencePolicy Compiled/Loaded Digests
converged. The `KarsEval` declaration resolves its corpus, but the upstream
`v0.1.25` Runner Job is blocked by AKS restricted Pod Security because its
generated Pod lacks the required restricted security context. The Job is
suspended; the namespace policy is not weakened.
## Full sandbox-escape release gate

This final stage combines the earlier controls. The release API explicitly
denies `self_modify_authority`, `symlink_escape`, `host_trust_handoff`, and
`dns_egress` scenarios. The successful path accepts only a normalized
`src/` artifact, rejects symlinks, and adds its manifest digest to the
Builder-to-Reviewer handoff.

The KARS advantage in the completed scenario is consistency: the same
declarative runtime, inference, tool, network, identity, suspension, and audit
boundaries remain in force from local validation through AKS release.

Run `make test` for the local gate and `make validate` for the rendered KARS
contract. A release is not ready merely because tests pass: authority,
artifact, egress, role separation, audit, suspension, and rollback boundaries
must remain intact.
