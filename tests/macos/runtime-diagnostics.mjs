const causeCodes=new Set(["ECONNREFUSED","ECONNRESET","EPIPE","ETIMEDOUT","EHOSTUNREACH","ENETUNREACH","UND_ERR_SOCKET","UND_ERR_CONNECT_TIMEOUT","UND_ERR_HEADERS_TIMEOUT","UND_ERR_BODY_TIMEOUT","ABORT_ERR"]);
const sourceFiles=new Set(["runtime-client.mjs","runtime-cases.mjs","runtime-media.mjs","runtime-g08.mjs","macos-workflow-acceptance.mjs"]);
const issueCodes=new Set(["invalid_type","invalid_value","invalid_format","too_small","too_big","unrecognized_keys","invalid_union","custom","invalid_string","invalid_enum_value"]);
const fields=new Set(["id","runId","artifactId","mimeType","byteLength","sha256","partial","width","height","durationMs","frameCount","droppedFrames","viewport","documentId","actionIndex","success","data","offset","nextOffset","eof"]);
const kinds=new Set(["image/png","image/gif","video/mp4"]);
const readErrors=new Set(["ARTIFACT_NOT_FOUND","ARTIFACT_NOT_READY","ARTIFACT_READ_FAILED","INVALID_PARAM",
 "UNAUTHORIZED","NOT_FOUND","BUSY","SCRIPT_UNAVAILABLE","RECORDING_IN_PROGRESS","RUN_NOT_FOUND"]);
const kind=value=>value===null?"null":Array.isArray(value)?"array":typeof value;
const finite=value=>typeof value==="number"&&Number.isFinite(value)&&value>=0&&value<=1_000_000_000?value:null;
export function errorFacts(error){
 const names=new Set(["TypeError","SyntaxError","ZodError","Error","AbortError","TimeoutError"]);
 const result={type:names.has(error?.name)?error.name:"OTHER"};
 let current=error;
 for(let depth=0;current&&depth<5;depth++,current=current.cause){
  if(causeCodes.has(current.code)){result.causeCode=current.code;break;}
 }
 const locations=[];
 for(const line of String(error?.stack??"").split("\n").slice(0,32)){
  const match=line.match(/(?:\/|\\)([A-Za-z0-9-]+\.mjs):(\d{1,6}):\d{1,6}/);
  if(match&&sourceFiles.has(match[1]))locations.push({file:match[1],line:Number(match[2])});
  if(locations.length===5)break;
 }
 if(locations.length)result.locations=locations;
 if(error?.name==="ZodError"&&Array.isArray(error.issues)){
  result.issues=error.issues.slice(0,16).map(issue=>({
   code:issueCodes.has(issue.code)?issue.code:"OTHER",
   path:Array.isArray(issue.path)?issue.path.slice(0,8).map(part=>typeof part==="number"?"[]":fields.has(part)?part:"OTHER"):[]
  }));
 }
 return result;
}
export function playFacts(value){
 if(!value||typeof value!=="object"||Array.isArray(value))return {type:kind(value)};
 const artifacts=Array.isArray(value.artifacts)?value.artifacts:null;
 const states=new Set(["idle","running","finalizing","completed","failed","aborted"]);
 const field=value.outputs?.catalogue?.fields?.[0];
 const statuses=new Set(["ok","missing","ambiguous","incomplete"]);
 return {type:"object",successType:kind(value.success),success:value.success===true?true:value.success===false?false:null,
  state:states.has(value.state)?value.state:"OTHER",hasRunId:typeof value.runId==="string",outputsType:kind(value.outputs),
  extraction:{catalogueType:kind(value.outputs?.catalogue),fieldsType:kind(value.outputs?.catalogue?.fields),
   fieldType:kind(field),status:statuses.has(field?.status)?field.status:"OTHER",valuesType:kind(field?.values),
   valueCount:Array.isArray(field?.values)?field.values.length:null,provenanceType:kind(field?.provenance),
   selectorType:kind(field?.provenance?.selector)},
  artifactsType:kind(value.artifacts),artifactCount:artifacts?.length??null,
  artifacts:artifacts?.slice(0,8).map(artifactFacts)??[]};
}
export function artifactFacts(value){
 if(!value||typeof value!=="object"||Array.isArray(value))return {type:kind(value)};
 const types={};for(const key of fields)if(Object.hasOwn(value,key))types[key]=kind(value[key]);
 return {type:"object",types,success:value.success===true?true:value.success===false?false:null,
  errorCode:readErrors.has(value.error?.code)?value.error.code:"OTHER",mimeType:kinds.has(value.mimeType)?value.mimeType:"OTHER",
  byteLength:finite(value.byteLength),width:finite(value.width),height:finite(value.height),
  frameCount:finite(value.frameCount),droppedFrames:finite(value.droppedFrames),
  unknownKeyCount:Object.keys(value).filter(key=>!fields.has(key)).length};
}
export function toolEnvelopeFacts(value){
 const content=value?.result?.content;
 return {type:kind(value),hasError:!!value?.error,resultType:kind(value?.result),contentType:kind(content),
  contentCount:Array.isArray(content)?content.length:null,textCount:Array.isArray(content)?content.filter(item=>item?.type==="text"&&typeof item.text==="string").length:null};
}
// Structural and fixed-code CLI facts only: stdout/stderr may contain private values.
export function cliExitFacts(exitCode,stdout,stderr){
 const allowed=new Set(["DEVICE_NOT_FOUND","LOCAL_BROWSER_UNAVAILABLE","NO_DEVICES","MULTIPLE_DEVICES",
  "UNAUTHORIZED","TIMEOUT","PAIR_ERROR","PAIR_DENIED","PAIR_TIMEOUT","SCRIPT_ABORTED","TARGET_NOT_FOUND",
  "TAB_NOT_FOUND","TAB_NOT_ACTIVE","TAB_NOT_VISIBLE","NAVIGATION_FAILED","RECORDING_IN_PROGRESS",
  "ARTIFACT_NOT_FOUND","ARTIFACT_NOT_READY","ARTIFACT_READ_FAILED"]);
 let parsed;try{parsed=JSON.parse(stdout);}catch{}
 const rawCode=parsed?.error?.code??parsed?.result?.error?.code;
 return {exitCode:Number.isInteger(exitCode)?exitCode:null,stdoutJson:!!parsed,stderrPresent:stderr.length>0,
  errorCode:allowed.has(rawCode)?rawCode:"OTHER"};
}
