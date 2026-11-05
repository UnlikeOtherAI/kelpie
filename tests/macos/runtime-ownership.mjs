// Missing is a normal startup state; a different or ambiguous owner is never ready.
export function listenerState(owners,pid){
 if(owners.length===0)return "missing";
 return owners.length===1&&owners[0]===pid?"owned":"foreign";
}

// Keep an empty lsof result distinct from a failed process invocation.
export function listenerProbeFailure(error){
 const stderrPresent=typeof error?.stderr?.length==="number"&&error.stderr.length>0;
 const outcome=error?.status===1&&!stderrPresent?"no-match":"probe-error";
 const causes=new Set(["ENOENT","EACCES","EAGAIN","ETIMEDOUT"]);
 return {outcome,cause:causes.has(error?.code)?error.code:"OTHER",stderrPresent};
}

// Only fixed labels leave the pre-pairing stdout parser, never the message text.
export function startupSignal(line){
 if(line==="[KelpieApp] AppReveal start requested")return "APPREVEAL_START_REQUESTED";
 if(line.startsWith("[KelpieApp] Skipping AppReveal start because port 8421"))return "APPREVEAL_PORT_PROBE_UNAVAILABLE";
 if(line==="[AppReveal] MCP server listening on port 8421")return "APPREVEAL_LISTENING";
 if(line==="[AppReveal] Bonjour advertising as _appreveal._tcp")return "APPREVEAL_ADVERTISING";
 if(line.startsWith("[AppReveal] Server failed:")||line.startsWith("[AppReveal] Failed to create listener:")){
  if(/EADDRINUSE|address already in use|rawValue: 48/i.test(line))return "APPREVEAL_ADDRESS_IN_USE";
  if(/PolicyDenied|NoAuth|-65570|-65555|permission denied|not authorized/i.test(line))return "APPREVEAL_POLICY_DENIED";
  return "APPREVEAL_LISTENER_FAILED";
 }
 return null;
}

// Native fixed outcome labels only; never retain a navigation URL or error message.
export function navigationSignal(line){
 const match=/^\[WorkflowNavigation\] failure=(BUSY|NAVIGATION_ERROR|TIMEOUT|NO_WEBVIEW|TAB_NOT_FOUND|INVALID_URL|RECORDING_IN_PROGRESS|UNCLASSIFIED)$/.exec(line);
 return match?.[1]??null;
}

// Fixed focus state only; never retain a page value or window identifier.
export function editFocusSignal(line){
 const match=/^\[WorkflowEditFocus\] phase=(before|after|result) key=([01u]) responder=([01u]) doc=([01u]) body=([01u]) target=([01u])$/.exec(line);
 return match?{phase:match[1],key:match[2],responder:match[3],documentFocused:match[4],activeBody:match[5],targetFocused:match[6]}:null;
}

// The hosted driver launches this exact executable with these exact arguments.
export function processCommandMatches(command,executable){
 return typeof command==="string"&&typeof executable==="string"&&command.trim()===executable+" --port 28420";
}

// Fixed numeric geometry differences only; no URLs, titles or page content.
export function viewportSignal(line){
 const match=/^\[WorkflowViewport\] bounds=([01]) layout=([01]) visible=([01]) scale=([01]) pixel=([01]) widths=(\d{1,5}\.\d{2}),(\d{1,5}\.\d{2}) heights=(\d{1,5}\.\d{2}),(\d{1,5}\.\d{2})$/.exec(line);
 return match?{boundsSame:match[1]==="1",layoutSame:match[2]==="1",visibleSame:match[3]==="1",scaleSame:match[4]==="1",pixelSame:match[5]==="1",oldWidth:Number(match[6]),newWidth:Number(match[7]),oldHeight:Number(match[8]),newHeight:Number(match[9])}:null;
}

// Fixed native visibility guard flags only; no window identity or page data.
export function workflowVisibilitySignal(line){
 const match=/^\[WorkflowVisibility\] phase=(check|focus) visible=([01u]) hidden=([01u]) key=([01u]) sheet=([01u])$/.exec(line);
 return match?{phase:match[1],visible:match[2],hidden:match[3],key:match[4],sheet:match[5]}:null;
}
