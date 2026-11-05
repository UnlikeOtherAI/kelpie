// Missing is a normal startup state; a different or ambiguous owner is never ready.
export function listenerState(owners,pid){
 if(owners.length===0)return "missing";
 return owners.length===1&&owners[0]===pid?"owned":"foreign";
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
