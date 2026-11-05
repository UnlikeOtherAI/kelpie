#!/usr/bin/env python3
"""Standard AT-SPI Action, pinned to one owned GTK process. Never focus or send input."""
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import time
import gi

gi.require_version("Gio", "2.0")
gi.require_version("Atspi", "2.0")
from gi.repository import Gio, GLib, Atspi

pid, binary, ticks, expected_hash, mode = sys.argv[1:]
pid = int(pid)
assert pid > 1 and mode in ("window", "inspect", "invoke")
assert os.path.isabs(binary) and re.fullmatch("[a-f0-9]{64}", expected_hash)
deadline = time.monotonic() + 4.0


def pin():
    proc = Path(f"/proc/{pid}")
    assert proc.stat().st_uid == os.getuid(), "Foreign process owner"
    assert os.path.realpath(proc / "exe") == os.path.realpath(binary), "Native executable changed"
    data = (proc / "stat").read_text()
    assert data[data.rfind(")") + 2:].split()[19] == ticks, "Native process identity changed"
    digest = hashlib.sha256()
    size = 0
    with (proc / "exe").open("rb") as executable:
        while block := executable.read(1048576):
            size += len(block)
            assert size <= 134217728
            digest.update(block)
    assert digest.hexdigest() == expected_hash, "Native executable bytes changed"


def call(connection, destination, path, interface, method, parameters=None):
    remaining = int((deadline - time.monotonic()) * 1000)
    assert remaining > 0, "Accessibility inspection deadline"
    return connection.call_sync(destination, path, interface, method, parameters, None,
                                Gio.DBusCallFlags.NONE, min(remaining, 500), None).unpack()


pin()
if os.environ.get("KELPIE_PRIVATE_ATSPI_ACTION") == "1":
    assert os.environ.get("KELPIE_ISOLATED_WAYLAND") == "1"
    address = os.environ["AT_SPI_BUS_ADDRESS"]
    assert address == os.environ["DBUS_SESSION_BUS_ADDRESS"] and "/run/user/" not in address
else:
    session = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    address = call(session, "org.a11y.Bus", "/org/a11y/bus", "org.a11y.Bus", "GetAddress")[0]
connection = Gio.DBusConnection.new_for_address_sync(
    address, Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION, None, None)
root = "/org/a11y/atspi/accessible/root"
accessible = "org.a11y.atspi.Accessible"
application = "org.a11y.atspi.Application"
action = "org.a11y.atspi.Action"
properties = "org.freedesktop.DBus.Properties"


def property_value(bus, path, interface, name):
    return call(connection, bus, path, properties, "Get", GLib.Variant("(ss)", (interface, name)))[0]


def owner(bus):
    return call(connection, "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                "GetConnectionUnixProcessID", GLib.Variant("(s)", (bus,)))[0]


names = call(connection, "org.freedesktop.DBus", "/org/freedesktop/DBus",
             "org.freedesktop.DBus", "ListNames")[0]
assert len(names) <= 1024
buses = []
for name in names:
    if not name.startswith(":"):
        continue
    try:
        if owner(name) == pid:
            toolkit = property_value(name, root, application, "ToolkitName")
            if isinstance(toolkit, str) and toolkit.lower().startswith("gtk"):
                buses.append(name)
    except GLib.Error:
        continue
assert buses, "The exact native process has no GTK accessibility application"

blocked = {int(getattr(Atspi.Role, name)) for name in
           ("DOCUMENT_WEB", "DOCUMENT_FRAME", "EMBEDDED", "HTML_CONTAINER", "DOCUMENT_TEXT")
           if hasattr(Atspi.Role, name)}
queue = [(bus, root, 0) for bus in buses]
seen, matches, frames = set(), [], []
while queue:
    bus, path, depth = queue.pop(0)
    if (bus, path) in seen:
        continue
    seen.add((bus, path))
    assert len(seen) <= 512 and depth <= 20
    role = call(connection, bus, path, accessible, "GetRole")[0]
    if role in blocked:
        continue
    if role in (int(Atspi.Role.FRAME), int(Atspi.Role.WINDOW)):
        bits = call(connection, bus, path, accessible, "GetState")[0]
        if all(int(state)//32 < len(bits) and bits[int(state)//32] & (1 << (int(state)%32))
               for state in (Atspi.StateType.VISIBLE, Atspi.StateType.SHOWING)):
            frames.append((bus, path))
    if role == int(Atspi.Role.PUSH_BUTTON):
        name = property_value(bus, path, accessible, "Name")
        if name == "Stop script":
            matches.append((bus, path))
    children = call(connection, bus, path, accessible, "GetChildren")[0]
    assert len(children) <= 256
    queue.extend((child_bus, child_path, depth + 1) for child_bus, child_path in children
                 if child_bus in buses and child_path != "/org/a11y/atspi/null")
if mode == "window":
    assert len(frames) == 1, "Owned GTK frame is missing or ambiguous"
    print(json.dumps({"pid": pid, "startTicks": ticks, "toolkit": "gtk", "frameShowing": True, "nodes": len(seen)}))
    sys.exit(0)
assert len(matches) == 1, "Native Stop button is missing or ambiguous"
bus, path = matches[0]
assert owner(bus) == pid
assert property_value(bus, path, accessible, "Name") == "Stop script"
states = call(connection, bus, path, accessible, "GetState")[0]
assert 1 <= len(states) <= 4
required = (Atspi.StateType.VISIBLE, Atspi.StateType.SHOWING, Atspi.StateType.ENABLED, Atspi.StateType.SENSITIVE)
for state in required:
    number = int(state)
    assert number // 32 < len(states) and states[number // 32] & (1 << (number % 32)), "Stop is not actionable onscreen"
count = property_value(bus, path, action, "NActions")
assert 1 <= count <= 8
actions = [call(connection, bus, path, action, "GetName", GLib.Variant("(i)", (index,)))[0] for index in range(count)]
indices = [index for index, name in enumerate(actions) if name in ("click", "press", "activate")]
assert len(indices) == 1, "Native Stop has no unambiguous standard action"
result = {"pid": pid, "startTicks": ticks, "toolkit": "gtk", "name": "Stop script", "role": "push-button",
          "visible": True, "showing": True, "enabled": True, "action": actions[indices[0]], "nodes": len(seen)}
if mode == "invoke":
    pin()
    assert owner(bus) == pid
    result["invoked"] = call(connection, bus, path, action, "DoAction", GLib.Variant("(i)", (indices[0],)))[0]
    assert result["invoked"], "Standard Stop action was refused"
print(json.dumps(result))
