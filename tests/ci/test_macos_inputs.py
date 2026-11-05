import importlib.util
import json
import os
import subprocess
import tempfile
from pathlib import Path
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("macos_inputs", ROOT / "scripts/ci/macos_inputs.py")
GATE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GATE)


class MacOSInputsTests(unittest.TestCase):
    def test_builds_only_actual_app_native_and_generator_inputs(self):
        for path in [
            "apps/macos/Kelpie/Renderer/CEFBridge.mm",
            "apps/macos/Kelpie/Info.plist",
            "apps/macos/KelpieHelper/main.mm",
            "apps/macos/Tests/ScriptCaptureTests.swift",
            "apps/macos/Project.swift",
            "native/CMakeLists.txt",
            "native/core-ai/CMakeLists.txt",
            "native/core-mcp/browser_contract.cmake",
            "native/core-automation/include/kelpie/script_redaction.h",
            "packages/shared/src/script-workflow.ts",
            "packages/shared/tsconfig.build.json",
            "packages/shared/scripts/build.mjs",
            "scripts/native/generate-browser-contract.mjs",
            "scripts/download-cef.sh", "pnpm-lock.yaml", "tsconfig.base.json",
            ".github/actions/browser-contract/action.yml", ".github/workflows/macos.yml",
        ]:
            with self.subTest(path=path):
                self.assertTrue(GATE.requires_native(path))

    def test_skips_docs_admin_other_apps_and_unused_desktop_engine(self):
        for path in [
            "docs/api/core.md", "docs/functionality.md", "AGENTS.md", "CLAUDE.md",
            "apps/macos/NATIVE_INTEGRATION.md", "apps/macos/Kelpie/README.md",
            "native/core-ai/README.md", "apps/macos/project.yml",
            "apps/android/app/build.gradle.kts", "apps/ios/Kelpie/App.swift",
            "apps/windows/CMakeLists.txt", "apps/linux/src/linux_app.cpp",
            "native/engine-chromium-desktop/src/desktop_engine.cpp",
            "packages/cli/src/commands/browser.ts", ".github/workflows/ios.yml",
            "packages/shared/tests/browser-control.test.ts", "packages/shared/tsconfig.json",
            "scripts/package-linux-rpm.sh",
        ]:
            with self.subTest(path=path):
                self.assertFalse(GATE.requires_native(path))

    def test_pull_request_uses_merge_base_and_rename_endpoints(self):
        event = {"pull_request": {"base": {"sha": "base"}, "head": {"sha": "head"}}}
        with patch.object(GATE.subprocess, "check_output", return_value=b"docs/api/core.md\0apps/macos/Kelpie/new.swift\0") as git:
            self.assertEqual(GATE.decision("pull_request", event), (True, "native-input-change"))
            git.assert_called_once_with(["git", "diff", "--name-only", "--no-renames", "-z", "base...head"])

    def test_unrelated_push_skips_and_initial_push_lists_tree(self):
        with patch.object(GATE.subprocess, "check_output", return_value=b"docs/brief.md\0") as git:
            self.assertEqual(GATE.decision("push", {"before": "old", "after": "new"}), (False, "unrelated-change"))
            git.assert_called_once_with(["git", "diff", "--name-only", "--no-renames", "-z", "old", "new"])
        with patch.object(GATE.subprocess, "check_output", return_value=b"native/core-ai/CMakeLists.txt\0") as git:
            self.assertTrue(GATE.decision("push", {"before": "0" * 40, "after": "new"})[0])
            git.assert_called_once_with(["git", "ls-tree", "-r", "--name-only", "-z", "new"])

    def test_real_git_documentation_push_skips_and_native_push_builds(self):
        cache = ROOT / ".cache" / "macos-scope-tests"
        cache.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=cache) as directory:
            fixture = Path(directory)

            def git(*args):
                return subprocess.check_output(["git", *args], cwd=fixture, stderr=subprocess.DEVNULL).decode().strip()

            git("init", "-q")
            git("config", "user.name", "Scope fixture")
            git("config", "user.email", "scope@example.invalid")
            readme = fixture / "README.md"
            readme.write_text("Initial documentation")
            git("add", ".")
            git("commit", "-qm", "Initial fixture")
            initial = git("rev-parse", "HEAD")
            readme.write_text("Documentation update")
            git("add", ".")
            git("commit", "-qm", "Documentation fixture")
            docs = git("rev-parse", "HEAD")
            source = fixture / "apps/macos/Kelpie/Fixture.swift"
            source.parent.mkdir(parents=True)
            source.write_text("// Native input")
            git("add", ".")
            git("commit", "-qm", "Native fixture")
            native = git("rev-parse", "HEAD")
            for before, after, expected in [(initial, docs, "native=false"), (docs, native, "native=true")]:
                event = fixture / "event.json"
                event.write_text(json.dumps({"before": before, "after": after}))
                output = subprocess.check_output(
                    ["python3", str(ROOT / "scripts/ci/macos_inputs.py")],
                    cwd=fixture,
                    env={**os.environ, "GITHUB_EVENT_NAME": "push", "GITHUB_EVENT_PATH": str(event)},
                    text=True,
                )
                self.assertIn(expected, output.splitlines())

    def test_manual_dispatch_is_explicit_and_git_failure_does_not_silently_skip(self):
        with patch.object(GATE.subprocess, "check_output", side_effect=RuntimeError("unavailable")):
            self.assertEqual(GATE.decision("workflow_dispatch", {}), (True, "explicit-manual-dispatch"))
            with self.assertRaises(RuntimeError):
                GATE.decision("push", {"before": "old", "after": "new"})


if __name__ == "__main__":
    unittest.main()
