using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Threading;
using System.Web.Script.Serialization;

public static class OwnedStartupObserver {
  [StructLayout(LayoutKind.Sequential)] struct IoCounters {
    public ulong ReadOperations, WriteOperations, OtherOperations, ReadBytes, WriteBytes, OtherBytes;
  }
  [StructLayout(LayoutKind.Sequential)] struct TcpRow {
    public uint State, LocalAddress, LocalPort, RemoteAddress, RemotePort, Pid;
  }
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetProcessIoCounters(IntPtr process, out IoCounters counters);
  [DllImport("iphlpapi.dll", SetLastError=true)] static extern uint GetExtendedTcpTable(IntPtr table, ref int size, bool order, int family, int tableClass, int reserved);
  [DllImport("user32.dll")] static extern bool EnumWindows(WindowCallback callback, IntPtr data);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr window);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetClassName(IntPtr window, System.Text.StringBuilder name, int size);
  delegate bool WindowCallback(IntPtr window, IntPtr data);

  static bool HasListener(int pid, int port) {
    int size=0; GetExtendedTcpTable(IntPtr.Zero,ref size,true,2,5,0);
    if(size<=0 || size>4*1024*1024) return false;
    IntPtr memory=Marshal.AllocHGlobal(size);
    try {
      if(GetExtendedTcpTable(memory,ref size,true,2,5,0)!=0) return false;
      int count=Marshal.ReadInt32(memory); int rowSize=Marshal.SizeOf(typeof(TcpRow));
      if(count<0 || 4+(long)count*rowSize>size) return false;
      for(int i=0;i<count;i++) {
        var row=(TcpRow)Marshal.PtrToStructure(IntPtr.Add(memory,4+i*rowSize),typeof(TcpRow));
        int localPort=(ushort)IPAddress.NetworkToHostOrder((short)(row.LocalPort&0xffff));
        if(row.Pid==(uint)pid && row.State==2 && localPort==port) return true;
      }
      return false;
    } finally { Marshal.FreeHGlobal(memory); }
  }
  static object WindowFacts(int pid) {
    int count=0, visible=0;
    EnumWindows(delegate(IntPtr window,IntPtr unused) {
      uint owner;GetWindowThreadProcessId(window,out owner);
      if(owner!=(uint)pid)return true;
      var name=new System.Text.StringBuilder(128);
      if(GetClassName(window,name,name.Capacity)>0 && name.ToString()=="Kelpie") {
        count++;if(IsWindowVisible(window))visible++;
      }
      return true;
    },IntPtr.Zero);
    return new { mainWindows=count, visibleMainWindows=visible };
  }
  public static int Main(string[] args) {
    if(args.Length==1 && args[0]=="--self-test") {
      var listener=new TcpListener(IPAddress.Loopback,0);listener.Start();
      try {
        int testPort=((IPEndPoint)listener.LocalEndpoint).Port;IoCounters io;
        bool found=HasListener(Process.GetCurrentProcess().Id,testPort),counters=GetProcessIoCounters(Process.GetCurrentProcess().Handle,out io);
        if(!found||!counters)return 3;
        Console.WriteLine(new JavaScriptSerializer().Serialize(new { ownListener=found, ioCounters=counters }));
        return 0;
      } finally { listener.Stop(); }
    }
    if(args.Length!=6)return 2;
    int pid=int.Parse(args[0],CultureInfo.InvariantCulture),port=int.Parse(args[2],CultureInfo.InvariantCulture);
    string expected=Path.GetFullPath(args[1]),readiness=args[3],done=args[4],output=args[5];
    var records=new List<object>();var clock=Stopwatch.StartNew();DateTime? started=null;
    ulong? oldRead=null,oldWrite=null;long? oldCpu=null;
    try {
      while(clock.ElapsedMilliseconds<45000 && records.Count<45 && !File.Exists(done)) {
        Process process;
        try { process=Process.GetProcessById(pid); } catch(ArgumentException) { records.Add(new { elapsedMs=clock.ElapsedMilliseconds, state="exited" });break; }
        using(process) {
          try {
            string actual=Path.GetFullPath(process.MainModule.FileName);
            DateTime began=process.StartTime.ToUniversalTime();
            if(process.SessionId!=1 || !String.Equals(actual,expected,StringComparison.OrdinalIgnoreCase) || (started.HasValue && began!=started.Value)) {
              records.Add(new { elapsedMs=clock.ElapsedMilliseconds, state="identity-changed" });break;
            }
            if(!started.HasValue)started=began;
            long cpu=process.TotalProcessorTime.Ticks;IoCounters io;bool haveIo=GetProcessIoCounters(process.Handle,out io);
            bool firstParty=false,cef=false,modulesAvailable=true;
            try { foreach(ProcessModule module in process.Modules) { if(String.Equals(module.ModuleName,"kelpie.dll",StringComparison.OrdinalIgnoreCase))firstParty=true;
              if(String.Equals(module.ModuleName,"libcef.dll",StringComparison.OrdinalIgnoreCase))cef=true; } }
            catch { modulesAvailable=false; }
            records.Add(new { elapsedMs=clock.ElapsedMilliseconds, state="owned", pid=pid,
              startFileTime=began.ToFileTimeUtc().ToString(CultureInfo.InvariantCulture),
              cpuDeltaTicks=oldCpu.HasValue ? (long?)(cpu-oldCpu.Value) : null,
              privateBytes=process.PrivateMemorySize64, workingSetBytes=process.WorkingSet64,
              readBytesDelta=haveIo && oldRead.HasValue && io.ReadBytes>=oldRead.Value ? (ulong?)(io.ReadBytes-oldRead.Value) : null,
              writeBytesDelta=haveIo && oldWrite.HasValue && io.WriteBytes>=oldWrite.Value ? (ulong?)(io.WriteBytes-oldWrite.Value) : null,
              modulesAvailable=modulesAvailable, firstPartyDll=firstParty, libcef=cef,
              windows=WindowFacts(pid), listener=HasListener(pid,port), readinessExists=File.Exists(readiness) });
            oldCpu=cpu;if(haveIo){oldRead=io.ReadBytes;oldWrite=io.WriteBytes;}
          } catch { records.Add(new { elapsedMs=clock.ElapsedMilliseconds, state="inspection-unavailable" });break; }
        }
        Thread.Sleep(1000);
      }
      File.WriteAllText(output,new JavaScriptSerializer().Serialize(new { samples=records, completed=File.Exists(done), elapsedMs=clock.ElapsedMilliseconds }));
      return 0;
    } catch { return 1; }
  }
}