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

// Existing HTTP listener lifecycle output, reduced to fixed labels.
export function serverLifecycleSignal(line){
 const match=/^\[HTTPServer\] Listening on port (\d{1,5})$/.exec(line);
 if(match)return {state:"listening",port:match[1]==="28420"?"requested":match[1]==="8420"?"default":"other"};
 if(line.startsWith("[HTTPServer] Listener failed:"))return {state:"failed"};
 if(line.startsWith("[HTTPServer] Failed to create listener:"))return {state:"create-failed"};
 return null;
}

export function listenerTransitionSignal(line){
 const update=/^\[WorkflowListener\] event=service-update$/.exec(line);
 if(update)return {event:"service-update"};
 const failure=/^\[WorkflowListener\] event=failed domain=(posix|dns|tls|other) code=(-?\d{1,9})$/.exec(line);
 if(failure)return {event:"failed",domain:failure[1],code:Number(failure[2])};
 const renderer=/^\[WorkflowRenderer\] event=(begin|created|active|service-update) engine=(webkit|chromium)$/.exec(line);
 return renderer?{event:renderer[1],engine:renderer[2]}:null;
}

export function captureCoherenceSignal(line){
 const match=/^\[WorkflowCaptureCoherence\] sample=(screenshot|critical|movie) change=(document|viewport)$/.exec(line);
 return match?{sample:match[1],change:match[2]}:null;
}

// Bounded numeric timing aggregates only; no positions, content, or raw logs.
export function captureTimingSignal(line){
 const coherent=/^\[WorkflowCaptureTiming\] sample=(screenshot|critical|movie) engine=(webkit|chromium|other) model=coherent ms=(\d{1,5}),(\d{1,5}),(\d{1,5})$/.exec(line);
 if(coherent)return {sample:coherent[1],engine:coherent[2],model:"coherent",stagesMs:coherent.slice(3).map(Number)};
 const match=/^\[WorkflowCaptureTiming\] sample=(screenshot|critical|movie) engine=(webkit|chromium|other) ms=(\d{1,5}),(\d{1,5}),(\d{1,5}),(\d{1,5}),(\d{1,5})$/.exec(line);
 return match?{sample:match[1],engine:match[2],stagesMs:match.slice(3).map(Number)}:null;
}
export function pointerTimingSignal(line){
 const match=/^\[WorkflowPointerTiming\] engine=(webkit|chromium|other) elapsed=(\d{1,5}) updates=(\d{1,5}) updateGap=(\d{1,5}) draws=(\d{1,5}) drawGap=(\d{1,5}) complete=([01])$/.exec(line);
 return match?{engine:match[1],elapsedMs:Number(match[2]),updates:Number(match[3]),maxUpdateGapMs:Number(match[4]),
  draws:Number(match[5]),maxDrawGapMs:Number(match[6]),completed:match[7]==="1"}:null;
}

// Fixed retiree lifecycle labels only, never page content or window identifiers.
export function retireeSignal(line){
 const match=/^\[WorkflowRetiree\] event=(start|retire|skipped) reason=(none|expired|missing|inactive|identity|visibility|document|target|geometry|issue|movie|marker)$/.exec(line);
 return match?{event:match[1],reason:match[2]}:null;
}

// Only the compiled hosted experiment emits this fixed mode.
export function cefPumpSignal(line){
 const match=/^\[WorkflowCEFPump\] mode=(legacy|scheduled)$/.exec(line);
 return match?.[1]??null;
}

// Numeric events from the compile-gated synthetic CEF fixture only.
export function hostedStreamSignal(line){
 if(line==="[WorkflowHostedStream] event=started")return {event:"started"};
 if(line==="[WorkflowHostedStream] event=discarded")return {event:"discarded"};
 const refusal=/^\[WorkflowHostedStream\] event=refusal reason=(stop|authority|fixture|identity|document|viewport|seal|sample|audit)$/.exec(line);
 if(refusal)return {event:"refusal",reason:refusal[1]};
 const probe=/^\[WorkflowHostedStream\] event=probe received=(\d{1,3}) consumed=(\d{1,3}) malformed=(\d{1,3}) metadata=(\d{1,2}) rejected=(\d{1,3}) drop=(\d{1,3}) decode=(\d{1,3}) stop=(\d{1,3}) ackfail=(\d{1,3}) decodefail=(\d{1,3}) overflow=(\d{1,3}) detached=(\d{1,3}) identity=(\d{1,3}) protocol=(\d{1,3}) stopped=([01])$/.exec(line);
 if(probe){const values=probe.slice(1).map(Number); if(values[3]>63)return null;
  const [received,consumed,malformed,metadata,rejected,drop,decode,stop,ackfail,decodefail,overflow,detached,identity,protocol,stopped]=values;
  return {event:"probe",received,consumed,malformed,metadata,rejected,drop,decode,stop,ackfail,decodefail,overflow,detached,identity,protocol,stopped};}
 const complete=/^\[WorkflowHostedStream\] event=complete count=(\d{1,2})$/.exec(line);
 if(complete&&Number(complete[1])<=64)return {event:"complete",count:Number(complete[1])};
 const sample=/^\[WorkflowHostedStream\] event=sample index=(\d{1,2}) receipt=(\d{1,4}) protocol=(\d{1,4}) x=(\d{1,4}) y=(\d{1,4})$/.exec(line);
 if(!sample)return null;
 const [index,receiptMs,protocolMs,x,y]=sample.slice(1).map(Number);
 return index<64&&receiptMs<=5000&&protocolMs<=5000&&x<=1920&&y<=1920?{event:"sample",index,receiptMs,protocolMs,x,y}:null;
}
