import { runCommand } from "./process.mjs";

// Windows PowerShell compiles this with its C# 5 compiler: no string
// interpolation or out-variable declarations.
const WINDOW_TYPE = [
  "Add-Type @'",
  "using System; using System.Collections.Generic; using System.Runtime.InteropServices; using System.Text;",
  "public static class KelpieWindows {",
  " public delegate bool EnumProc(IntPtr hwnd, IntPtr parameter);",
  " [DllImport(\"user32.dll\")] static extern bool EnumWindows(EnumProc callback, IntPtr parameter);",
  " [DllImport(\"user32.dll\")] static extern bool EnumChildWindows(IntPtr parent, EnumProc callback, IntPtr parameter);",
  " [DllImport(\"user32.dll\")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);",
  " [DllImport(\"user32.dll\", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int count);",
  " [DllImport(\"user32.dll\", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr hwnd, StringBuilder text, int count);",
  " [DllImport(\"user32.dll\")] static extern bool PostMessage(IntPtr hwnd, uint message, IntPtr w, IntPtr l);",
  " static List<IntPtr> Shells(uint target) {",
  "  var shells = new List<IntPtr>();",
  "  EnumWindows(delegate(IntPtr hwnd, IntPtr parameter) {",
  "   uint pid; GetWindowThreadProcessId(hwnd, out pid);",
  "   var name = new StringBuilder(64); GetClassName(hwnd, name, name.Capacity);",
  "   if (pid == target && name.ToString() == \"Kelpie\") shells.Add(hwnd);",
  "   return true;",
  "  }, IntPtr.Zero);",
  "  return shells;",
  " }",
  " public static string[] Texts(uint target) {",
  "  var texts = new List<string>();",
  "  foreach (var shell in Shells(target)) {",
  "   EnumChildWindows(shell, delegate(IntPtr hwnd, IntPtr parameter) {",
  "    var text = new StringBuilder(512); GetWindowText(hwnd, text, text.Capacity);",
  "    if (text.Length > 0) texts.Add(text.ToString());",
  "    return true;",
  "   }, IntPtr.Zero);",
  "  }",
  "  return texts.ToArray();",
  " }",
  " public static int Close(uint target) {",
  "  var shells = Shells(target);",
  "  foreach (var shell in shells) PostMessage(shell, 0x0010, IntPtr.Zero, IntPtr.Zero);",
  "  return shells.Count;",
  " }",
  "}",
  "'@",
].join("\n");

function validPid(pid) {
  const value = Number(pid);
  if (!Number.isSafeInteger(value) || value < 1) throw new Error("Browser PID is invalid");
  return value;
}

async function runWindowScript(line) {
  const probe = await runCommand("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", `${WINDOW_TYPE}\n${line}`]);
  if (probe.code !== 0) throw new Error(`Window probe failed: ${probe.stderr || probe.stdout}`);
  return probe.stdout.trim();
}

/**
 * Returns the startup failure a Kelpie shell window is showing, or undefined.
 * A failed startup keeps its window open and names the stage that failed, so
 * this is how a caller outside the process learns which stage it was.
 */
export async function startupFailureText(pid) {
  const output = await runWindowScript(`ConvertTo-Json -Compress @([KelpieWindows]::Texts([uint32]${validPid(pid)}))`);
  const texts = JSON.parse(output || "[]");
  return (Array.isArray(texts) ? texts : [texts]).find(text => text.startsWith("Browser startup failed"));
}

/** Asks an owned Kelpie shell to close as a person would, with WM_CLOSE. */
export async function closeShellWindow(pid) {
  const count = Number(await runWindowScript(`[KelpieWindows]::Close([uint32]${validPid(pid)})`));
  if (count < 1) throw new Error("No Kelpie shell window was found to close");
}
