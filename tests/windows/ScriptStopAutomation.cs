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
      if(args.Length!=4 || (args[0]!="pin" && args[0]!="inspect" && args[0]!="invoke"))
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
        visibleInvokableButtons=candidates.Count,invoked=invoked});
      return 0;
    } catch(Exception error) {
      Console.Error.WriteLine(error.GetType().Name+": "+error.Message);
      return 1;
    }
  }
  private static void Print(object value) {
    Console.WriteLine(new JavaScriptSerializer().Serialize(value));
  }
}
