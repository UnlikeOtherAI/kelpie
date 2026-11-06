// Match the existing headless harness's private runtime and desktop isolation.
const desktopNames = ["DISPLAY", "WAYLAND_DISPLAY", "WAYLAND_SOCKET", "XAUTHORITY", "DBUS_SESSION_BUS_ADDRESS",
  "AT_SPI_BUS_ADDRESS", "GNOME_SETUP_DISPLAY", "GDK_BACKEND"];
export function headlessEnvironment(source, runtime) {
  const env = { ...source };
  for (const name of desktopNames) delete env[name];
  env.XDG_RUNTIME_DIR = runtime;
  env.TMPDIR = runtime;
  return env;
}
export function installHeadlessEnvironment(target, runtime) {
  const clean = headlessEnvironment(target, runtime);
  for (const name of desktopNames) delete target[name];
  target.XDG_RUNTIME_DIR = clean.XDG_RUNTIME_DIR;
  target.TMPDIR = clean.TMPDIR;
}
