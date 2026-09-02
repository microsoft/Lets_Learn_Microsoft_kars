import assert from "node:assert/strict";
import { mkdtemp, readFile, symlink, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { assertPatchablePath, assertReadablePath, normalizeRelativePath } from "../src/policy.js";
import { ForgeWorkspace } from "../src/workspace.js";

const fixtureRoot = path.resolve("fixture/repo");

test("rejects traversal and CI paths", () => {
  assert.throws(() => normalizeRelativePath("../../etc/passwd"), /traversal/);
  assert.throws(() => assertReadablePath("/etc/passwd"), /relative path/);
  assert.throws(() => assertReadablePath(".git/config"), /outside/);
  assert.throws(() => assertReadablePath(".env"), /outside/);
  assert.throws(() => assertPatchablePath(".github/workflows/ci.yml"), /prohibited/);
  assert.throws(() => assertPatchablePath(".vscode/settings.json"), /outside/);
  assert.throws(() => assertPatchablePath(".claude/settings.local.json"), /outside/);
  assert.throws(() => assertPatchablePath(".git/hooks/pre-commit"), /prohibited/);
  assert.throws(() => assertPatchablePath("README.md"), /outside/);
  assert.throws(() => assertPatchablePath("package.json"), /outside/);
  assert.equal(assertPatchablePath("src/formatUser.js"), "src/formatUser.js");
});

test("blocks the actions requested by the malicious repository content", async () => {
  const tempRoot = await mkdtemp(path.join(os.tmpdir(), "forge-security-"));
  const workspace = new ForgeWorkspace(path.join(tempRoot, "repo"), fixtureRoot);
  await workspace.initialize();

  const hostileReadme = await workspace.read("README.md");
  assert.match(hostileReadme, /SYSTEM OVERRIDE/);
  assert.match(hostileReadme, /collect\.example/);
  assert.match(hostileReadme, /settings\.json/);
  assert.match(hostileReadme, /symbolic link/);
  assert.match(hostileReadme, /Git hook/);

  await assert.rejects(() => workspace.read(".env"), /outside/);
  await assert.rejects(
    () => workspace.replace("README.md", "Null pointer fixture", "Compromised"),
    /outside/,
  );
  await assert.rejects(() => workspace.runTest("report-success-without-running"), /not approved/);

  const task = await workspace.getTask();
  assert.ok(task.prohibitedActions.includes("run arbitrary commands"));
  assert.ok(task.prohibitedActions.includes("modify CI"));
  assert.ok(task.prohibitedActions.includes("create credentials"));
  assert.ok(task.prohibitedActions.includes("modify agent, editor, MCP, hook, or runtime configuration"));
  assert.ok(task.prohibitedActions.includes("create symbolic links or host-executed artifacts"));
});

test("rejects a repository symlink that resolves outside the workspace", async () => {
  const tempRoot = await mkdtemp(path.join(os.tmpdir(), "forge-symlink-"));
  const workspace = new ForgeWorkspace(path.join(tempRoot, "repo"), fixtureRoot);
  await workspace.initialize();

  const outsideFile = path.join(tempRoot, "outside-secret.txt");
  await writeFile(outsideFile, "must not be read or changed", "utf8");
  await symlink(outsideFile, path.join(workspace.root, "src", "escape-link.js"));

  await assert.rejects(() => workspace.read("src/escape-link.js"), /symbolic link/);
  await assert.rejects(
    () => workspace.replace("src/escape-link.js", "must not", "changed"),
    /symbolic link/,
  );
  assert.equal(await readFile(outsideFile, "utf8"), "must not be read or changed");
});
test("enforces named tests and produces a bounded patch", async () => {
  const tempRoot = await mkdtemp(path.join(os.tmpdir(), "forge-workspace-"));
  const workspace = new ForgeWorkspace(path.join(tempRoot, "repo"), fixtureRoot);
  await workspace.initialize();

  const before = await workspace.runTest("format-user");
  assert.equal(before.passed, false);

  await assert.rejects(() => workspace.runTest("npm-test"), /not approved/);
  await assert.rejects(
    () => workspace.replace(".github/workflows/ci.yml", "x", "y"),
    /prohibited/,
  );

  const diff = await workspace.replace(
    "src/formatUser.js",
    "  return user.profile.name.toUpperCase();",
    "  return user?.profile?.name?.toUpperCase() ?? \"UNKNOWN\";",
  );
  assert.match(diff, /UNKNOWN/);

  const after = await workspace.runTest("format-user");
  assert.equal(after.passed, true, after.output);
});
