// Dedicated hosted runner only. No global input, simulator, or existing app attachment.
import {spawn,execFileSync} from "node:child_process";
import {mkdir,writeFile,readFile,realpath} from "node:fs/promises";
import {createReadStream} from "node:fs";
import {createHash} from "node:crypto";
import path from "node:path";
import {Client,Failure,requireTrue,listeners,waitFor,delay} from "../../tests/macos/runtime-client.mjs";
import {startFixture} from "../../tests/macos/runtime-fixture.mjs";
import {publicCLI,inference} from "../../tests/macos/runtime-interfaces.mjs";
import {runEngine} from "../../tests/macos/runtime-cases.mjs";
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
const root=await realpath("."),app=await realpath("apps/macos/.build/Build/Products/Debug/Kelpie.app");
requireTrue(app.startsWith(root+"/apps/macos/.build/"),"CANDIDATE_PATH");
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
let appLogBytes=0,fixture,client;
const child=spawn(executable,["--port","28420"],{detached:true,stdio:["ignore","pipe","pipe"]});
let childExited=false;child.once("exit",()=>{childExited=true;});
for(const stream of [child.stdout,child.stderr])stream.on("data",bytes=>{appLogBytes+=bytes.length;});
try{
 await new Promise((resolve,reject)=>{child.once("spawn",resolve);child.once("error",()=>reject(new Failure("APP_SPAWN")));});
 report.pid=child.pid;client=new Client(child.pid,out);
 await waitFor(()=>client.ready(),30000);
 client.token=await client.pair("Hosted Mac acceptance");
 fixture=await startFixture();
 await runEngine(client,fixture,"webkit",report);
 report.publicCLI=await publicCLI(client,fixture,privateDir);
 report.inference=await inference(client,privateDir);
 await runEngine(client,fixture,"chromium",report);
 report.corpusPassed=true;
}catch(error){report.failure=error.code??"HOSTED_RUNTIME_FAILED";process.exitCode=1;}
finally{
 await fixture?.close();
 // The detached process group belongs exclusively to this exact child.
 try{const pgid=Number(execFileSync("/bin/ps",["-o","pgid=","-p",String(child.pid)],{encoding:"utf8"}).trim());
  if(pgid===child.pid)process.kill(-pgid,"SIGTERM");else report.cleanup="OWNED_PROCESS_GROUP_MISMATCH";
 }catch{report.cleanup="OWNED_CHILD_ALREADY_EXITED";}
 const end=Date.now()+10000;
 while(Date.now()<end&&(!childExited||listeners(28420).includes(child.pid)||listeners(8421).includes(child.pid)))await delay(100);
 if(!childExited||listeners(28420).includes(child.pid)||listeners(8421).includes(child.pid)){report.cleanup="OWNED_CHILD_TEARDOWN_TIMEOUT";report.corpusPassed=false;process.exitCode=1;}
 else {report.ownedListenersReleased=true;report.ownedChildExited=true;}
 // A failed teardown must not leave the test driver waiting forever on inherited pipes.
 child.stdout.destroy();child.stderr.destroy();child.unref();
 // Raw app logs, pairing grants, private model/recipes and token stores are never artifacts.
 report.appLogBytes=appLogBytes;
 await writeFile(path.join(out,"report.json"),JSON.stringify(report,null,2));
}
