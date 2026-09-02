#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
require_forge

model="$(model_name)"
for source_file in contract-v1.yaml contract-v2.yaml cross-namespace.yaml; do
  sed "s/__MODEL__/${model//\//\\/}/g" \
    "${LAB_ROOT}/manifests/${source_file}" \
    >"${GENERATED_DIR}/${source_file}"
done

printf 'Rendered code/03 manifests with model %s in %s\n' "${model}" "${GENERATED_DIR}"
