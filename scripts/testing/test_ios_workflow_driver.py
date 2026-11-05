"""Verify hosted simulator cleanup decisions without starting or changing a simulator."""
import importlib.util
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
SPEC = importlib.util.spec_from_file_location(
    "ios_workflow_acceptance", Path(__file__).with_name("ios-workflow-acceptance.py")
)
DRIVER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(DRIVER)


class HostedSimulatorCleanupTests(unittest.TestCase):
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
