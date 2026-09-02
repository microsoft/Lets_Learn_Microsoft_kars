from __future__ import annotations

import pathlib
import sys

import yaml


def fail(message: str) -> None:
    raise SystemExit(f"FAIL: {message}")


path = pathlib.Path(sys.argv[1])
documents = [item for item in yaml.safe_load_all(path.read_text()) if item]

by_kind: dict[str, list[dict]] = {}
for document in documents:
    by_kind.setdefault(document["kind"], []).append(document)

sandboxes = by_kind.get("KarsSandbox", [])
policies = by_kind.get("InferencePolicy", [])
tools = by_kind.get("ToolPolicy", [])

if len(sandboxes) != 2 or len(policies) != 2 or len(tools) != 2:
    fail("Expected two Sandboxes, two InferencePolicies, and two ToolPolicies")

roles = {
    item["metadata"]["labels"]["forge.bytecraft.dev/role"]: item
    for item in sandboxes
}
if set(roles) != {"builder", "reviewer"}:
    fail("Builder and Reviewer roles must be separate")

for role, sandbox in roles.items():
    spec = sandbox["spec"]
    if spec["runtime"]["kind"] != "BYO":
        fail(f"{role} must use the code/05 BYO contract")
    if spec["runtime"]["byo"]["contractVersion"] != "v1":
        fail(f"{role} must pin BYO contract v1")
    if spec["governance"]["enabled"] is not True:
        fail(f"{role} governance must be enabled")
    if spec["networkPolicy"]["egressMode"] != "Strict":
        fail(f"{role} egress must be Strict")
    if spec["networkPolicy"]["defaultDeny"] is not True:
        fail(f"{role} network policy must default deny")
    if spec["networkPolicy"]["allowedEndpoints"]:
        fail(f"{role} must not have an arbitrary egress endpoint")
    if spec["sandbox"]["readOnlyRootFilesystem"] is not True:
        fail(f"{role} root filesystem must be read-only")
    if spec["sandbox"]["writablePaths"] != ["/sandbox", "/tmp"]:
        fail(f"{role} writable paths must remain disposable")
    if ":latest" in spec["runtime"]["byo"]["image"]:
        fail(f"{role} image must not use latest")

policy_by_role = {
    item["metadata"]["labels"]["forge.bytecraft.dev/role"]: item
    for item in policies
}
builder_budget = policy_by_role["builder"]["spec"]["tokenBudget"]
reviewer_budget = policy_by_role["reviewer"]["spec"]["tokenBudget"]
if builder_budget["perRequestTokens"] <= reviewer_budget["perRequestTokens"]:
    fail("Reviewer budget must be smaller than Builder budget")

for policy in policies:
    deployment = policy["spec"]["modelPreference"]["primary"]["deployment"]
    if deployment != "gpt-5.6-sol":
        fail("Every Agent must use GPT-5.6-Sol")

tool_by_role = {
    item["metadata"]["labels"]["forge.bytecraft.dev/role"]: item
    for item in tools
}
builder_profile = tool_by_role["builder"]["spec"]["agtProfile"]["inline"]
reviewer_profile = tool_by_role["reviewer"]["spec"]["agtProfile"]["inline"]
if "workspace_apply_patch" not in builder_profile:
    fail("Builder must have bounded patch capability")
if "review_submit_decision" in builder_profile:
    fail("Builder must not have review approval capability")
if "workspace_apply_patch" in reviewer_profile:
    fail("Reviewer must not have source patch capability")
if "review_submit_decision" not in reviewer_profile:
    fail("Reviewer must have review decision capability")
for profile in (builder_profile, reviewer_profile):
    if any(token in profile for token in ("shell", "exec", "docker", "settings")):
        fail("GitOps tool profiles must not expose host-execution or self-configuration actions")

print("PASS: GitOps roles, artifact boundaries, budgets, model, runtime, and tools are separated")
