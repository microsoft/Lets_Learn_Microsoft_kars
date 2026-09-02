#!/usr/bin/env python3
import sys

import yaml


TARGET_DEPLOYMENTS = {"kars-controller", "registry", "relay"}
SANDBOX_TOLERATION = {
    "key": "kars.azure.com/sandbox",
    "operator": "Equal",
    "value": "true",
    "effect": "NoSchedule",
}


documents = list(yaml.safe_load_all(sys.stdin))
for document in documents:
    if not isinstance(document, dict) or document.get("kind") != "Deployment":
        continue
    if document.get("metadata", {}).get("name") not in TARGET_DEPLOYMENTS:
        continue

    pod_spec = document["spec"]["template"]["spec"]
    pod_spec.setdefault("nodeSelector", {})["kars.azure.com/pool"] = "sandbox"
    tolerations = pod_spec.setdefault("tolerations", [])
    if SANDBOX_TOLERATION not in tolerations:
        tolerations.append(SANDBOX_TOLERATION)

yaml.safe_dump_all(
    documents,
    sys.stdout,
    explicit_start=True,
    sort_keys=False,
)
