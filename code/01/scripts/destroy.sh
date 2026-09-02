#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

kubectl delete -f "${ROOT_DIR}/.generated/forge.yaml" --ignore-not-found
kubectl delete -f "${ROOT_DIR}/.generated/policies.yaml" --ignore-not-found
kubectl delete -f "${ROOT_DIR}/k8s/workspace-mcp.yaml" --ignore-not-found
