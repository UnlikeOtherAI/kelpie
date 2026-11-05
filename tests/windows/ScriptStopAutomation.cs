using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Security.Principal;
using System.Web.Script.Serialization;
using System.Windows.Automation;

public static class ScriptStopAutomation {
  [MTAThread]
  public static int Main(string[] args) {
    try {
      var self=Process.GetCurrentProcess();
      if(args.Length==1 && args[0]=="session") {
        Print(new {sessionId=self.SessionId,user=WindowsIdentity.GetCurrent().Name,
          userSid=WindowsIdentity.GetCurrent().User.Value}); return 0;
      }
      bool capture=args.Length==5 && args[0]=="capture";
      if(!capture && (args.Length!=4 || (args[0]!="pin" && args[0]!="inspect" && args[0]!="invoke")))
        throw new InvalidOperationException("Expected mode, exact PID, executable and start time");
      if(self.SessionId!=1) throw new InvalidOperationException("UIA test requires interactive Session1");
      int pid=int.Parse(args[1],CultureInfo.InvariantCulture);
      var process=Process.GetProcessById(pid);
      string expected=Path.GetFullPath(args[2]),actual=Path.GetFullPath(process.MainModule.FileName);
      if(!string.Equals(expected,actual,StringComparison.OrdinalIgnoreCase) || process.SessionId!=self.SessionId)
        throw new InvalidOperationException("Candidate executable/session identity mismatch");
      var supplied=DateTime.Parse(args[3],CultureInfo.InvariantCulture,DateTimeStyles.RoundtripKind).ToUniversalTime();
      var started=process.StartTime.ToUniversalTime();
      if(args[0]=="pin" ? started<supplied.AddSeconds(-2) : started!=supplied)
        throw new InvalidOperationException("Candidate start-time identity mismatch");
      var owner=new PropertyCondition(AutomationElement.ProcessIdProperty,pid);
      var roots=AutomationElement.RootElement.FindAll(TreeScope.Children,owner);
      var candidates=new List<AutomationElement>();
      var details=new List<object>();
      var condition=new AndCondition(owner,
        new PropertyCondition(AutomationElement.ControlTypeProperty,ControlType.Button),
        new PropertyCondition(AutomationElement.NameProperty,"Stop script"));
      foreach(AutomationElement root in roots) {
        foreach(AutomationElement element in root.FindAll(TreeScope.Descendants,condition)) {
          var info=element.Current;
          var parent=TreeWalker.RawViewWalker.GetParent(element);
          if(parent==null || parent.Current.ProcessId!=pid || parent.Current.ClassName!="KelpieScriptStop" ||
            !string.Equals(info.ClassName,"Button",StringComparison.OrdinalIgnoreCase)) continue;
          object pattern;
          bool available=element.TryGetCurrentPattern(InvokePattern.Pattern,out pattern);
          details.Add(new {name=info.Name,className=info.ClassName,processId=info.ProcessId,
            offscreen=info.IsOffscreen,enabled=info.IsEnabled,invokePatternAvailable=available,
            parentClass=parent.Current.ClassName});
          if(available && info.IsEnabled && !info.IsOffscreen) candidates.Add(element);
        }
      }
      var captured=capture?CaptureOwned(roots,owner,pid,args[4]):new List<object>();
      bool invoked=false;
      if(args[0]=="invoke") {
        if(candidates.Count!=1) throw new InvalidOperationException("Exactly one visible owned Stop InvokePattern is required");
        var button=candidates[0];
        var current=button.Current;
        if(current.ProcessId!=pid || current.IsOffscreen || !current.IsEnabled)
          throw new InvalidOperationException("Stop provider changed before invocation");
        // Standard accessibility invocation only: no focus, keyboard, mouse,
        // window activation, desktop capture or application debug API.
        ((InvokePattern)button.GetCurrentPattern(InvokePattern.Pattern)).Invoke();
        invoked=true;
      }
      Print(new {processId=pid,sessionId=process.SessionId,executable=actual,
        startTime=started.ToString("o"),ownTopLevelRoots=roots.Count,matchingButtons=details,
        visibleInvokableButtons=candidates.Count,invoked=invoked,captured=captured});
      return 0;
    } catch(Exception error) {
      Console.Error.WriteLine(error.GetType().Name+": "+error.Message);
      return 1;
    }
  }

  [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential)]
  private struct NativeRect { public int Left,Top,Right,Bottom; }
  [System.Runtime.InteropServices.DllImport("user32.dll",SetLastError=true)]
  private static extern bool GetWindowRect(IntPtr window,out NativeRect rect);
  [System.Runtime.InteropServices.DllImport("user32.dll")]
  private static extern uint GetWindowThreadProcessId(IntPtr window,out uint process);
  [System.Runtime.InteropServices.DllImport("user32.dll")]
  private static extern bool IsWindowVisible(IntPtr window);
  [System.Runtime.InteropServices.DllImport("user32.dll",SetLastError=true)]
  private static extern bool PrintWindow(IntPtr window,IntPtr memoryDc,uint flags);

  private static List<object> CaptureOwned(AutomationElementCollection roots,
      PropertyCondition owner,int pid,string directory) {
    if(!Path.IsPathRooted(directory) || Directory.Exists(directory))
      throw new InvalidOperationException("Capture output must be a fresh absolute directory");
    Directory.CreateDirectory(directory);
    var result=new List<object>();
    var handles=new HashSet<int>();
    var found=new HashSet<string>();
    var allowed=new HashSet<string>(new [] {"Kelpie","KelpieScriptStop","KelpieScriptPresentation"});
    foreach(AutomationElement root in roots) {
      var elements=new List<AutomationElement>(); elements.Add(root);
      foreach(AutomationElement child in root.FindAll(TreeScope.Descendants,owner)) elements.Add(child);
      foreach(AutomationElement element in elements) {
        var current=element.Current;
        if(current.ProcessId!=pid || !allowed.Contains(current.ClassName) ||
          current.NativeWindowHandle==0 || !handles.Add(current.NativeWindowHandle)) continue;
        found.Add(current.ClassName);
        var window=new IntPtr(unchecked((long)(uint)current.NativeWindowHandle));
        uint actualPid; GetWindowThreadProcessId(window,out actualPid);
        if(actualPid!=(uint)pid) throw new InvalidOperationException("Capture window ownership changed");
        NativeRect rect;
        if(current.IsOffscreen || !IsWindowVisible(window) || !GetWindowRect(window,out rect)) {
          result.Add(new {className=current.ClassName,status="unavailable-or-hidden"}); continue;
        }
        int width=rect.Right-rect.Left,height=rect.Bottom-rect.Top;
        if(width<=0 || height<=0 || width>4096 || height>4096 || (long)width*height>8388608) {
          result.Add(new {className=current.ClassName,status="bounds-outside-limit"}); continue;
        }
        string file=Path.Combine(directory,current.ClassName+"-"+current.NativeWindowHandle+".png");
        DateTime began=DateTime.UtcNow;
        bool printed; long nonBlack=0,red=0; int centerRgb;
        var colors=new HashSet<int>();
        using(var bitmap=new System.Drawing.Bitmap(width,height,System.Drawing.Imaging.PixelFormat.Format32bppRgb)) {
          using(var graphics=System.Drawing.Graphics.FromImage(bitmap)) {
            graphics.Clear(System.Drawing.Color.Black);
            IntPtr dc=graphics.GetHdc();
            try {
              GetWindowThreadProcessId(window,out actualPid);
              if(actualPid!=(uint)pid || !IsWindowVisible(window))
                throw new InvalidOperationException("Capture ownership/visibility changed before PrintWindow");
              printed=PrintWindow(window,dc,2);
            } finally {graphics.ReleaseHdc(dc);}
          }
          var bounds=new System.Drawing.Rectangle(0,0,width,height);
          var data=bitmap.LockBits(bounds,System.Drawing.Imaging.ImageLockMode.ReadOnly,
            System.Drawing.Imaging.PixelFormat.Format32bppRgb);
          try {
            var row=new byte[width*4];
            for(int y=0;y<height;y++) {
              System.Runtime.InteropServices.Marshal.Copy(IntPtr.Add(data.Scan0,y*data.Stride),row,0,row.Length);
              for(int x=0;x<width;x++) {
                int at=x*4,b=row[at],g=row[at+1],r=row[at+2],rgb=(r<<16)|(g<<8)|b;
                if(r+g+b>24) nonBlack++;
                if(r>190 && g<180 && b<180) red++;
                if(colors.Count<256) colors.Add(rgb);
              }
            }
          } finally {bitmap.UnlockBits(data);}
          centerRgb=bitmap.GetPixel(width/2,height/2).ToArgb()&0xFFFFFF;
          GetWindowThreadProcessId(window,out actualPid);
          if(actualPid!=(uint)pid || !IsWindowVisible(window))
            throw new InvalidOperationException("Capture ownership/visibility changed before PNG persistence");
          using(var stream=new FileStream(file,FileMode.CreateNew,FileAccess.Write,FileShare.Read))
            bitmap.Save(stream,System.Drawing.Imaging.ImageFormat.Png);
        }
        string hash;
        using(var stream=File.OpenRead(file))
        using(var sha=System.Security.Cryptography.SHA256.Create())
          hash=BitConverter.ToString(sha.ComputeHash(stream)).Replace("-","").ToLowerInvariant();
        string status=!printed?"printwindow-failed":nonBlack<16||colors.Count<3?"black-or-blank-unsupported":"pixels-captured";
        if(status=="pixels-captured" && current.ClassName=="KelpieScriptPresentation" && nonBlack<(long)width*height*.8)
          status="layer-transparency-or-black-background-unsupported";
        if(status=="pixels-captured" && current.ClassName=="Kelpie" &&
          (((centerRgb>>16)&255)+((centerRgb>>8)&255)+(centerRgb&255))<600)
          status="renderer-black-or-unavailable";
        result.Add(new {className=current.ClassName,status=status,file=file,sha256=hash,width=width,height=height,
          processId=pid,printWindowReturned=printed,nonBlackPixels=nonBlack,redPixels=red,
          distinctRgbCapped=colors.Count,centerRgb=centerRgb,beganAt=began.ToString("o"),endedAt=DateTime.UtcNow.ToString("o"),
          method="PrintWindow PW_RENDERFULLCONTENT into memory bitmap; no desktop DC"});
      }
    }
    foreach(string className in allowed) if(!found.Contains(className))
      result.Add(new {className=className,status="not-exposed-by-owned-uia-tree"});
    return result;
  }
  private static void Print(object value) {
    Console.WriteLine(new JavaScriptSerializer().Serialize(value));
  }
}
