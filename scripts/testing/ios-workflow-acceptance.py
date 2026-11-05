#!/usr/bin/env python3
"""Run Kelpie's real workflow acceptance corpus on existing simulators on a dedicated GitHub runner."""
import hashlib
import json
import os
import plistlib
import re
import subprocess
import sys
import time
import uuid
from pathlib import Path
from ios_workflow_cli import run_fixture
from ios_workflow_rendezvous import HostedCLIRendezvous
from ios_workflow_diagnostics import export_lease_diagnostics, fixed_capture_events

PRODUCTS = Path("apps/ios/.build/Build/Products").resolve()
EVIDENCE = Path(os.environ.get("RUNNER_TEMP", ".")) / "kelpie-ios-evidence"
BUNDLE = "com.unlikeotherai.kelpie"
NAVIGATION_UI_TEST = "testInitialOwnedHTTPNavigationLoadsFixture"
COLD_NAVIGATION_TEST = "testColdPriorHTTPEitherNavigatesOrRefusesBeforeLoadThenRecovers"
NAVIGATION_TESTS = Path("apps/ios/Tests/IOSWorkflowNavigationTests.swift")


def selection(scope):
    if scope == "keyboard":
        name = "testKeyboardGeometryForOwnedPacedCapture"
        return ["KelpieUITests/WorkflowCaptureUITests/" + name], {name}
    if scope == "postedit":
        name = "testPostEvaluationCallbackKeepsKeyboardClosed"
        return ["KelpieTests/IOSPostEvaluationProbeTests", "KelpieUITests/WorkflowCaptureUITests/" + name], {
            name, "testPreAuthorizationTimeoutAndExactViewTermination"
        }
    if scope == "geometry":
        methods = [
            "testLiveMarkerProjectionMatchesSameSceneTarget",
            "testPairedMCPClickShowsNativeMarkerAndDownloadsDecodedMedia",
            "testNativePinchClipsTapCenterAndExportedMarker",
            "testNativePinchScrollableControl",
        ]
        return ["KelpieUITests/WorkflowCaptureUITests/" + method for method in methods], set(methods)
    if scope not in ("full", "navigation", "diagnostics"):
        raise ValueError("Unsupported native workflow test scope")
    targets = ["KelpieTests/IOSWorkflowNavigationTests"]
    files = [NAVIGATION_TESTS]
    if scope == "full":
        targets.extend(["KelpieTests/IOSWorkflowAdmissionTests", "KelpieTests/IOSWorkflowReceiptTests",
                        "KelpieTests/IOSCaptureViewportTests", "KelpieTests/IOSG08GeometryTests",
                        "KelpieUITests/WorkflowCaptureUITests"])
        files.extend([Path("apps/ios/Tests/IOSWorkflowAdmissionTests.swift"), Path("apps/ios/Tests/IOSWorkflowReceiptTests.swift"), Path("apps/ios/Tests/IOSCaptureViewportTests.swift"),
                      Path("apps/ios/Tests/IOSG08GeometryTests.swift"), *Path("apps/ios/UITests").glob("Workflow*.swift")])
    else:
        methods = [NAVIGATION_UI_TEST, COLD_NAVIGATION_TEST]
        if scope == "diagnostics":
            targets.append("KelpieTests/IOSCaptureViewportTests")
            targets.append("KelpieTests/IOSG08GeometryTests")
            targets.append("KelpieTests/IOSWorkflowReceiptTests/testCanonicalMutationReceiptMatrix")
            targets.append("KelpieTests/IOSWorkflowReceiptTests/testMalformedCallbackLatchesBeforeDocumentOrAuthorityGuard")
            targets.extend("KelpieTests/IOSWorkflowAdmissionTests/" + name for name in [
                "testCaptureCleanupPreservesRegisteredAliasAndDiscardsUnpublishedFiles",
                "testWorkflowReadInspectsRealSelectedTabWhilePublicGateRemainsClosed",
                "testFirstCaptureWaitsForStableCompleteViewport",
                "testFirstCaptureStabilityHonorsTimeoutStopAndDocumentReplacement",
                "testPointerDefaultAndExplicitDurationUseSharedContract",
                "testDeviceCapabilitiesAdvertiseOnlySupportedMobileActions",
                "testPacedAcknowledgementRequiresCompleteResultAndMatchingToken",
                "testPacedUnknownPostMutationSensitivityStops",
                "testPacedEditsArePlannedBeforeAnyEarlierAction",
                "testPacedExecutorClearsOnceAndWaitsOnlyBetweenUnicodeScalars",
                "testPacedExecutorStopsWithoutReplayAndPreservesUncertainty",
            ])
            methods.extend([
                "testHostedCLIUsesPairedWorkflowAndDownloadsEveryFormat",
                "testCaptureLimitsRecoverAndBothPointerCurvesReachTheirTarget",
                "testDefaultPointerMotionUsesShorterNativeTiming",
                "testLivePointerMarkerAndStopAppearDuringCapture",
                "testNativePinchClipsTapCenterAndExportedMarker",
                "testNativePinchScrollableControl",
                "testMarkerDetectorRecognizesFadedGreenWithoutAcceptingGray",
                "testLabelFillTypeAndReflectedPasswordRedaction",
                "testFocusAutocompleteRefusalThroughMCPRedactsEarlierOutputsAndDiscardsFrames",
                "testPairedMCPClickShowsNativeMarkerAndDownloadsDecodedMedia",
                "testLiveMarkerProjectionMatchesSameSceneTarget",
                "testPrivateObservationTypedExtractionAndSensitiveTargetRecovery",
                "testPostInputAutocompleteCaptureStopsLaterActionsAndDiscardsMedia",
                "testPacedFillUsesUnicodeScalarsAndRetainsMedia",
                "testPacedCaptureKeepsNativeKeyboardClosedDuringEdit",
                            "testPacedFocusLossStopsWithoutRetargeting",
                "testPacedLateSensitivityDiscardsCaptureAndRedactsFullLiteral",
                "testPacedUnknownTargetRedactsFullLiteralButOrdinaryInputDoesNot",
                "testPacedAcknowledgedFinalNavigationCompletesAndRedacts",
                "testPacedAcknowledgedFinalNavigationDiscardsCapture",
                "testPacedLostFinalCallbackProtectsLiteralWithoutCapture",
                "testPacedLostFinalCallbackDiscardsCapture",
                "testPacedEmptyTypeDoesNotInputAndEmptyFillClears",
                "testPacedEmptyTypeRejectsButtonAndReadonlyTargets",
            ])
        targets.extend("KelpieUITests/WorkflowCaptureUITests/" + method for method in methods)
    required = {method for file in files for method in re.findall(r"func (test\w+)\(", file.read_text())}
    if scope != "full":
        required.update(methods)
        if scope == "diagnostics":
            required.update([
                "testConstantG08GeometryBindsEverySampleToBothDocuments",
                "testFirstCaptureRequiresInsetPropagationIncludingZoom",
                "testProjectionUsesInsetContentOriginAndVisualViewport",
                "testUnsettledInsetAdmissionHonorsDeadlineAndStop",
                "testCanonicalMutationReceiptMatrix",
                "testMalformedCallbackLatchesBeforeDocumentOrAuthorityGuard",
                "testCaptureCleanupPreservesRegisteredAliasAndDiscardsUnpublishedFiles",
                "testWorkflowReadInspectsRealSelectedTabWhilePublicGateRemainsClosed",
                "testFirstCaptureWaitsForStableCompleteViewport",
                "testFirstCaptureStabilityHonorsTimeoutStopAndDocumentReplacement",
                "testPointerDefaultAndExplicitDurationUseSharedContract",
                "testDeviceCapabilitiesAdvertiseOnlySupportedMobileActions",
                "testPacedAcknowledgementRequiresCompleteResultAndMatchingToken",
                "testPacedUnknownPostMutationSensitivityStops",
                "testPacedEditsArePlannedBeforeAnyEarlierAction",
                "testPacedExecutorClearsOnceAndWaitsOnlyBetweenUnicodeScalars",
                "testPacedExecutorStopsWithoutReplayAndPreservesUncertainty",
            ])
    return targets, required


def command(*args, timeout=60):
    return subprocess.check_output(list(map(str, args)), text=True, timeout=timeout).strip()


def digest(path):
    hasher = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def version(value):
    return tuple(int(n) for n in re.findall(r"\d+", value))


def select_devices(devices, sdk):
    for runtime in sorted(devices, key=lambda key: version(key.rsplit("iOS-", 1)[-1]) if ".iOS-" in key else (), reverse=True):
        if ".iOS-" not in runtime:
            continue
        number = version(runtime.rsplit("iOS-", 1)[-1])
        if not (17,) <= number <= version(sdk):
            continue
        available = [d for d in devices[runtime] if d.get("isAvailable")]
        chosen = []
        for family, preferred in [("iPhone", "iPhone 17"), ("iPad", "iPad Air 13-inch (M4)")]:
            matches = [d for d in available if d["name"].startswith(family)]
            if matches:
                device = min(matches, key=lambda d: (d["state"] != "Booted", d["name"] != preferred, d["name"]))
                chosen.append({"family": family, "runtime": runtime, **{k: device[k] for k in ["udid", "name", "state"]}})
        if len(chosen) == 2:
            return chosen
    raise RuntimeError("No existing compatible iPhone and iPad pair on one installed iOS runtime")


def runner_config(nonce, port):
    original, = PRODUCTS.glob("Kelpie_*.xctestrun")
    data = plistlib.loads(original.read_bytes())
    targets = [t for c in data.get("TestConfigurations", []) for t in c["TestTargets"]]
    if not targets:
        targets = [data.get("KelpieUITests", {})]
    ui, = [t for t in targets if str(t.get("TestHostBundleIdentifier", "")).endswith(".uitests.xctrunner")]
    ui.setdefault("EnvironmentVariables", {}).update({"KELPIE_WORKFLOW_CLI_PROBE": nonce, "KELPIE_WORKFLOW_CLI_PORT": str(port)})
    config = PRODUCTS / ("Hosted-" + nonce + ".xctestrun")
    config.write_bytes(plistlib.dumps(data))
    return config, ui["TestHostBundleIdentifier"]


def device_state(udid):
    devices = json.loads(command("xcrun", "simctl", "list", "devices", "-j", timeout=30))["devices"]
    states = [d["state"] for items in devices.values() for d in items if d["udid"] == udid]
    if len(states) != 1:
        raise RuntimeError("Selected simulator is missing from the inventory")
    return states[0]


def terminate_owned(udid, bundle, pins):
    if device_state(udid) == "Shutdown":
        return "device already shutdown"
    installed = subprocess.run(["xcrun", "simctl", "get_app_container", udid, bundle, "app"],
                               capture_output=True, text=True, timeout=20)
    if installed.returncode:
        if "No such file or directory" in installed.stderr:
            return "absent"
        raise RuntimeError("Could not query the pinned bundle container")
    root = Path(installed.stdout.strip())
    if not pins or not all((root / name).is_file() and digest(root / name) == value for name, value in pins.items()):
        raise RuntimeError("Refusing to terminate a bundle whose build hashes differ")
    result = subprocess.run(["xcrun", "simctl", "terminate", udid, bundle], capture_output=True, text=True, timeout=20)
    if result.returncode == 0:
        return "terminated"
    if "nothing to terminate" in result.stderr.lower() or "not running" in result.stderr.lower():
        return "already stopped"
    raise RuntimeError("Could not confirm termination of the pinned bundle")


def shutdown_owned(udid):
    # Only a simulator booted by this invocation may be shut down. Confirm actual state, not command admission.
    try:
        if device_state(udid) == "Shutdown":
            return "verified shutdown"
        subprocess.run(["xcrun", "simctl", "shutdown", udid], capture_output=True, check=False, timeout=100)
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            if device_state(udid) == "Shutdown":
                return "verified shutdown"
            time.sleep(2)
    except (ValueError, OSError, KeyError, RuntimeError, subprocess.SubprocessError):
        pass
    return "unconfirmed: simulator shutdown"


def failure_diagnostics(log_path, destination):
    if not log_path.exists():
        return
    lines = []
    with log_path.open(errors="replace") as log:
        for line in log:
            capture = fixed_capture_events((line,))
            if capture:
                lines.append("[WorkflowCapture] reason=" + next(iter(capture)))
                if len(lines) >= 100:
                    break
                continue
            if not re.search(r"\berror:|Test Case .*failed|Test Suite .*failed|\*\* TEST .*FAILED|timed out", line, re.I):
                continue
            line = re.sub(r"(?i)(bearer\s+)\S+", r"\1[redacted]", line)
            line = re.sub(r"(?i)([\"']?(?:access_token|token|password|authorization)[\"']?\s*[:=]\s*)[^\s,}]+",
                          r"\1[redacted]", line)
            lines.append(line.strip()[:600])
            if len(lines) >= 100:
                break
    destination.write_text("\n".join(lines) + "\n")


def run_device(device, product_hashes, scope):
    udid = device["udid"]
    folder = EVIDENCE / device["family"]
    folder.mkdir()
    nonce = str(uuid.uuid4())
    handoff = HostedCLIRendezvous(nonce)
    config, runner = runner_config(nonce, handoff.port)
    result = folder / "workflow.xcresult"
    started_here = device["state"] != "Booted"
    process = None
    log_path = folder.parent.parent / (device["family"] + "-workflow-xcode.log")
    runner_product = PRODUCTS / "Debug-iphonesimulator/KelpieUITests-Runner.app"
    test_binary = "PlugIns/KelpieUITests.xctest/KelpieUITests"
    runner_pins = {test_binary: digest(runner_product / test_binary)}
    handoff.start()
    try:
        if started_here:
            command("xcrun", "simctl", "boot", udid, timeout=120)
        command("xcrun", "simctl", "bootstatus", udid, "-b", timeout=300)
        command("xcrun", "simctl", "install", udid, PRODUCTS / "Debug-iphonesimulator/Kelpie.app", timeout=120)
        installed = Path(command("xcrun", "simctl", "get_app_container", udid, BUNDLE, "app"))
        installed_hashes = {key: digest(installed / key) for key in product_hashes}
        install_report = {"device": device, "beforeHashes": installed_hashes}
        (folder / "installed.json").write_text(json.dumps(install_report, indent=2))
        if installed_hashes != product_hashes:
            raise RuntimeError("Installed simulator app differs from the generic build")
        args = ["xcodebuild", "test-without-building", "-xctestrun", str(config), "-destination", "id=" + udid,
                "-parallel-testing-enabled", "NO", "-maximum-concurrent-test-simulator-destinations", "1",
                "-test-timeouts-enabled", "YES", "-default-test-execution-time-allowance", "750",
                "-maximum-test-execution-time-allowance", "780", "-resultBundlePath", str(result)]
        targets, required = selection(scope)
        args.extend("-only-testing:" + target for target in targets)
        cli_error = None
        cli_started = False
        # Xcode's human-readable diagnostics stay on the ephemeral machine. Only the xcresult and curated outputs are uploaded.
        with log_path.open("w") as log:
            process = subprocess.Popen(args, stdout=log, stderr=subprocess.STDOUT)
            deadline = time.monotonic() + {"navigation": 10, "geometry": 20, "postedit": 10, "keyboard": 10}.get(scope, 40) * 60
            while process.poll() is None and time.monotonic() < deadline:
                tab = handoff.current_tab()
                if tab and not cli_started:
                    cli_started = True
                    try:
                        run_fixture(tab, folder / "cli")
                        handoff.standard_passed()
                        acknowledgment_deadline = time.monotonic() + 60
                        while not handoff.standard_verified() and time.monotonic() < acknowledgment_deadline:
                            if process.poll() is not None:
                                raise RuntimeError("XCTest exited before original CLI verification")
                            time.sleep(0.2)
                        if not handoff.standard_verified():
                            raise RuntimeError("Original CLI verification was not acknowledged")
                        stage = folder / "g08-stage.json"
                        stage.write_text(json.dumps({"state": "running"}))
                        completed = subprocess.run(
                            ["node", "scripts/testing/ios-g08.mjs", tab, str(folder / "g08"),
                             device["family"], product_hashes["Kelpie"], command("git", "rev-parse", "HEAD")],
                            capture_output=True, text=True, timeout=600)
                        stage.write_text(json.dumps({"state": "passed" if completed.returncode == 0 else "failed",
                                                     "exitCode": completed.returncode}, indent=2))
                        if completed.returncode:
                            raise RuntimeError("G08 fixture or decoder failed; see retained evidence")
                    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as error:
                        cli_error = type(error).__name__ + ": " + str(error)[:160]
                        (folder / "cli-stage-failure.txt").write_text(cli_error + "\n")
                        stage = folder / "g08-stage.json"
                        if stage.exists() and json.loads(stage.read_text()).get("state") == "running":
                            stage.write_text(json.dumps({"state": "failed", "error": type(error).__name__}, indent=2))
                    finally:
                        handoff.finish(cli_error is None)
                time.sleep(1)
            if process.poll() is None:
                raise RuntimeError("XCTest exceeded the per-device runtime budget")
        summary = command("xcrun", "xcresulttool", "get", "test-results", "summary", "--path", result)
        (folder / "summary.json").write_text(summary)
        tests = command("xcrun", "xcresulttool", "get", "test-results", "tests", "--path", result)
        (folder / "tests.json").write_text(tests)
        install_verified = False
        try:
            state = device_state(udid)
            install_report["afterState"] = state
            if state != "Shutdown":
                installed = Path(command("xcrun", "simctl", "get_app_container", udid, BUNDLE, "app"))
            # The known container can be hashed on disk even after XCTest shuts the simulator down.
            after_hashes = {key: digest(installed / key) for key in product_hashes}
            install_report["afterHashes"] = after_hashes
            install_verified = after_hashes == product_hashes
        except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as error:
            install_report["afterError"] = type(error).__name__
        (folder / "installed.json").write_text(json.dumps(install_report, indent=2))
        missing = sorted(method for method in required if method not in tests)
        cli_required = scope not in ("navigation", "geometry", "postedit", "keyboard")
        if process.returncode or (cli_required and not cli_started) or cli_error or missing or json.loads(summary).get("failedTests", 0):
            raise RuntimeError(f"XCTest exit {process.returncode}, CLI started {cli_started}, CLI error {cli_error}, missing tests {missing}")
        if not install_verified:
            raise RuntimeError("Post-test installed app hash could not be verified; see installation report")
        return True
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as error:
        (folder / "primary-failure.txt").write_text(type(error).__name__ + ": " + str(error)[:500] + "\n")
        raise
    finally:
        handoff.close()
        if process and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=20)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=10)
        cleanup = {}
        for bundle, pins in [(runner, runner_pins), (BUNDLE, product_hashes)]:
            try:
                cleanup[bundle] = terminate_owned(udid, bundle, pins)
            except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as error:
                cleanup[bundle] = "unconfirmed: " + str(error)[:150]
        if started_here:
            cleanup["simulator"] = shutdown_owned(udid)
        else:
            try:
                state = device_state(udid)
                cleanup["simulator"] = "preserved initial boot state" if state == "Booted" else "changed by XCTest: " + state
            except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError):
                cleanup["simulator"] = "unconfirmed: initial boot state"
        individually_retired = all(not cleanup[b].startswith("unconfirmed") for b in (runner, BUNDLE))
        cleanup["nextDeviceAllowed"] = cleanup["simulator"] == "verified shutdown" or (
            not started_here and individually_retired and cleanup["simulator"] == "preserved initial boot state"
        )
        (folder / "cleanup.json").write_text(json.dumps(cleanup, indent=2))
        failure_diagnostics(log_path, folder / "diagnostics.txt")
        if result.is_dir():
            export_lease_diagnostics(result, folder)
            try:
                subprocess.run(["xcrun", "xcresulttool", "export", "attachments", "--path", str(result),
                                "--output-path", str(folder / "attachments")], check=False, timeout=120)
            except (OSError, subprocess.SubprocessError) as error:
                (folder / "attachment-export-error.txt").write_text(type(error).__name__)
        if not cleanup["nextDeviceAllowed"] and sys.exc_info()[0] is None:
            raise RuntimeError("Device app cleanup could not be confirmed; see cleanup report")


def main():
    if os.environ.get("GITHUB_ACTIONS") != "true" or os.environ.get("KELPIE_RUNNER_ENVIRONMENT") != "github-hosted":
        raise RuntimeError("This driver only runs on a disposable GitHub-hosted runner")
    scope = os.environ.get("KELPIE_IOS_TEST_SCOPE", "full")
    selection(scope)
    EVIDENCE.mkdir(exist_ok=False)
    sdk = command("xcrun", "--sdk", "iphonesimulator", "--show-sdk-version")
    inventory = json.loads(command("xcrun", "simctl", "list", "devices", "available", "-j"))["devices"]
    devices = select_devices(inventory, sdk)
    app = PRODUCTS / "Debug-iphonesimulator/Kelpie.app"
    hashes = {key: digest(app / key) for key in ("Kelpie", "Kelpie.debug.dylib") if (app / key).exists()}
    if "Kelpie" not in hashes:
        raise RuntimeError("The simulator executable is missing")
    revision = command("git", "rev-parse", "HEAD")
    if revision != os.environ["GITHUB_SHA"]:
        raise RuntimeError("Checkout and dispatched revision differ")
    report = {"revision": revision, "sourceTree": command("git", "rev-parse", "HEAD^{tree}"),
              "appReveal": command("git", "-C", "vendor/AppReveal", "rev-parse", "HEAD"),
              "xcode": command("xcodebuild", "-version"), "sdk": sdk, "devices": devices, "hashes": hashes,
              "imageVersion": os.environ.get("ImageVersion"), "scope": scope, "outcomes": {}}
    path = EVIDENCE / "report.json"
    path.write_text(json.dumps(report, indent=2))
    for device in sorted(devices, key=lambda item: item["state"] != "Booted"):
        try:
            passed = run_device(device, hashes, scope)
            report["outcomes"][device["family"]] = {"passed": passed}
        except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError) as error:
            report["outcomes"][device["family"]] = {"passed": False, "error": str(error)[:512]}
        path.write_text(json.dumps(report, indent=2))
        print(device["family"], json.dumps(report["outcomes"][device["family"]]), flush=True)
        cleanup_file = EVIDENCE / device["family"] / "cleanup.json"
        cleanup = json.loads(cleanup_file.read_text()) if cleanup_file.is_file() else {}
        if not cleanup.get("nextDeviceAllowed", False):
            for other in devices:
                report["outcomes"].setdefault(other["family"], {"passed": False, "error": "Prior device cleanup unconfirmed"})
            path.write_text(json.dumps(report, indent=2))
            break
    return int(not all(value["passed"] for value in report["outcomes"].values()))


if __name__ == "__main__":
    sys.exit(main())
