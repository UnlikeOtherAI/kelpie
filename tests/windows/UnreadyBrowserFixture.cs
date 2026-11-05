using System;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Threading;

// A task-owned executable that never writes browser readiness.
public static class UnreadyBrowserFixture {
  public static int Main(string[] args) {
    for (int index = 0; index + 1 < args.Length; index++) {
      if (args[index] != "--profile-dir") continue;
      Directory.CreateDirectory(args[index + 1]);
      var process = Process.GetCurrentProcess();
      string line = process.Id.ToString(CultureInfo.InvariantCulture) + "\n" +
        process.StartTime.ToUniversalTime().ToString("o", CultureInfo.InvariantCulture);
      File.WriteAllText(Path.Combine(args[index + 1], "fixture-process.txt"), line);
      Thread.Sleep(TimeSpan.FromSeconds(30));
      return 0;
    }
    return 2;
  }
}