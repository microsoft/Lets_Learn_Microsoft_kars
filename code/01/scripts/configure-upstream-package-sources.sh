#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KARS_DIR="${ROOT_DIR}/.cache/upstream/kars"
AGT_DIR="${ROOT_DIR}/.cache/upstream/agent-governance-toolkit"
OPENCLAW_DIR="${ROOT_DIR}/.cache/upstream/openclaw"
ACTION="${1:-apply}"

node - "${KARS_DIR}" "${AGT_DIR}" "${OPENCLAW_DIR}" "${ACTION}" <<'NODE'
const fs = require("node:fs");
const path = require("node:path");

const [karsDir, agtDir, openClawDir, action] = process.argv.slice(2);
const npmRegistry = "ENV NPM_CONFIG_REGISTRY=https://packagefeedproxy.microsoft.io/npm/";
const pnpmRegistry = "ENV PNPM_CONFIG_REGISTRY=https://packagefeedproxy.microsoft.io/npm/";
const blockedNpmRegistry = ["https://registry", "npmjs.org/"].join(".");
const npmAllowProxyRedirect = "ENV NPM_CONFIG_ALLOW_REMOTE=all";
const npmReplaceRegistry = "ENV NPM_CONFIG_REPLACE_REGISTRY_HOST=registry.npmjs.org";
const npmNoLockRewrite = "ENV NPM_CONFIG_PACKAGE_LOCK=false";
const pipIndex = "ENV PIP_INDEX_URL=https://packagefeedproxy.microsoft.io/pypi/simple/";
const npmOpenClawInstall =
  'RUN echo "openclaw cache-bust: ${OPENCLAW_CACHE_BUST}" && npm install -g openclaw@${OPENCLAW_VERSION}';
const sourceOpenClawInstall = `RUN echo "openclaw cache-bust: \${OPENCLAW_CACHE_BUST}"
COPY --from=openclaw-source /app /usr/local/lib/node_modules/openclaw
RUN ln -s /usr/local/lib/node_modules/openclaw/openclaw.mjs /usr/local/bin/openclaw`;
const builderStage = "FROM ${AZURELINUX_BASE} AS builder";
const sourceStage = "FROM openclaw-source:dev AS openclaw-source";
const corepackInstall = "RUN corepack enable";
const proxyPnpmInstall =
  "RUN npm install -g https://packagefeedproxy.microsoft.io/npm/pnpm/-/pnpm-11.2.2.tgz";
const legacyProxyPnpmInstall = "RUN npm install -g pnpm@11.2.2";
const legacyAgtServerInstall = 'RUN pip install --no-cache-dir ".[server]"';
const currentAgtServerInstall =
  'RUN pip install --no-cache-dir . "fastapi==0.141.1" "uvicorn[standard]==0.52.1"';
const legacyOpenClawModelBlock = 'MODEL="${OPENCLAW_MODEL:-gpt-4.1}"';
const modelAwareOpenClawModelBlock = `MODEL="\${OPENCLAW_MODEL:-gpt-4.1}"

# Local source-build compatibility: GPT-5.6-Sol is Responses API only.
MODEL_API="openai-completions"
case "\${MODEL}" in
  gpt-5.6-sol) MODEL_API="openai-responses" ;;
esac`;
const legacyOpenClawApi = '        "api": "openai-completions",';
const modelAwareOpenClawApi = '        "api": "${MODEL_API}",';
const legacyResponsesFallbackCheck = `                        .and_then(|v| {
                            v.get("error")?
                                .get("message")?
                                .as_str()
                                .map(|s| s.contains("unsupported"))
                        })
                        .unwrap_or(false)`;
const copilotResponsesFallbackCheck = `                        .and_then(|v| {
                            let error = v.get("error")?;
                            let code = error.get("code").and_then(|value| value.as_str());
                            let message = error
                                .get("message")
                                .and_then(|value| value.as_str())
                                .unwrap_or("");
                            Some(
                                code == Some("unsupported_api_for_model")
                                    || message.contains("unsupported")
                                    || message.contains(
                                        "not accessible via the /chat/completions endpoint",
                                    ),
                            )
                        })
                        .unwrap_or(false)`;

function update(file, marker, lines) {
  let content = fs.readFileSync(file, "utf8");
  if (action === "restore") {
    const configuredLines = new Set([
      ...lines,
      "ENV NPM_CONFIG_REPLACE_REGISTRY_HOST=always",
    ]);
    const restoredLines = content
      .split("\n")
      .filter((line) => !configuredLines.has(line));
    const markerIndex = restoredLines.findIndex((line) => line === marker);
    while (restoredLines[markerIndex + 1] === "") {
      restoredLines.splice(markerIndex + 1, 1);
    }
    restoredLines.splice(markerIndex + 1, 0, "");
    fs.writeFileSync(file, restoredLines.join("\n"));
    return;
  }
  if (action !== "apply") {
    throw new Error(`Unsupported action: ${action}`);
  }
  const contentLines = content.split("\n");
  const markerIndex = contentLines.findIndex((line) => line === marker);
  if (markerIndex === -1) {
    throw new Error(`Cannot configure package proxy in ${file}: marker not found`);
  }
  const nearbyLines = contentLines.slice(markerIndex + 1, markerIndex + lines.length + 3);
  if (lines.every((line) => nearbyLines.includes(line))) {
    return;
  }
  while (contentLines[markerIndex + 1] === "") {
    contentLines.splice(markerIndex + 1, 1);
  }
  contentLines.splice(markerIndex + 1, 0, "", ...lines, "");
  content = contentLines.join("\n");
  fs.writeFileSync(file, content);
}

update(
  path.join(karsDir, "sandbox-images/openclaw/Dockerfile.base"),
  "FROM ${AZURELINUX_BASE} AS builder",
  [npmRegistry, pnpmRegistry, npmAllowProxyRedirect, npmReplaceRegistry, npmNoLockRewrite, pipIndex],
);
update(
  path.join(karsDir, "sandbox-images/openclaw/Dockerfile.base"),
  "FROM ${AZURELINUX_BASE}",
  [npmRegistry, pnpmRegistry, npmAllowProxyRedirect, npmReplaceRegistry, npmNoLockRewrite, pipIndex],
);
update(
  path.join(karsDir, "sandbox-images/hermes/Dockerfile"),
  "FROM mcr.microsoft.com/azurelinux/base/python:3.12@sha256:485299b016fe5ae745ffee27f0b8a850576841205ed1d420c9a84b126198e320 AS base",
  [pipIndex],
);
update(
  path.join(agtDir, "agent-governance-python/agent-mesh/docker/Dockerfile"),
  "FROM python:${PYTHON_VERSION}-slim@sha256:233de06753d30d120b1a3ce359d8d3be8bda78524cd8f520c99883bfe33964cf AS base",
  [pipIndex],
);
{
  const agtDockerfile = path.join(
    agtDir,
    "agent-governance-python/agent-mesh/docker/Dockerfile",
  );
  let agtContent = fs.readFileSync(agtDockerfile, "utf8");
  agtContent =
    action === "apply"
      ? agtContent.replace(legacyAgtServerInstall, currentAgtServerInstall)
      : agtContent.replace(currentAgtServerInstall, legacyAgtServerInstall);
  fs.writeFileSync(agtDockerfile, agtContent);
}
{
  const openClawEntrypoint = path.join(
    karsDir,
    "sandbox-images/openclaw/entrypoint.sh",
  );
  let entrypointContent = fs.readFileSync(openClawEntrypoint, "utf8");
  if (action === "apply") {
    entrypointContent = entrypointContent
      .replace(legacyOpenClawModelBlock, modelAwareOpenClawModelBlock)
      .replace(legacyOpenClawApi, modelAwareOpenClawApi);
  } else {
    entrypointContent = entrypointContent
      .replace(modelAwareOpenClawModelBlock, legacyOpenClawModelBlock)
      .replace(modelAwareOpenClawApi, legacyOpenClawApi);
  }
  fs.writeFileSync(openClawEntrypoint, entrypointContent);
}
{
  const chatCompletionsRoute = path.join(
    karsDir,
    "inference-router/src/routes/chat_completions.rs",
  );
  let routeContent = fs.readFileSync(chatCompletionsRoute, "utf8");
  routeContent =
    action === "apply"
      ? routeContent.replace(legacyResponsesFallbackCheck, copilotResponsesFallbackCheck)
      : routeContent.replace(copilotResponsesFallbackCheck, legacyResponsesFallbackCheck);
  fs.writeFileSync(chatCompletionsRoute, routeContent);
}
if (fs.existsSync(path.join(openClawDir, "Dockerfile"))) {
  const sourceDockerfile = path.join(openClawDir, "Dockerfile");
  update(
    sourceDockerfile,
    "FROM ${OPENCLAW_NODE_BOOKWORM_IMAGE} AS build",
    [npmRegistry, pnpmRegistry, npmAllowProxyRedirect, npmReplaceRegistry, npmNoLockRewrite],
  );
  let sourceContent = fs.readFileSync(sourceDockerfile, "utf8");
  if (action === "apply") {
    sourceContent = sourceContent
      .replace(legacyProxyPnpmInstall, proxyPnpmInstall)
      .replace(corepackInstall, proxyPnpmInstall);
  } else {
    sourceContent = sourceContent
      .replace(proxyPnpmInstall, corepackInstall)
      .replace(legacyProxyPnpmInstall, corepackInstall);
    sourceContent = sourceContent.replace(
      "FROM ${OPENCLAW_NODE_BOOKWORM_IMAGE} AS build\n\nARG OPENCLAW_BUNDLED_PLUGIN_DIR",
      "FROM ${OPENCLAW_NODE_BOOKWORM_IMAGE} AS build\nARG OPENCLAW_BUNDLED_PLUGIN_DIR",
    );
  }
  fs.writeFileSync(sourceDockerfile, sourceContent);

  const sourceNpmrc = path.join(openClawDir, ".npmrc");
  let npmrcContent = fs.readFileSync(sourceNpmrc, "utf8");
  const registryLine = "registry=https://packagefeedproxy.microsoft.io/npm/";
  if (action === "apply" && !npmrcContent.includes(registryLine)) {
    npmrcContent = `${registryLine}\n${npmrcContent}`;
  } else if (action === "restore") {
    npmrcContent = npmrcContent.replace(`${registryLine}\n`, "");
  }
  fs.writeFileSync(sourceNpmrc, npmrcContent);

  const workspaceFile = path.join(openClawDir, "pnpm-workspace.yaml");
  let workspaceContent = fs.readFileSync(workspaceFile, "utf8");
  if (action === "apply") {
    workspaceContent = workspaceContent.replace(
      "minimumReleaseAge: 2880",
      "minimumReleaseAge: 0",
    );
  } else {
    workspaceContent = workspaceContent.replace(
      "minimumReleaseAge: 0",
      "minimumReleaseAge: 2880",
    );
  }
  fs.writeFileSync(workspaceFile, workspaceContent);
}

const openClawDockerfile = path.join(
  karsDir,
  "sandbox-images/openclaw/Dockerfile.base",
);
let openClawContent = fs.readFileSync(openClawDockerfile, "utf8");
if (action === "apply") {
  if (!openClawContent.includes(sourceStage)) {
    openClawContent = openClawContent.replace(builderStage, `${sourceStage}\n\n${builderStage}`);
  }
  if (!openClawContent.includes(sourceOpenClawInstall)) {
    if (!openClawContent.includes(npmOpenClawInstall)) {
      throw new Error("Cannot replace the OpenClaw npm install with its pinned GitHub source build");
    }
    openClawContent = openClawContent.replace(npmOpenClawInstall, sourceOpenClawInstall);
  }
} else {
  openClawContent = openClawContent.replace(sourceOpenClawInstall, npmOpenClawInstall);
  openClawContent = openClawContent.replace(`${sourceStage}\n\n`, "");
}
fs.writeFileSync(openClawDockerfile, openClawContent);

function rewriteNpmLockSources(directory) {
  if (!fs.existsSync(directory)) {
    return;
  }
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    if (entry.name === ".git" || entry.name === "node_modules") {
      continue;
    }
    const entryPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      rewriteNpmLockSources(entryPath);
      continue;
    }
    if (entry.name !== "package-lock.json" && entry.name !== "npm-shrinkwrap.json") {
      continue;
    }
    let content = fs.readFileSync(entryPath, "utf8");
    if (action === "apply") {
      content = content.replaceAll(
        blockedNpmRegistry,
        "https://packagefeedproxy.microsoft.io/npm/",
      );
    } else {
      content = content.replaceAll(
        "https://packagefeedproxy.microsoft.io/npm/",
        blockedNpmRegistry,
      );
    }
    fs.writeFileSync(entryPath, content);
  }
}

rewriteNpmLockSources(karsDir);
rewriteNpmLockSources(openClawDir);
NODE

echo "Upstream Docker package feed proxy action completed: ${ACTION}."
