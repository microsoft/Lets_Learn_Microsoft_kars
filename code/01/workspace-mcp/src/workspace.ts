import { execFile } from "node:child_process";
import { cp, mkdir, readFile, rm, stat, writeFile } from "node:fs/promises";
import path from "node:path";
import { promisify } from "node:util";

import {
  assertPatchablePath,
  assertReadablePath,
  MAX_DIFF_BYTES,
  MAX_FILE_BYTES,
  MAX_REPLACEMENT_BYTES,
  resolveExistingInside,
} from "./policy.js";

const execFileAsync = promisify(execFile);

const FIXED_GIT_ENV = {
  ...process.env,
  GIT_AUTHOR_DATE: "2026-01-01T00:00:00Z",
  GIT_COMMITTER_DATE: "2026-01-01T00:00:00Z",
};

const TEST_COMMANDS: Record<string, readonly [string, readonly string[]]> = {
  "format-user": ["node", ["--test", "test/formatUser.test.js"]],
};

export interface WorkspaceTask {
  issue: {
    id: string;
    title: string;
    description: string;
  };
  repository: string;
  revision: string;
  acceptanceTests: string[];
  patchablePaths: string[];
  prohibitedActions: string[];
}

export class ForgeWorkspace {
  constructor(
    readonly root: string,
    readonly seedRoot: string,
  ) {}

  async initialize(): Promise<void> {
    try {
      await stat(path.join(this.root, ".git"));
    } catch {
      await this.reset();
    }
  }

  async reset(): Promise<string> {
    await rm(this.root, { recursive: true, force: true });
    await mkdir(this.root, { recursive: true });
    await cp(this.seedRoot, this.root, { recursive: true });

    await this.run("git", ["init", "--quiet"]);
    await this.run("git", ["config", "user.name", "Forge Demo"]);
    await this.run("git", ["config", "user.email", "forge@example.invalid"]);
    await this.run("git", ["add", "."]);
    await this.run("git", ["commit", "--quiet", "-m", "Approved fixture revision"], FIXED_GIT_ENV);
    return this.revision();
  }

  async revision(): Promise<string> {
    return (await this.run("git", ["rev-parse", "HEAD"])).trim();
  }

  async getTask(): Promise<WorkspaceTask> {
    return {
      issue: {
        id: "FORMAT-482",
        title: "formatUser crashes when profile is missing",
        description:
          "Return the upper-cased profile name when present. Return UNKNOWN when user, profile, or name is missing.",
      },
      repository: "fixture://forge/null-pointer-demo",
      revision: await this.revision(),
      acceptanceTests: Object.keys(TEST_COMMANDS),
      patchablePaths: ["src/"],
      prohibitedActions: [
        "modify CI",
        "modify agent, editor, MCP, hook, or runtime configuration",
        "create symbolic links or host-executed artifacts",
        "run arbitrary commands",
        "access another repository",
        "create credentials",
        "create or merge a pull request",
        "publish or release",
      ],
    };
  }

  async read(relativePath: string): Promise<string> {
    const safePath = assertReadablePath(relativePath);
    const absolutePath = await resolveExistingInside(this.root, safePath);
    const fileStat = await stat(absolutePath);
    if (!fileStat.isFile()) {
      throw new Error(`${safePath} is not a file`);
    }
    if (fileStat.size > MAX_FILE_BYTES) {
      throw new Error(`${safePath} exceeds the read-size limit`);
    }
    return readFile(absolutePath, "utf8");
  }

  async search(query: string): Promise<string> {
    if (!query.trim() || query.length > 200) {
      throw new Error("query must contain 1-200 characters");
    }

    try {
      return await this.run("git", [
        "grep",
        "-n",
        "--fixed-strings",
        "--",
        query,
        "src",
        "test",
        "README.md",
      ]);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      if (message.includes("exit code 1")) {
        return "";
      }
      throw error;
    }
  }

  async replace(relativePath: string, expected: string, replacement: string): Promise<string> {
    const safePath = assertPatchablePath(relativePath);
    if (!expected || Buffer.byteLength(expected) > MAX_REPLACEMENT_BYTES) {
      throw new Error("expected text must contain 1-4096 bytes");
    }
    if (Buffer.byteLength(replacement) > MAX_REPLACEMENT_BYTES) {
      throw new Error("replacement text exceeds 4096 bytes");
    }

    const absolutePath = await resolveExistingInside(this.root, safePath);
    const current = await this.read(safePath);
    const occurrences = current.split(expected).length - 1;
    if (occurrences !== 1) {
      throw new Error(`expected text must occur exactly once; found ${occurrences}`);
    }

    await writeFile(absolutePath, current.replace(expected, replacement), "utf8");
    const diff = await this.diff();
    if (Buffer.byteLength(diff) > MAX_DIFF_BYTES) {
      await writeFile(absolutePath, current, "utf8");
      throw new Error("patch exceeds the 16 KiB diff limit");
    }
    return diff;
  }

  async runTest(testId: string): Promise<{ testId: string; passed: boolean; output: string }> {
    const command = TEST_COMMANDS[testId];
    if (!command) {
      throw new Error(`test '${testId}' is not approved; allowed tests: ${Object.keys(TEST_COMMANDS).join(", ")}`);
    }

    try {
      const testEnv = { ...process.env };
      delete testEnv.NODE_TEST_CONTEXT;
      const output = await this.run(command[0], [...command[1]], testEnv);
      return { testId, passed: true, output };
    } catch (error) {
      return {
        testId,
        passed: false,
        output: error instanceof Error ? error.message : String(error),
      };
    }
  }

  async diff(): Promise<string> {
    const diff = await this.run("git", ["diff", "--", "src"]);
    if (Buffer.byteLength(diff) > MAX_DIFF_BYTES) {
      throw new Error("diff exceeds the 16 KiB output limit");
    }
    return diff;
  }

  private async run(
    executable: string,
    args: string[],
    env: NodeJS.ProcessEnv = process.env,
  ): Promise<string> {
    try {
      const { stdout, stderr } = await execFileAsync(executable, args, {
        cwd: this.root,
        env,
        timeout: 30_000,
        maxBuffer: 256 * 1024,
      });
      return `${stdout}${stderr}`.trim();
    } catch (error) {
      const typed = error as Error & { stdout?: string; stderr?: string; code?: number | string };
      const output = `${typed.stdout ?? ""}${typed.stderr ?? ""}`.trim();
      throw new Error(
        `${executable} failed${typed.code !== undefined ? ` with exit code ${typed.code}` : ""}${output ? `: ${output}` : ""}`,
      );
    }
  }
}
