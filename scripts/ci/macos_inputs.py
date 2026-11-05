#!/usr/bin/env python3
"""Select only inputs read by the macOS app/native/contract build."""
import json
import os
from pathlib import Path
import subprocess

EXACT_INPUTS = {
    ".github/workflows/macos.yml",
    "scripts/ci/macos_inputs.py",
    "tests/ci/test_macos_inputs.py",
    "scripts/download-cef.sh",
    "scripts/native/generate-browser-contract.mjs",
    "scripts/native/generate-script-presentation.mjs",
    ".mise.toml", ".swiftlint.yml", ".npmrc", "Makefile",
    "package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml", "tsconfig.base.json",
    "native/CMakeLists.txt",
    "apps/macos/Project.swift",
    "packages/shared/package.json", "packages/shared/tsconfig.build.json",
}
PREFIX_INPUTS = (
    "apps/macos/Kelpie/", "apps/macos/KelpieHelper/", "apps/macos/Tests/",
    "apps/macos/Tuist/", ".github/actions/browser-contract/",
    "native/core-protocol/", "native/core-connect/", "native/core-state/",
    "native/core-automation/", "native/core-mcp/", "native/core-ai/",
    "packages/shared/src/", "packages/shared/scripts/",
)


def requires_native(path):
    # Documentation is not compiled, including README files inside source directories.
    if path.lower().endswith((".md", ".mdx", ".rst")):
        return False
    return path in EXACT_INPUTS or path.startswith(PREFIX_INPUTS)


def changed_paths(event_name, event):
    if event_name == "pull_request":
        base = event["pull_request"]["base"]["sha"]
        head = event["pull_request"]["head"]["sha"]
        command = ["diff", "--name-only", "--no-renames", "-z", base + "..." + head]
    elif event_name == "push":
        base, head = event["before"], event["after"]
        command = (["ls-tree", "-r", "--name-only", "-z", head]
                   if base == "0" * 40 else
                   ["diff", "--name-only", "--no-renames", "-z", base, head])
    else:
        raise ValueError("Unsupported workflow event")
    data = subprocess.check_output(["git", *command])
    return [os.fsdecode(path) for path in data.split(b"\0") if path]


def decision(event_name, event):
    if event_name == "workflow_dispatch":
        return True, "explicit-manual-dispatch"
    selected = any(requires_native(path) for path in changed_paths(event_name, event))
    return selected, "native-input-change" if selected else "unrelated-change"


def main():
    event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
    selected, reason = decision(os.environ["GITHUB_EVENT_NAME"], event)
    print("native=" + str(selected).lower())
    print("reason=" + reason)


if __name__ == "__main__":
    main()
