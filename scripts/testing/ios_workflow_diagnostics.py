"""Export only fixed native navigation lease states from XCTest diagnostic logs."""
import collections
import json
from pathlib import Path
import re
import subprocess

STATES = frozenset({
    "awaiting-start", "destination-reserved", "awaiting-issue",
    "start-before-issue", "already-invalid", "second-start", "previous-version-changed",
    "missing-issued-token", "missing-callback-token", "unexpected-navigation-token", "duplicate-issue",
})
EVENT = re.compile(r"\[WorkflowNavigationLease\] (invalid|wait-refused|timeout)=([a-z-]+)(?:\s|$)")


def fixed_events(lines):
    events = collections.Counter()
    for line in lines:
        found = EVENT.search(line)
        if found and found[2] in STATES:
            events[found[1] + "=" + found[2]] += 1
    return dict(sorted(events.items()))


def export_lease_diagnostics(result, destination):
    raw = destination.parent.parent / ("private-navigation-diagnostics-" + destination.name)
    try:
        subprocess.run(
            ["xcrun", "xcresulttool", "export", "diagnostics", "--path", str(result), "--output-path", str(raw)],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120,
        )
        events = collections.Counter()
        for file in raw.rglob("StandardOutputAndStandardError*.txt"):
            with file.open(errors="replace") as stream:
                events.update(fixed_events(stream))
        report = {"events": dict(sorted(events.items()))}
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        report = {"unavailable": type(error).__name__}
    (destination / "navigation-lease.json").write_text(json.dumps(report, indent=2))
