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
    "native-bounds", "native-insets", "pixel-ratio", "layout-size", "visible-size", "scale", "presentation-parent",
    "responder-accepted", "responder-refused", "responder-descendant", "responder-outside",
    "postedit-authorized", "postedit-result",
    "text-interaction-still-on", "text-interaction-disabled", "text-interaction-restored-on", "text-interaction-restored-off",
    *(f"snapshot-{value}" for value in ("native-bounds", "native-insets", "pixel-ratio", "layout-size", "visible-size", "scale")),
    *(f"focus-{value}" for value in (
        "document-focus", "target-focus", "identity", "viewport", "eligibility",
        "budget", "geometry", "hit", "sensitivity", "unknown",
    )),
    *(f"observation-{value}" for value in (
        "BUSY", "TAB_CHANGED", "WEBVIEW_ERROR", "UNAUTHORIZED", "RECORDING_IN_PROGRESS",
        "TIMEOUT", "INVALID_PARAM", "INVALID_VALUE", "UNSUPPORTED", "INVALID_ARGUMENTS",
        "COMMAND_FAILED", "ACCESS_DENIED", "TAB_REQUIRED", "STALE_REFERENCE", "CANCELLED",
        "READINESS_FAILED", "EXTRACT_FAILED", "BROWSER_FAILED", "BROWSER_BUSY", "PAGE_CHANGED", "OTHER",
    )),
})
KEYBOARD_EVENT = re.compile(r"\[WorkflowKeyboardGeometry\] phase=(will|did) values=([-0-9.,]+)(?:\s|$)")
ADMISSION_EVENT = re.compile(r"\[WorkflowCaptureAdmission\] first=([-0-9.,]+) last=([-0-9.,]+) count=([0-9]+)(?:\s|$)")
INSETS_EVENT = re.compile(r"\[WorkflowCaptureInsets\] before=([-0-9.,]+) after=([-0-9.,]+)(?:\s|$)")
GEOMETRY_EVENT = re.compile(r"\[WorkflowCaptureGeometry\] before=([0-9.,]+) after=([0-9.,]+)(?:\s|$)")
PROJECTION_EVENT = re.compile(r"\[WorkflowProjection\] values=([-0-9.,]+)(?:\s|$)")
ENCODE_EVENT = re.compile(r"\[WorkflowCaptureEncode\] elapsedMs=([0-9]+)(?:\s|$)")
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


def fixed_projection(line):
    found = PROJECTION_EVENT.search(line)
    if not found:
        return None
    try:
        values = [float(value) for value in found[1].split(",")]
    except ValueError:
        return None
    if len(values) != 17 or not all(math.isfinite(value) and abs(value) <= 10000 for value in values):
        return None
    return values


def fixed_capture_encode(line):
    found = ENCODE_EVENT.search(line)
    if not found:
        return None
    value = int(found[1])
    return value if 0 <= value <= 10000 else None


def fixed_keyboard_geometry(line):
    found = KEYBOARD_EVENT.search(line)
    if not found:
        return None
    try:
        values = [float(number) for number in found[2].split(",")]
    except ValueError:
        return None
    if len(values) != 20 or not all(math.isfinite(number) and abs(number) <= 10000 for number in values):
        return None
    if any(value not in (0, 1) for value in values[:6]):
        return None
    return {"phase": found[1], "values": values}


def fixed_admission(line):
    found = ADMISSION_EVENT.search(line)
    if not found:
        return None
    try:
        first, last = ([float(number) for number in value.split(",")] for value in found.groups()[:2])
        count = int(found[3])
    except ValueError:
        return None
    if len(first) != 10 or len(last) != 10 or not 1 <= count <= 10000 or not all(
        math.isfinite(number) and abs(number) <= 10000 for number in first + last
    ):
        return None
    return {"first": first, "last": last, "count": count}


def fixed_capture_insets(line):
    found = INSETS_EVENT.search(line)
    if not found:
        return None
    try:
        before, after = ([float(number) for number in value.split(",")] for value in found.groups())
    except ValueError:
        return None
    if len(before) != 9 or len(after) != 9 or not all(
        math.isfinite(number) and abs(number) <= 10000 for number in before + after
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
        insets = []
        encodes = []
        projections = []
        admissions = []
        keyboards = []
        for file in raw.rglob("StandardOutputAndStandardError*.txt"):
            with file.open(errors="replace") as stream:
                for line in stream:
                    events.update(fixed_events((line,)))
                    capture.update(fixed_capture_events((line,)))
                    observed = fixed_capture_geometry(line)
                    if observed and len(geometry) < 100:
                        geometry.append(observed)
                    inset = fixed_capture_insets(line)
                    if inset and len(insets) < 100:
                        insets.append(inset)
                    encode = fixed_capture_encode(line)
                    if encode is not None and len(encodes) < 1000:
                        encodes.append(encode)
                    keyboard = fixed_keyboard_geometry(line)
                    if keyboard and len(keyboards) < 100:
                        keyboards.append(keyboard)
                    admission = fixed_admission(line)
                    if admission and len(admissions) < 100:
                        admissions.append(admission)
                    projection = fixed_projection(line)
                    if projection is not None and len(projections) < 1000:
                        projections.append(projection)
        report = {"events": dict(sorted(events.items()))}
        capture_report = {"events": dict(sorted(capture.items())), "geometry": geometry, "insets": insets, "encodeMs": encodes, "projections": projections, "admissions": admissions, "keyboards": keyboards}
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        report = {"unavailable": type(error).__name__}
        capture_report = report
    (destination / "navigation-lease.json").write_text(json.dumps(report, indent=2))
    (destination / "capture-events.json").write_text(json.dumps(capture_report, indent=2))
