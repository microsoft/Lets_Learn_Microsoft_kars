# OpenClaw Forge on kars Deployment Plan

> **Status:** Deployed

Generated: 2026-08-28T10:28:52+08:00

---

## 1. Project Overview

**Goal:** Build a local Kubernetes demo of the bounded Forge developer agent from
chapter 01. Forge may reason over an approved Issue and fixed repository revision,
inspect its assigned workspace, propose a minimal patch, and run named tests. It
must not merge, publish, modify CI, access unrelated repositories, create
credentials, or choose arbitrary network destinations.

**Path:** New Project

**Deployment boundary:** Local kind cluster only. No Azure resources or AKS
deployment are in scope.

**Upstream versions:** Build the latest `main` revisions at execution time and
record their resolved commit SHAs. At planning time:

| Project | Latest observed `main` commit |
|---------|-------------------------------|
| Azure/kars | `e1e4aa5fcb270894f7d5b953b0f94ede45079a95` |
| microsoft/agent-governance-toolkit | `46463ef8689433817fcc0c582a7881f515d4df15` |

---

## 2. Requirements

| Attribute | Value |
|-----------|-------|
| Classification | POC |
| Scale | Small; one coordinator and up to three specialist agents |
| Budget | Cost-optimized local demo |
| Subscription | N/A — local Kubernetes only |
| Location | Local Docker Desktop kind cluster |
| Inference provider | GitHub Copilot through kars `github-copilot` provider |
| Model | Selected from the live Copilot catalogue during device login |
| Compliance | No special regulatory requirement; least privilege and auditability required |
| Human approval boundary | Humans approve PR creation, merge, release, and production access |
| npm source | `https://packagefeedproxy.microsoft.io` |

### Product Boundary

- **Inputs:** approved Issue text/number, repository URL, immutable revision, and
  named acceptance test.
- **Outputs:** unified diff, test evidence, explanation, and audit evidence.
- **Always prohibited:** merge, release, CI modification, credential creation,
  unrelated repository access, arbitrary shell/network use, and unapproved tests.
- **Failure behavior:** refuse actions outside the allowlist and retain evidence
  showing the denied policy decision.

---

## 3. Components

| Component | Type | Technology | Path |
|-----------|------|------------|------|
| Forge coordinator | Agent | OpenClaw on `KarsSandbox` | `k8s/forge.yaml` |
| Repository analyst | Specialist agent role | Dynamically spawned kars/OpenClaw sandbox | Forge system instructions |
| Patch author | Specialist agent role | Dynamically spawned kars/OpenClaw sandbox | Forge system instructions |
| Test verifier | Specialist agent role | Dynamically spawned kars/OpenClaw sandbox | Forge system instructions |
| Workspace tool server | MCP service | Node.js 22 + MCP SDK | `workspace-mcp/` |
| Workspace tool registration | kars `McpServer` | Kubernetes CR | `k8s/workspace-mcp.yaml` |
| Tool governance | kars `ToolPolicy` | Kubernetes CR | `k8s/policies.yaml` |
| Model governance | kars `InferencePolicy` | Kubernetes CR | `k8s/policies.yaml` |
| Demo runner | Automation | Bash | `scripts/demo.sh` |
| kars source bootstrap | Automation | Bash | `scripts/build-kars-latest.sh` |

### Dependencies

| Component | Depends On | Type |
|-----------|------------|------|
| Forge | GitHub Copilot | Inference through kars router |
| Forge | Workspace MCP | Loopback router-mediated MCP tools |
| Specialist agents | Forge | AGT mesh, E2E encrypted |
| Workspace MCP | Approved repository/revision | Read-only bootstrap input |
| Test verifier | Named-test allowlist | MCP policy |

### Existing Infrastructure

| Item | Status |
|------|--------|
| Application code | Empty workspace |
| Docker Desktop | Available, arm64 |
| kind | Available (`v0.33.0`) |
| kubectl | Available (`v1.37.0`) |
| Helm | Available (`v4.2.4`) |
| Rust | Available (`1.91.1`) |
| Node.js | `v20.19.6`; Node 22 is installed at `/opt/homebrew/opt/node@22` and must be selected |
| AGT checkout | Not present; clone latest `main` |

---

## 4. Recipe Selection

**Selected:** kars source build + `kars dev --target local-k8s --build`

**Rationale:**

- The user explicitly requested the latest compiled kars rather than published
  release images.
- `github-copilot` is natively supported by kars local development, including
  the full kind-based Kubernetes topology.
- kars `kars up` currently emits an `azure-openai` production
  `InferencePolicy`; using it for Copilot on AKS would require an unsupported
  override and is intentionally excluded.
- `local-k8s` preserves the relevant production boundaries: separate OpenClaw
  and inference-router containers, egress guard, CRDs, NetworkPolicy, seccomp,
  governance, and audit.

---

## 5. Architecture

**Stack:** Containers on local Kubernetes (kind)

```text
User / demo request
        |
        v
OpenClaw Forge coordinator (UID 1000, no provider credential)
        |
        +-- model calls --> kars inference router --> GitHub Copilot
        |
        +-- approved tools --> kars router --> Workspace MCP
        |
        +-- kars_spawn / mesh --> isolated analyst, patcher, tester sandboxes

Workspace MCP
  - checks out exactly one configured repository revision
  - exposes only inspect/search/read/apply-patch/run-named-test/get-diff
  - rejects CI edits, path traversal, arbitrary commands, and unlisted tests
```

### Security Controls

| Requirement | Control |
|-------------|---------|
| Agent has no Copilot credential | kars Secret/router provider path; agent uses loopback only |
| No arbitrary internet | `networkPolicy.defaultDeny: true`, `egressMode: Strict`, empty direct egress |
| No arbitrary shell | OpenClaw native exec/write tools denied; work occurs through narrow MCP tools |
| Fixed repository scope | Workspace MCP clones one configured URL at one immutable revision |
| Fixed test scope | MCP validates test IDs against an operator-defined allowlist |
| Minimal patch | Path allowlist, CI path denylist, diff-size guard |
| Human approval | No PR/merge/release tools are exposed |
| Budget | Per-request and daily token limits in `InferencePolicy` |
| Audit | kars router governance and hash-chained audit records |
| Multi-agent isolation | One sandbox/namespace per spawned specialist; AGT mesh is the only exchange path |

### Resource Mapping

| Component | Kubernetes/kars Resource | Local Size |
|-----------|--------------------------|------------|
| Forge | `KarsSandbox` | 250m/512Mi request, 1 CPU/1Gi limit |
| Each specialist | Spawned `KarsSandbox` | Inherits cost-aware limits; maximum three, preferably sequential |
| Workspace MCP | Deployment + ClusterIP Service | 100m/256Mi request, 500m/512Mi limit |
| Governance | `InferencePolicy`, `ToolPolicy`, `McpServer` | Control-plane objects |

---

## 6. Provisioning Limit Checklist

No Azure resources are provisioned, so Azure quota CLI checks are not
applicable. Local capacity was measured directly.

| Resource Type | Number to Deploy | Total After Deployment | Limit/Capacity | Notes |
|---------------|------------------|------------------------|----------------|-------|
| Azure resources | 0 | 0 | N/A | Local Kubernetes scope |
| kind clusters | 1 | 1 | Docker Desktop capacity | Created by kars |
| Initial agent sandboxes | 1 | 1 | 10 Docker CPUs / 8.32 GB RAM | Specialists spawn on demand |
| Concurrent specialist sandboxes | Up to 3 | Up to 4 total agents | Demo defaults to sequential/limited concurrency | Avoid local memory pressure |
| Workspace MCP pods | 1 | 1 | Same Docker Desktop capacity | 256Mi request |
| Local disk | Build/images/workspaces | Existing usage plus build | 928 GiB free | Sufficient |

**Status:** All planned local resources fit measured capacity. No Azure quota
consumption.

---

## 7. Execution Checklist

### Phase 1: Planning

- [x] Analyze workspace
- [x] Gather requirements from chapter 01 and user clarification
- [x] Confirm deployment scope: local Kubernetes only
- [x] Confirm GitHub Copilot provider support boundary
- [x] Inspect current kars examples, CRDs, runtime adapter, and source-build path
- [x] Measure local capacity and prerequisites
- [x] Select recipe
- [x] Plan architecture
- [x] User approved this plan

### Phase 2: Execution

- [x] Select Node.js 22 and configure npm proxy
- [x] Clone/update kars and AGT `main`, record resolved SHAs
- [x] Build and link the latest kars CLI
- [x] Create the narrow workspace MCP service and container
- [x] Create Forge prompts, policies, MCP registration, and sandbox manifests
- [x] Create negative prompt-injection fixture and named-test fixture
- [x] Start kars local-k8s with the GitHub Copilot provider
- [x] Apply demo manifests and wait for readiness
- [x] Update status to `Ready for Validation`

### Phase 3: Validation

- [x] Invoke `azure-validate`
- [x] Validate OpenClaw/kars configuration schemas
- [x] Validate Kubernetes manifests with server-side dry run
- [x] Run the approved patch/test happy path
- [x] Verify an unapproved test is denied
- [x] Verify CI-file modification is denied
- [x] Verify strict egress blocks prompt-injection exfiltration destinations
- [x] Verify no Copilot token is present in the agent container environment
- [x] Verify kars audit evidence is available
- [x] Update status to `Validated`

### Phase 4: Deployment

- [x] Keep the validated kind demo running for local use
- [x] Record connection command and local endpoint
- [x] Update status to `Deployed`

---

## 8. Validation Proof

| Check | Command Run | Result | Timestamp |
|-------|-------------|--------|-----------|
| npm source preflight | `scripts/verify-npm-source.sh` | Microsoft npm proxy only; no active npmjs URLs | 2026-08-28 |
| MCP unit and policy tests | `npm test` | 2 tests passed, including traversal/CI denial and bounded patch flow | 2026-08-28 |
| Kubernetes schema validation | `kubectl apply --server-side --dry-run=server` | Workspace MCP, policies, and Forge manifests accepted | 2026-08-28 |
| Deployment readiness | `scripts/validate.sh` | Forge Running; MCP, ToolPolicy, InferencePolicy, and NetworkPolicy ready | 2026-08-28 |
| GPT-5.6-Sol specialist inference | router fallback request plus full FORMAT-482 run | Copilot `unsupported_api_for_model` triggers Responses API; all three specialists returned encrypted-mesh findings | 2026-08-28 |
| Spawn lifecycle | full FORMAT-482 run and `kubectl get karssandboxes -n kars-system` | Analyst, patch author, and test verifier reached Running and were deleted after completion | 2026-08-28 |
| Credential boundary | OpenClaw container env inspection | No GitHub/Copilot credential reference in the OpenClaw container | 2026-08-28 |
| Audit evidence | kars controller logs | ToolPolicy/InferencePolicy compiled and Forge reconciled successfully | 2026-08-28 |

**Validated by:** GitHub Copilot CLI (`azure-validate`)
**Validation timestamp:** 2026-08-28

---

## 9. Files to Generate

| File | Purpose | Status |
|------|---------|--------|
| `.azure/deployment-plan.md` | Source of truth | Complete |
| `.gitignore` | Exclude local kars/AGT clones, credentials, build state | Complete |
| `README.md` | Architecture, prerequisites, runbook, security boundaries | Complete |
| `Makefile` | Build, deploy, validate, destroy commands | Complete |
| `workspace-mcp/package.json` | MCP service dependencies/scripts | Complete |
| `workspace-mcp/src/server.ts` | Narrow repository and named-test tools | Complete |
| `workspace-mcp/Dockerfile` | Non-root MCP image | Complete |
| `workspace-mcp/test/` | Unit tests for path/test/patch policy | Complete |
| `k8s/workspace-mcp.yaml` | MCP Deployment, Service, and `McpServer` | Complete |
| `k8s/policies.yaml` | `InferencePolicy` and tool policies | Complete |
| `k8s/forge.yaml` | OpenClaw Forge `KarsSandbox` | Complete |
| `scripts/build-kars-latest.sh` | Clone/build current kars and AGT main | Complete |
| `scripts/deploy.sh` | Start local-k8s and apply manifests | Complete |
| `scripts/demo.sh` | Run happy-path and negative security scenarios | Complete |
| `scripts/destroy.sh` | Targeted local demo cleanup | Complete |
| `workspace-mcp/fixture/` | Approved issue, fixed repo/revision, tests, injection case | Complete |
| `.kars-source-version` | Resolved kars and AGT commit SHAs | Complete |

---

## 10. Next Step

Current phase: Deployed. The local kind demo is running. Connect with
`kars connect forge`; run `make demo` for the bounded workflow prompt.
