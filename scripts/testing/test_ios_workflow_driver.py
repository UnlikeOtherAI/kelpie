"""Verify hosted simulator cleanup decisions without starting or changing a simulator."""
import importlib.util
from pathlib import Path
import sys
import tempfile
import subprocess
import types
import unittest
import json
import urllib.error
import urllib.request
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
SPEC = importlib.util.spec_from_file_location(
    "ios_workflow_acceptance", Path(__file__).with_name("ios-workflow-acceptance.py")
)
DRIVER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(DRIVER)


class HostedSimulatorCleanupTests(unittest.TestCase):
    def test_two_stage_rendezvous_requires_explicit_original_result_acknowledgment(self):
        from ios_workflow_rendezvous import HostedCLIRendezvous
        bridge = HostedCLIRendezvous("test-nonce")
        bridge.start()
        url = f"http://127.0.0.1:{bridge.port}/test-nonce"
        def post(body):
            request = urllib.request.Request(url, json.dumps(body).encode(), {"Content-Type": "application/json"})
            with urllib.request.urlopen(request, timeout=2) as response:
                return response.status
        try:
            with self.assertRaises(urllib.error.HTTPError) as early:
                post({"verified": True})
            self.assertEqual(early.exception.code, 409)
            early.exception.close()
            self.assertEqual(post({"tabId": "a74a8e9e-4557-4e01-b5ca-c0e7fb70c0ed"}), 202)
            self.assertFalse(bridge.standard_verified())
            bridge.standard_passed()
            self.assertEqual(post({"verified": True}), 202)
            self.assertTrue(bridge.standard_verified())
            with self.assertRaises(urllib.error.HTTPError) as duplicate:
                post({"verified": True})
            self.assertEqual(duplicate.exception.code, 409)
            duplicate.exception.close()
            bridge.finish(False)
            with urllib.request.urlopen(url, timeout=2) as response:
                self.assertEqual(json.load(response), {"state": "failed"})
        finally:
            bridge.close()

    def test_capture_insets_are_bounded_numeric_only(self):
        from ios_workflow_diagnostics import fixed_capture_insets
        line = "[WorkflowCaptureInsets] before=0,34,0,34,0,0,0,34,0 after=0,0,0,0,0,0,0,0,0"
        self.assertEqual(fixed_capture_insets(line), {
            "before": [0, 34, 0, 34, 0, 0, 0, 34, 0], "after": [0, 0, 0, 0, 0, 0, 0, 0, 0],
        })
        self.assertIsNone(fixed_capture_insets(line.replace("0,34", "private,34")))
        self.assertIsNone(fixed_capture_insets(line.replace("0,34", "999999,34")))

    def test_capture_geometry_diagnostics_are_bounded_numeric_only(self):
        from ios_workflow_diagnostics import fixed_capture_geometry
        line = "[WorkflowCaptureGeometry] before=390,800,390,800,390,800,1,3 after=390,790,390,790,390,790,1,3"
        self.assertEqual(fixed_capture_geometry(line), {
            "before": [390, 800, 390, 800, 390, 800, 1, 3],
            "after": [390, 790, 390, 790, 390, 790, 1, 3],
        })
        self.assertIsNone(fixed_capture_geometry(line.replace("390,800", "private,800")))
        self.assertIsNone(fixed_capture_geometry(line.replace("390,800", "999999,800")))
        self.assertIsNone(fixed_capture_geometry(line.replace("390,800", "390,0")))

    def test_capture_xcresult_diagnostics_only_keep_fixed_enums(self):
        from ios_workflow_diagnostics import fixed_capture_events
        self.assertEqual(fixed_capture_events([
            "prefix [WorkflowCapture] reason=observation-INVALID_ARGUMENTS",
            "[WorkflowCapture] reason=snapshot-visible-size",
            "[WorkflowCapture] reason=focus-viewport",
            "[WorkflowCapture] reason=responder-outside",
            "[WorkflowCapture] reason=focus-private_value",
        ]), {"focus-viewport": 1, "observation-INVALID_ARGUMENTS": 1, "responder-outside": 1,
              "snapshot-visible-size": 1})

    def test_capture_diagnostics_only_keep_fixed_reasons(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "log"
            output = Path(directory) / "diagnostics"
            source.write_text("prefix [WorkflowCapture] reason=visible-size\n"
                              "[WorkflowCapture] reason=observation-BUSY\n"
                              "[WorkflowCapture] reason=private-user-value\n")
            DRIVER.failure_diagnostics(source, output)
            self.assertEqual(output.read_text(), "[WorkflowCapture] reason=visible-size\n"
                             "[WorkflowCapture] reason=observation-BUSY\n")

    def test_cli_timeout_metadata_excludes_output_values(self):
        from ios_workflow_cli import timeout_metadata
        payload = json.dumps({"result": {"success": True, "state": "completed",
                                         "outputs": {"secret": "private"}, "artifacts": [{}, {}]},
                              "downloaded": [{}, {}]}).encode()
        report = timeout_metadata(subprocess.TimeoutExpired("script", 60, output=payload, stderr=b"private"))
        self.assertEqual(report, {"stdoutBytes": len(payload), "stderrBytes": 7, "resultSuccess": True,
                                  "resultState": "completed", "artifactCount": 2, "downloadCount": 2})
        self.assertNotIn("private", json.dumps(report))
        self.assertEqual(timeout_metadata(subprocess.TimeoutExpired("script", 60, output=b"{")),
                         {"stdoutBytes": 1, "stderrBytes": 0})

    def test_cli_rejects_process_local_pair_before_script_execution(self):
        from ios_workflow_cli import run_fixture
        with tempfile.TemporaryDirectory() as directory:
            with patch("ios_workflow_cli.invoke", return_value={"success": True, "scope": "session", "persisted": False}) as invoke:
                with self.assertRaisesRegex(ValueError, "did not persist"):
                    run_fixture("a74a8e9e-4557-4e01-b5ca-c0e7fb70c0ed", Path(directory) / "cli")
                self.assertEqual(invoke.call_count, 1)

    def test_cli_failure_status_keeps_only_bounded_metadata(self):
        from ios_workflow_cli import run_fixture
        responses = [{"success": True, "scope": "persistent", "persisted": True}, subprocess.TimeoutExpired("script", 60),
                     {"state": "running", "playing": True, "actionIndex": 1,
                      "outputs": {"secret": "private"}, "runError": {"code": "SAFE_CODE", "message": "private"}}]
        with tempfile.TemporaryDirectory() as directory:
            with patch("ios_workflow_cli.invoke", side_effect=responses):
                with self.assertRaises(subprocess.TimeoutExpired):
                    run_fixture("a74a8e9e-4557-4e01-b5ca-c0e7fb70c0ed", Path(directory) / "cli")
            report = json.loads((Path(directory) / "cli/status-on-failure.json").read_text())
            self.assertEqual(report, {"status": "observed", "stdoutBytes": 0, "stderrBytes": 0,
                                      "state": "running", "playing": True, "actionIndex": 1, "errorCode": "SAFE_CODE"})
            self.assertNotIn("private", json.dumps(report))

    def test_navigation_diagnostics_emit_only_known_fixed_events(self):
        from ios_workflow_diagnostics import fixed_events
        raw = [
            "[WorkflowNavigationLease] invalid=unexpected-navigation-token",
            "prefix [WorkflowNavigationLease] invalid=unexpected-navigation-token trailing",
            "[WorkflowNavigationLease] wait-refused=awaiting-issue",
            "[WorkflowNavigationLease] invalid=private-user-value",
            "authorization: fixture-credential",
        ]
        self.assertEqual(fixed_events(raw), {
            "invalid=unexpected-navigation-token": 2, "wait-refused=awaiting-issue": 1,
        })

    def test_navigation_selection_has_only_real_native_and_public_navigation_cases(self):
        targets, names = DRIVER.selection("navigation")
        self.assertEqual(len(targets), 3)
        self.assertEqual(names, {
            "testRealWebKitHTTPNavigationUsesIssuedToken",
            "testRealWebKitHTTPNavigationAfterPriorBlankUsesIssuedToken",
            "testRealWebKitDelayedPriorHTTPCallbackRetiresBeforeNewLease",
            "testRealWebKitPriorLoadDeadlineDoesNotIssueAnotherLoad",
            "testRealWebKitPriorLoadCancellationDoesNotIssueAnotherLoad",
            "testRealWebKitForeignCallbackAfterReservationStillRefuses",
            "testInitialOwnedHTTPNavigationLoadsFixture",
            "testColdPriorHTTPEitherNavigatesOrRefusesBeforeLoadThenRecovers",
        })
        _, diagnostic_names = DRIVER.selection("diagnostics")
        self.assertTrue(names < diagnostic_names)
        self.assertIn("testHostedCLIUsesPairedWorkflowAndDownloadsEveryFormat", diagnostic_names)
        _, full_names = DRIVER.selection("full")
        self.assertTrue(diagnostic_names < full_names)
        self.assertTrue(names < full_names)
        self.assertIn("testHostedCLIUsesPairedWorkflowAndDownloadsEveryFormat", full_names)
        with self.assertRaises(ValueError):
            DRIVER.selection("unrecognized")

    def test_already_shutdown_device_is_verified_without_mutation(self):
        with patch.object(DRIVER, "device_state", return_value="Shutdown"), patch.object(DRIVER.subprocess, "run") as run:
            self.assertEqual(DRIVER.shutdown_owned("owned"), "verified shutdown")
            self.assertEqual(DRIVER.terminate_owned("owned", "app", {}), "device already shutdown")
            run.assert_not_called()

    def test_shutdown_race_uses_observed_state_even_if_command_fails(self):
        with patch.object(DRIVER, "device_state", side_effect=["Booted", "Shutdown"]), patch.object(
            DRIVER.subprocess, "run", return_value=types.SimpleNamespace(returncode=149)
        ) as run:
            self.assertEqual(DRIVER.shutdown_owned("owned"), "verified shutdown")
            self.assertEqual(run.call_args.args[0], ["xcrun", "simctl", "shutdown", "owned"])

    def test_inventory_failure_keeps_shutdown_unconfirmed(self):
        for error in (RuntimeError("Selected simulator is missing"), KeyError("devices")):
            with self.subTest(error=type(error).__name__), patch.object(
                DRIVER, "device_state", side_effect=error
            ), patch.object(DRIVER.subprocess, "run") as run:
                self.assertEqual(DRIVER.shutdown_owned("owned"), "unconfirmed: simulator shutdown")
                run.assert_not_called()

    def test_container_query_failure_does_not_mean_the_app_is_absent(self):
        failure = types.SimpleNamespace(returncode=149, stdout="", stderr="Unable to lookup in current state")
        with patch.object(DRIVER, "device_state", return_value="Booted"), patch.object(
            DRIVER.subprocess, "run", return_value=failure
        ):
            with self.assertRaisesRegex(RuntimeError, "Could not query"):
                DRIVER.terminate_owned("owned", "app", {})

    def test_different_installed_binary_cannot_be_terminated(self):
        with tempfile.TemporaryDirectory() as directory:
            (Path(directory) / "Kelpie").write_bytes(b"foreign installed binary")
            found = types.SimpleNamespace(returncode=0, stdout=directory, stderr="")
            with patch.object(DRIVER, "device_state", return_value="Booted"), patch.object(
                DRIVER.subprocess, "run", return_value=found
            ) as run:
                with self.assertRaisesRegex(RuntimeError, "hashes differ"):
                    DRIVER.terminate_owned("owned", "app", {"Kelpie": "0" * 64})
                self.assertEqual(run.call_count, 1)
                self.assertEqual(run.call_args.args[0][2], "get_app_container")


if __name__ == "__main__":
    unittest.main()
