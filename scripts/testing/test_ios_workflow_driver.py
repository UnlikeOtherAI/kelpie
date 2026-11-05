"""Verify hosted simulator cleanup decisions without starting or changing a simulator."""
import importlib.util
from pathlib import Path
import sys
import tempfile
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
            self.assertEqual(post({"tabId": "a74a8e9e-4557-4e01-b5ca-c0e7fb70c0ed"}), 202)
            self.assertFalse(bridge.standard_verified())
            bridge.standard_passed()
            self.assertEqual(post({"verified": True}), 202)
            self.assertTrue(bridge.standard_verified())
            with self.assertRaises(urllib.error.HTTPError) as duplicate:
                post({"verified": True})
            self.assertEqual(duplicate.exception.code, 409)
            bridge.finish(False)
            with urllib.request.urlopen(url, timeout=2) as response:
                self.assertEqual(json.load(response), {"state": "failed"})
        finally:
            bridge.close()

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
        _, full_names = DRIVER.selection("full")
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
