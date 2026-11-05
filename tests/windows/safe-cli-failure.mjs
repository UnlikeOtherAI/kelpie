// Return only bounded, allowlisted facts from CLI output; never retain grants or output text.
export function safeCliFailure(error){
 let data;try{data=JSON.parse(String(error.stdout??""));}catch{}
 const message=String(data?.error?.message??"");
 const categories=new Map([
  ["Kelpie did not publish a valid local readiness file","readiness-timeout"],
  ["Kelpie did not accept orderly shutdown","shutdown-refused"],
  ["Kelpie did not complete orderly shutdown before the deadline","shutdown-deadline"],
  ["Refusing to clear state after a different browser launch replaced readiness","readiness-replaced"],
  ["A live browser already owns this profile; attach to its alias or stop it first","profile-owned"]
 ]);
 const category=categories.get(message)??(/^Kelpie exited before publishing readiness \(exit -?\d+\)$/.test(message)?"exited-before-readiness":
  /^Kelpie failed to start:/.test(message)?"spawn-failed":data?.error?"other-cli-error":"no-cli-error-json");
 const codes=new Set(["BROWSER_LAUNCH_FAILED","BROWSER_STOP_FAILED","BROWSER_NOT_RUNNING","BROWSER_LAUNCH_MISMATCH","BROWSER_LAUNCH_PENDING","BROWSER_CONFIGURATION_INVALID","BROWSER_NOT_REGISTERED"]);
 const retirement=data?.error?.retirement;const outcomes=new Set(["exited","kill-refused","kill-error","exit-wait-expired"]);
 const retirementFact=outcomes.has(retirement?.outcome)&&Number.isInteger(retirement?.elapsedMs)&&retirement.elapsedMs>=0&&retirement.elapsedMs<=60000?{outcome:retirement.outcome,elapsedMs:retirement.elapsedMs}:null;
 return {retirement:retirementFact,code:typeof error.code==="number"?error.code:null,signal:error.signal??null,killed:error.killed??false,
  cliErrorCode:codes.has(data?.error?.code)?data.error.code:null,category};
}
