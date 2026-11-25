function Copy-KelpieBranding([string]$SourceDll, [string]$DestinationExe) {
  if (-not ("KelpieResourceStamp" -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class KelpieResourceStamp {
  const int DataFile = 2, Version = 16, GroupIcon = 14, Icon = 3, Lang = 1033;
  [DllImport("kernel32", SetLastError=true)] static extern IntPtr LoadLibraryEx(string p, IntPtr h, int f);
  [DllImport("kernel32", SetLastError=true)] static extern bool FreeLibrary(IntPtr h);
  [DllImport("kernel32", SetLastError=true)] static extern IntPtr FindResource(IntPtr h, IntPtr n, IntPtr t);
  [DllImport("kernel32", SetLastError=true)] static extern IntPtr LoadResource(IntPtr h, IntPtr r);
  [DllImport("kernel32", SetLastError=true)] static extern uint SizeofResource(IntPtr h, IntPtr r);
  [DllImport("kernel32", SetLastError=true)] static extern IntPtr LockResource(IntPtr d);
  [DllImport("kernel32", SetLastError=true)] static extern IntPtr BeginUpdateResource(string p, bool deleteExisting);
  [DllImport("kernel32", SetLastError=true)] static extern bool UpdateResource(IntPtr h, IntPtr t, IntPtr n, ushort l, byte[] d, uint s);
  [DllImport("kernel32", SetLastError=true)] static extern bool EndUpdateResource(IntPtr h, bool discard);
  static byte[] Read(IntPtr module, int type, int name) {
    IntPtr resource = FindResource(module, (IntPtr)name, (IntPtr)type);
    if (resource == IntPtr.Zero) throw new InvalidOperationException("Missing source resource " + type + "/" + name);
    uint size = SizeofResource(module, resource); byte[] bytes = new byte[size];
    Marshal.Copy(LockResource(LoadResource(module, resource)), bytes, 0, (int)size); return bytes;
  }
  static void Put(IntPtr update, int type, int name, byte[] value) {
    if (!UpdateResource(update, (IntPtr)type, (IntPtr)name, Lang, value, (uint)value.Length))
      throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
  }
  public static void Copy(string source, string destination) {
    IntPtr module = LoadLibraryEx(source, IntPtr.Zero, DataFile);
    if (module == IntPtr.Zero) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
    IntPtr update = IntPtr.Zero;
    try {
      byte[] version = Read(module, Version, 1), group = Read(module, GroupIcon, 101);
      update = BeginUpdateResource(destination, false);
      if (update == IntPtr.Zero) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
      Put(update, Version, 1, version); Put(update, GroupIcon, 101, group);
      int count = BitConverter.ToUInt16(group, 4);
      for (int i = 0; i < count; i++) { int id = BitConverter.ToUInt16(group, 6 + i * 14 + 12); Put(update, Icon, id, Read(module, Icon, id)); }
      if (!EndUpdateResource(update, false)) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
      update = IntPtr.Zero;
    } finally { if (update != IntPtr.Zero) EndUpdateResource(update, true); FreeLibrary(module); }
  }
}
'@
  }
  [KelpieResourceStamp]::Copy($SourceDll, $DestinationExe)
}
