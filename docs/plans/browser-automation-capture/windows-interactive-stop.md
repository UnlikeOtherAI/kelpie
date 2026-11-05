# Windows interactive Stop acceptance plan

This is test instrumentation. No task has been registered or run. The existing Windows execution policy is Restricted and stays unchanged.

## Read-only prerequisites

On 5 November 2026, Maxis reported Maxis\\ondre as both the SSH caller and interactive user. The SSH token has administrator membership, Task Scheduler is running, its COM API connects, and the ScheduledTasks cmdlets exist. The proposed exact task name is absent. Own-account interactive-token tasks do not require a password; see [Microsoft security contexts](https://learn.microsoft.com/en-us/windows/win32/taskschd/security-contexts-for-running-tasks) and [interactive logon type](https://learn.microsoft.com/en-us/windows/win32/taskschd/principal-logontype). Registration permission has not been exercised.

The public normal browser launch through Windows OpenSSH creates a Session0 process. It does not produce a discoverable interactive UIA window. Both hidden and normal Session0 probes found zero own top-level UIA roots. No InvokePattern, focus or input was attempted in those probes.

A Node action and small standard .NET UIAutomationClient executable avoid PowerShell script-policy changes. The installed Framework64 v4.0.30319 csc.exe and WPF UIAutomationClient/UIAutomationTypes/WindowsBase assemblies are present. The test client has not yet been compiled.

## Exact owned action

- Task: \\KelpieCapture-Windows-Stop-20261105-9333ff50; no trigger, on-demand only.
- Principal: Maxis\\ondre, Interactive token, Limited run level. No password, stored credentials, service, elevation or policy change.
- Executable: C:\\Program Files\\nodejs\\node.exe.
- Action source: D:\\Worktrees\\kelpie\\capture-windows-20261104\\tests\\windows\\run-interactive-stop-acceptance.mjs.
- UIA source: tests/windows/ScriptStopAutomation.cs.
- UIA binary: D:\\BuildArtifacts\\kelpie\\capture-windows-20261104\\uia-client\\ScriptStopAutomation.exe.
- Candidate: D:\\BuildArtifacts\\kelpie\\capture-windows-20261104\\app\\kelpie.exe.
- Verified CLI entry: D:\\Temp\\capture-windows-20261104\\cli-final\\node_modules\\@unlikeotherai\\kelpie\\dist\\index.js.
- Evidence root: D:\\BuildArtifacts\\kelpie\\capture-windows-20261104\\uia-session1-9333.
- Private root: D:\\Temp\\capture-windows-20261104\\uia-session1-9333.
- Public alias: capture-uia-session1-9333; port28420; private profile and CLI home under that private root.

The five positional action arguments are candidate EXE, CLI entry, UIA executable, evidence root and private root, in that order. Every path must be absolute and both roots must be fresh. The task working directory is the dedicated Windows worktree.

## Guards and expected result

1. Assert the action itself is in Session1 as Maxis\\ondre before starting an app.
2. Verify the9333 candidate EXE and DLL hashes. Public browser register/normal launch writes the private alias record; no handcrafted running record.
3. Pin exact process path, PID, start time, Session1, readiness launch ID and loopback listener PID. Authenticate through that readiness grant, held only in memory.
4. Navigate the owned tab to about:blank. Start one authenticated commentary/wait capture with GIF, MP4 and PNG output.
5. Find exactly one visible enabled own-process standard Button named Stop script, whose UIA parent is KelpieScriptStop. Recheck the authenticated run ID immediately before invocation.
6. Invoke only that button through standard InvokePattern, once. No SetFocus, SendInput, mouse, keyboard, foreground APIs, desktop screenshots, CUA/VNC or other windows.
7. Inspect aborted terminal status, retrieve partial artifacts by authenticated IDs/chunks and verify hashes. Run a new workflow to verify recovery.
8. Persist the report before cleanup. Finally use public browser stop on that exact private alias. Do not terminate or alter PID52960 or any other task.

The Node action has a120-second test deadline, bounded child/API calls and public cleanup. The task hard bound is180 seconds, leaving teardown time. If the provider is absent/offscreen, session identity differs, the task cannot register or any operation needs focus/input, fail safely and retain the UI gate.

## Registration and teardown after root review

Registration uses New-ScheduledTaskAction for the Node executable, New-ScheduledTaskPrincipal -UserId Maxis\\ondre -LogonType Interactive -RunLevel Limited and New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Seconds180) -MultipleInstances IgnoreNew. Register-ScheduledTask must omit Force, Trigger and Password. Recheck that the exact task name is absent before registration.

Root reviews the pushed source and frozen action arguments before registration/run. Record only this task's exported definition, state and result. Do not enumerate other task actions. The monitor is bounded and preserves failures; if needed, planned teardown uses the same public private-alias stop path. After the action exits and owned browser/readiness/socket cleanup is verified, unregister only the exact task whose principal and action still match this plan. No persistent task or service remains.

Matching base195eb/final native UI screenshots still require a task-owned base binary and capture restricted to its own windows. No screenshot of another task or renderer-only export may substitute for native window evidence.
