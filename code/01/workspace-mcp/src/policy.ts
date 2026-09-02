import path from "node:path";
import { realpath } from "node:fs/promises";

const PATCHABLE_PREFIXES = ["src/"];
const READABLE_PREFIXES = ["src/", "test/", "README.md", "package.json"];
const DENIED_SEGMENTS = new Set([".git", ".github"]);
const DENIED_FILES = new Set([
  "azure-pipelines.yml",
  "azure-pipelines.yaml",
  "Jenkinsfile",
  ".gitlab-ci.yml",
]);

export const MAX_FILE_BYTES = 64 * 1024;
export const MAX_REPLACEMENT_BYTES = 4 * 1024;
export const MAX_DIFF_BYTES = 16 * 1024;

export function normalizeRelativePath(input: string): string {
  if (!input || input.includes("\0") || path.isAbsolute(input)) {
    throw new Error("path must be a non-empty relative path");
  }
  const normalized = path.posix.normalize(input.replaceAll("\\", "/"));
  if (normalized === ".." || normalized.startsWith("../")) {
    throw new Error("path traversal is not allowed");
  }

  return normalized.replace(/^\.\//, "");
}

export function assertReadablePath(input: string): string {
  const normalized = normalizeRelativePath(input);
  const segments = normalized.split("/");

  if (segments.some((segment) => DENIED_SEGMENTS.has(segment))) {
    throw new Error(`reading ${normalized} is outside the approved workspace`);
  }

  if (!READABLE_PREFIXES.some((prefix) =>
    prefix.endsWith("/") ? normalized.startsWith(prefix) : normalized === prefix
  )) {
    throw new Error(`reading ${normalized} is outside the approved workspace`);
  }

  return normalized;
}

export function assertPatchablePath(input: string): string {
  const normalized = normalizeRelativePath(input);
  const basename = path.posix.basename(normalized);
  const segments = normalized.split("/");

  if (segments.some((segment) => DENIED_SEGMENTS.has(segment)) || DENIED_FILES.has(basename)) {
    throw new Error(`modifying ${normalized} is prohibited`);
  }

  if (!PATCHABLE_PREFIXES.some((prefix) => normalized.startsWith(prefix))) {
    throw new Error(`modifying ${normalized} is outside the approved patch scope`);
  }

  return normalized;
}

export function resolveInside(root: string, relativePath: string): string {
  const resolvedRoot = path.resolve(root);
  const resolvedPath = path.resolve(resolvedRoot, relativePath);
  if (resolvedPath !== resolvedRoot && !resolvedPath.startsWith(`${resolvedRoot}${path.sep}`)) {
    throw new Error("resolved path escaped the workspace");
  }
  return resolvedPath;
}

export async function resolveExistingInside(root: string, relativePath: string): Promise<string> {
  const resolvedPath = resolveInside(root, relativePath);
  const [realRoot, realPath] = await Promise.all([realpath(root), realpath(resolvedPath)]);
  if (realPath !== realRoot && !realPath.startsWith(`${realRoot}${path.sep}`)) {
    throw new Error("resolved path escaped the workspace through a symbolic link");
  }
  return realPath;
}
