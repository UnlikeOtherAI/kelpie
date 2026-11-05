using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

public static class KelpieConfinedProcess {
  [StructLayout(LayoutKind.Sequential)] struct BasicLimits {
    public long ProcessTime, JobTime; public uint Flags;
    public UIntPtr MinimumWorkingSet, MaximumWorkingSet; public uint ActiveProcesses;
    public UIntPtr Affinity; public uint Priority, Scheduling;
  }
  [StructLayout(LayoutKind.Sequential)] struct IoCounters { public ulong A,B,C,D,E,F; }
  [StructLayout(LayoutKind.Sequential)] struct ExtendedLimits {
    public BasicLimits Basic; public IoCounters Io;
    public UIntPtr ProcessMemory, JobMemory, PeakProcessMemory, PeakJobMemory;
  }
  [StructLayout(LayoutKind.Sequential)] struct Security { public int Length; public IntPtr Descriptor; public int Inherit; }
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)] struct Startup {
    public int Size; public string Reserved, Desktop, Title;
    public int X,Y,Width,Height,XChars,YChars,Fill,Flags; public short Show,ReservedBytes;
    public IntPtr ReservedPointer, Input, Output, Error;
  }
  [StructLayout(LayoutKind.Sequential)] struct ProcessInfo { public IntPtr Process, Thread; public uint Pid,Tid; }
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr CreateJobObject(IntPtr attributes,string name);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetInformationJobObject(IntPtr job,int kind,ref ExtendedLimits value,uint length);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool AssignProcessToJobObject(IntPtr job,IntPtr process);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool CreateProcess(string executable,StringBuilder command,IntPtr processSecurity,IntPtr threadSecurity,bool inherit,uint flags,IntPtr environment,string directory,ref Startup startup,out ProcessInfo process);
  [DllImport("kernel32.dll", SetLastError=true)] static extern uint ResumeThread(IntPtr thread);
  [DllImport("kernel32.dll", SetLastError=true)] static extern uint WaitForSingleObject(IntPtr handle,uint milliseconds);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetExitCodeProcess(IntPtr process,out uint code);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool TerminateProcess(IntPtr process,uint code);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool TerminateJobObject(IntPtr job,uint code);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr CreateFile(string path,uint access,uint share,ref Security security,uint creation,uint flags,IntPtr template);
  static void Require(bool value) { if(!value) throw new Win32Exception(Marshal.GetLastWin32Error()); }
  static string Quote(string value) {
    var result=new StringBuilder("\""); int slashes=0;
    foreach(char c in value) {
      if(c=='\\') { slashes++; continue; }
      if(c=='"') { result.Append('\\',slashes*2+1); result.Append(c); slashes=0; continue; }
      result.Append('\\',slashes); slashes=0; result.Append(c);
    }
    result.Append('\\',slashes*2); return result.Append('"').ToString();
  }
  public static int Run(string executable,string[] args,string directory,string log,int timeout) {
    if(timeout<100 || timeout>1800000) throw new ArgumentOutOfRangeException("timeout");
    IntPtr job=IntPtr.Zero, output=IntPtr.Zero, input=IntPtr.Zero;
    var process=new ProcessInfo(); bool assigned=false;
    try {
      job=CreateJobObject(IntPtr.Zero,null); Require(job!=IntPtr.Zero);
      var limits=new ExtendedLimits();
      // No breakaway flags. Windows enforces these limits even if descendants call Set*.
      limits.Basic.Flags=0x2000|0x10|0x20|0x200;
      limits.JobMemory=new UIntPtr(2147483648UL);
      limits.Basic.Affinity=new UIntPtr(1); limits.Basic.Priority=0x20;
      Require(SetInformationJobObject(job,9,ref limits,(uint)Marshal.SizeOf(typeof(ExtendedLimits))));
      var security=new Security {Length=Marshal.SizeOf(typeof(Security)),Inherit=1};
      output=CreateFile(log,0x40000000,3,ref security,1,0,IntPtr.Zero);
      Require(output!=new IntPtr(-1));
      input=CreateFile("NUL",0x80000000,3,ref security,3,0,IntPtr.Zero);
      Require(input!=new IntPtr(-1));
      var startup=new Startup {Size=Marshal.SizeOf(typeof(Startup)),Flags=0x100,Input=input,Output=output,Error=output};
      var command=new StringBuilder(Quote(executable));
      foreach(string arg in args) command.Append(' ').Append(Quote(arg));
      // Suspended creation closes the interval in which a child could launch outside the job.
      Require(CreateProcess(executable,command,IntPtr.Zero,IntPtr.Zero,true,0x08000004,IntPtr.Zero,directory,ref startup,out process));
      Require(AssignProcessToJobObject(job,process.Process)); assigned=true;
      Require(ResumeThread(process.Thread)!=0xffffffff);
      uint waited=WaitForSingleObject(process.Process,(uint)timeout);
      if(waited==258) { Require(TerminateJobObject(job,124)); WaitForSingleObject(process.Process,2000); return 124; }
      Require(waited==0);
      uint exit; Require(GetExitCodeProcess(process.Process,out exit));
      return unchecked((int)exit);
    } finally {
      if(process.Process!=IntPtr.Zero && !assigned) TerminateProcess(process.Process,125);
      // Closing the only job handle retires only this explicitly assigned tree.
      if(job!=IntPtr.Zero) CloseHandle(job);
      if(process.Thread!=IntPtr.Zero) CloseHandle(process.Thread);
      if(process.Process!=IntPtr.Zero) CloseHandle(process.Process);
      if(output!=IntPtr.Zero && output!=new IntPtr(-1)) CloseHandle(output);
      if(input!=IntPtr.Zero && input!=new IntPtr(-1)) CloseHandle(input);
    }
  }
}
