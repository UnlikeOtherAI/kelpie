import test from "node:test";
import assert from "node:assert/strict";
import { headlessEnvironment, installHeadlessEnvironment } from "./headless-control-environment.mjs";
test("headless control strips desktop and accessibility connections", () => {
  const source = { DISPLAY: ":0", WAYLAND_DISPLAY: "wayland-0", WAYLAND_SOCKET: "3", XAUTHORITY: "/secret",
    DBUS_SESSION_BUS_ADDRESS: "unix:path=/private", AT_SPI_BUS_ADDRESS: "unix:path=/private",
    GNOME_SETUP_DISPLAY: ":1", GDK_BACKEND: "wayland", HOME: "/user", OTHER: "retained" };
  const clean = headlessEnvironment(source, "/owned/runtime");
  for (const key of ["DISPLAY", "WAYLAND_DISPLAY", "WAYLAND_SOCKET", "XAUTHORITY", "DBUS_SESSION_BUS_ADDRESS",
    "AT_SPI_BUS_ADDRESS", "GNOME_SETUP_DISPLAY", "GDK_BACKEND"]) assert.equal(key in clean, false);
  assert.equal(clean.XDG_RUNTIME_DIR, "/owned/runtime");
  assert.equal(clean.TMPDIR, "/owned/runtime");
  assert.equal(clean.OTHER, "retained");
  assert.equal(source.DISPLAY, ":0");
  installHeadlessEnvironment(source, "/owned/runtime");
  assert.deepEqual(source, clean);
});
