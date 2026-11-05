// Dedicated hosted runner only. No global input, simulator, or existing app attachment.
import {spawn,execFileSync} from "node:child_process";
import {mkdir,writeFile,readFile,realpath} from "node:fs/promises";
import {StringDecoder} from "node:string_decoder";
import {startupSignal,navigationSignal,editFocusSignal,viewportSignal,workflowVisibilitySignal,serverLifecycleSignal,listenerTransitionSignal} from "../../tests/macos/runtime-ownership.mjs";
import {createReadStream} from "node:fs";
import {createHash} from "node:crypto";
import path from "node:path";
import {Client,Failure,requireTrue,listeners,waitFor,delay} from "../../tests/macos/runtime-client.mjs";
import {bootstrapDiagnostics} from "../../tests/macos/runtime-bootstrap.mjs";
import {startFixture} from "../../tests/macos/runtime-fixture.mjs";
import {publicCLI,inference} from "../../tests/macos/runtime-interfaces.mjs";
import {runEngine} from "../../tests/macos/runtime-cases.mjs";
import {runIndependentPhase} from "../../tests/macos/runtime-orchestration.mjs";
requireTrue(process.env.GITHUB_ACTIONS==="true"&&process.env.RUNNER_OS==="macOS","DEDICATED_HOSTED_RUNNER_REQUIRED");
if(process.argv[2]==="--preparation"){
 const state=process.argv[3],exitCode=Number(process.argv[4]);
 requireTrue(["started","ready","failed"].includes(state)&&Number.isInteger(exitCode)&&exitCode>=0&&exitCode<=255,"PREPARATION_ARGUMENTS");
 const source=execFileSync("git",["rev-parse","HEAD"],{encoding:"utf8"}).trim();
 requireTrue(source===process.env.GITHUB_SHA,"SOURCE_REVISION_MISMATCH");
 const directory=path.resolve(".cache/macos-runtime/evidence");await mkdir(directory,{recursive:true});
 await writeFile(path.join(directory,"preparation.json"),JSON.stringify({version:1,source,phase:"runtime-preparation",state,exitCode,utc:new Date().toISOString(),release:false},null,2));
 process.exit(0);
}
requireTrue(process.env.KELPIE_HOSTED_RUNTIME==="1","DEDICATED_HOSTED_RUNNER_REQUIRED");
const root=await realpath("."),app=await realpath("apps/macos/.build-runtime/Build/Products/Debug/Kelpie.app");
requireTrue(app.startsWith(root+"/apps/macos/.build-runtime/"),"CANDIDATE_PATH");
const out=path.join(root,".cache/macos-runtime/evidence"),privateDir=path.join(root,".cache/macos-runtime/private");
await mkdir(out,{recursive:true});await mkdir(privateDir,{recursive:true,mode:0o700});
requireTrue(listeners(28420).length===0&&listeners(8421).length===0,"OCCUPIED_LISTENER");
const executable=path.join(app,"Contents/MacOS/Kelpie");
const hash=async file=>{const digest=createHash("sha256");for await(const bytes of createReadStream(file))digest.update(bytes);return digest.digest("hex");};
const source=execFileSync("git",["rev-parse","HEAD"],{encoding:"utf8"}).trim();
requireTrue(source===process.env.GITHUB_SHA,"SOURCE_REVISION_MISMATCH");
execFileSync("git",["diff","--quiet","HEAD","--","apps/macos","native","packages/shared","tests/macos","scripts/testing"]);
const report={source,platform:process.platform,
 cefFrameworkHash:await hash(path.join(app,"Contents/Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework")),
 cefVersion:(await readFile("apps/macos/Frameworks/cef_include/cef_version.h","utf8")).match(/#define CEF_VERSION "([^"\n]+)"/)?.[1],
 executableHash:await hash(executable),debugLibraryHash:await hash(path.join(app,"Contents/MacOS/Kelpie.debug.dylib")),
 engines:[],gaps:[],corpusPassed:false,completePlatformAcceptance:false,release:false,signing:"ad-hoc hosted test only"};
let appLogBytes=0,fixture,client,phase="launch",childExit=null,stopping=false;const started=Date.now();
const startupSignals=[],navigationSignals=[],editFocusSignals=[],viewportSignals=[],workflowVisibilitySignals=[],serverLifecycleSignals=[],listenerTransitionSignals=[];
const child=spawn(executable,["--port","28420"],{detached:true,stdio:["ignore","pipe","pipe"],env:{...process.env,NSUnbufferedIO:"YES"}});
let childExited=false;child.once("exit",(code,signal)=>{childExited=true;childExit={code,signal,during:stopping?"cleanup":"runtime"};});
for(const stream of [child.stdout,child.stderr]){
 const decoder=new StringDecoder("utf8");let text="";
 stream.on("data",bytes=>{
  appLogBytes+=bytes.length;
  text=(text+decoder.write(bytes)).slice(-16384);let index;
  while((index=text.indexOf("\n"))>=0){const line=text.slice(0,index).trim();text=text.slice(index+1);
   if(["launch","listeners"].includes(phase)){const signal=startupSignal(line);if(signal&&!startupSignals.includes(signal))startupSignals.push(signal);}
   const navigation=navigationSignal(line);if(navigation&&navigationSignals.length<32)navigationSignals.push(navigation);
   const focus=editFocusSignal(line);if(focus&&editFocusSignals.length<32)editFocusSignals.push(focus);
   const viewport=viewportSignal(line);if(viewport&&viewportSignals.length<32)viewportSignals.push(viewport);
   const visibility=workflowVisibilitySignal(line);if(visibility&&workflowVisibilitySignals.length<32)workflowVisibilitySignals.push(visibility);
   const server=serverLifecycleSignal(line);if(server&&serverLifecycleSignals.length<32)serverLifecycleSignals.push({phase,...server});
   const transition=listenerTransitionSignal(line);if(transition&&listenerTransitionSignals.length<32)listenerTransitionSignals.push({phase,...transition});
  }
 });
}
try{
 await new Promise((resolve,reject)=>{child.once("spawn",resolve);child.once("error",()=>reject(new Failure("APP_SPAWN")));});
 report.pid=child.pid;client=new Client(child.pid,out,executable);phase="listeners";
 await waitFor(()=>client.ready(),30000);
 phase="pairing";client.token=await client.pair("Hosted Mac acceptance");
 fixture=await startFixture();
 const failures=[];
 async function independent(name,operation){
  phase=name;
  await runIndependentPhase(name,operation,failures,error=>({
   childExitAtFailure:childExit,childAliveAtFailure:!childExited&&child.exitCode===null&&child.signalCode===null,
   ...(["cli","cef-cli"].includes(name)?{cliStage:client.cliStage,cliFacts:error.cliFacts}:{}),
   ...(error.code==="LISTENER_IDENTITY"?{listenerFailure:client.listenerFailure}:{}),
  }));
 }
 await independent("webkit",()=>runEngine(client,fixture,"webkit",report));
 await independent("cli",async()=>{report.publicCLI=await publicCLI(client,fixture,privateDir);});
 await independent("inference",async()=>{report.inference=await inference(client,privateDir);});
 await independent("chromium",async()=>{
  // Never reset a failed workflow: wait until its own playback and listener ownership are settled.
  await waitFor(async()=>client.ready()&&(await client.api("get-script-status")).playing===false,30000);
  await runEngine(client,fixture,"chromium",report);
 });
 await independent("cef-cli",async()=>{
  const selected=report.engines.find(item=>item.engine==="chromium")?.checks.some(item=>item.name==="native-renderer-control"&&item.passed);
  requireTrue(selected,"CLI_CEF_RENDERER_UNAVAILABLE");
  await waitFor(async()=>client.ready()&&(await client.api("get-script-status")).playing===false,30000);
  report.cefCLI=await publicCLI(client,fixture,privateDir,"chromium");
 });
 if(failures.length){
  report.phaseFailures=failures;
  phase=failures[0].phase;
  throw new Failure(failures[0].code);
 }
 report.corpusPassed=true;
}catch(error){
 report.failure=error.code??"HOSTED_RUNTIME_FAILED";report.phaseAtFailure=phase;
 if(report.phaseFailures?.length){
  report.childExitAtFailure=report.phaseFailures[0].childExitAtFailure;
  report.childAliveAtFailure=report.phaseFailures[0].childAliveAtFailure;
 }else{
  report.childExitAtFailure=childExit;
  report.childAliveAtFailure=!childExited&&child.exitCode===null&&child.signalCode===null;
 }
 process.exitCode=1;
 if(["launch","listeners"].includes(phase)){
  try{report.bootstrap=await bootstrapDiagnostics({pid:child.pid,executable,started,privateDir});}
  catch{report.bootstrapDiagnosticError="BOOTSTRAP_DIAGNOSTICS_FAILED";}
 }
}
finally{
 await fixture?.close();
 stopping=true;
 if(Number.isSafeInteger(child.pid)&&child.pid>1){
  // The detached process group belongs exclusively to this exact child.
  if(!childExited){
   try{const pgid=Number(execFileSync("/bin/ps",["-o","pgid=","-p",String(child.pid)],{encoding:"utf8"}).trim());
    if(pgid===child.pid)process.kill(-pgid,"SIGTERM");else report.cleanup="OWNED_PROCESS_GROUP_MISMATCH";
   }catch{report.cleanup="OWNED_CHILD_ALREADY_EXITED";}
  }
  const end=Date.now()+10000;
  while(Date.now()<end&&(!childExited||listeners(28420).includes(child.pid)||listeners(8421).includes(child.pid)))await delay(100);
  if(!childExited||listeners(28420).includes(child.pid)||listeners(8421).includes(child.pid)){report.cleanup="OWNED_CHILD_TEARDOWN_TIMEOUT";report.corpusPassed=false;process.exitCode=1;}
  else {report.ownedListenersReleased=true;report.ownedChildExited=true;}
 }else report.cleanup="NO_CHILD_SPAWNED";
 child.stdout?.destroy();child.stderr?.destroy();child.unref();
 report.childExit=childExit;report.readiness=client?.readiness??[];
 // Raw app logs, pairing grants, private model/recipes and token stores are never artifacts.
 report.appLogBytes=appLogBytes;report.startupSignals=startupSignals;report.navigationSignals=navigationSignals;report.editFocusSignals=editFocusSignals;report.viewportSignals=viewportSignals;report.workflowVisibilitySignals=workflowVisibilitySignals;report.serverLifecycleSignals=serverLifecycleSignals;report.listenerTransitionSignals=listenerTransitionSignals;
 report.artifacts=client?.artifacts??[];
 await writeFile(path.join(out,"report.json"),JSON.stringify(report,null,2));
}
