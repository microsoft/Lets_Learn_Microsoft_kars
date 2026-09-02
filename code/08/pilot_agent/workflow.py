WORKFLOW = [
    "OPENCLAW_INTAKE",
    "PIN_REQUIREMENT_AND_REVISION",
    "MAF_BUILDER_INSPECT",
    "PROPOSE_MINIMAL_PATCH",
    "RUN_TARGETED_TESTS",
    "CREATE_DIGEST_PINNED_HANDOFF",
    "VERIFY_ARTIFACT_MANIFEST",
    "INDEPENDENT_REVIEW",
    "STOP_FOR_HUMAN_PR_APPROVAL",
]

APPROVED_TOOLS = [
    "inspect_release_contract",
]

FORBIDDEN_ACTIONS = [
    "shell",
    "source_merge",
    "production_deploy",
    "builder_self_approve",
    "reviewer_modify_source",
    "self_modify_authority",
    "symlink_escape",
    "host_trust_handoff",
    "dns_egress",
]
