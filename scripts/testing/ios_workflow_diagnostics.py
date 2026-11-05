"""Export only fixed native navigation lease states from XCTest diagnostic logs."""
import collections
import json
import math
from pathlib import Path
import re
import subprocess

STATES = frozenset({
    "awaiting-start", "destination-reserved", "awaiting-issue",
    "start-before-issue", "already-invalid", "second-start", "previous-version-changed",
    "missing-issued-token", "missing-callback-token", "unexpected-navigation-token", "duplicate-issue",
})
CAPTURE_REASONS = frozenset({
    "native-bounds", "pixel-ratio", "layout-size", "visible-size", "scale", "presentation-parent",
    *(f"snapshot-{value}" for value in ("native-bounds", "pixel-ratio", "layout-size", "visible-size", "scale")),
    *(f"observation-{value}" for value in (
        "BUSY", "TAB_CHANGED", "WEBVIEW_ERROR", "UNAUTHORIZED", "RECORDING_IN_PROGRESS",
        "TIMEOUT", "INVALID_PARAM", "INVALID_VALUE", "UNSUPPORTED", "INVALID_ARGUMENTS",
        "COMMAND_FAILED", "ACCESS_DENIED", "TAB_REQUIRED", "STALE_REFERENCE", "CANCELLED",
        "READINESS_FAILED", "EXTRACT_FAILED", "BROWSER_FAILED", "BROWSER_BUSY", "PAGE_CHANGED", "OTHER",
    )),
})
GEOMETRY_EVENT = re.compile(r"\[WorkflowCaptureGeometry\] before=([0-9.,]+) after=([0-9.,]+)(?:\s|$)")
CAPTURE_EVENT = re.compile(r"\[WorkflowCapture\] reason=([A-Za-z_-]+)(?:\s|$)")
EVENT = re.compile(r"\[WorkflowNavigationLease\] (invalid|wait-refused|timeout)=([a-z-]+)(?:\s|$)")


def fixed_events(lines):
    events = collections.Counter()
    for line in lines:
        found = EVENT.search(line)
        if found and found[2] in STATES:
            events[found[1] + "=" + found[2]] += 1
    return dict(sorted(events.items()))


def fixed_capture_events(lines):
    events = collections.Counter()
    for line in lines:
        found = CAPTURE_EVENT.search(line)
        if found and found[1] in CAPTURE_REASONS:
            events[found[1]] += 1
    return dict(sorted(events.items()))


def fixed_capture_geometry(line):
    found = GEOMETRY_EVENT.search(line)
    if not found:
        return None
    try:
        before, after = ([float(number) for number in value.split(",")] for value in found.groups())
    except ValueError:
        return None
    if len(before) != 8 or len(after) != 8 or not all(
        math.isfinite(number) and 0 < number <= 100000 for number in before + after
    ):
        return None
    return {"before": before, "after": after}


def export_lease_diagnostics(result, destination):
    raw = destination.parent.parent / ("private-navigation-diagnostics-" + destination.name)
    try:
        subprocess.run(
            ["xcrun", "xcresulttool", "export", "diagnostics", "--path", str(result), "--output-path", str(raw)],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120,
        )
        events = collections.Counter()
        capture = collections.Counter()
        geometry = []
        for file in raw.rglob("StandardOutputAndStandardError*.txt"):
            with file.open(errors="replace") as stream:
                for line in stream:
                    events.update(fixed_events((line,)))
                    capture.update(fixed_capture_events((line,)))
                    observed = fixed_capture_geometry(line)
                    if observed and len(geometry) < 100:
                        geometry.append(observed)
        report = {"events": dict(sorted(events.items()))}
        capture_report = {"events": dict(sorted(capture.items())), "geometry": geometry}
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        report = {"unavailable": type(error).__name__}
        capture_report = report
    (destination / "navigation-lease.json").write_text(json.dumps(report, indent=2))
    (destination / "capture-events.json").write_text(json.dumps(capture_report, indent=2))
