const errorCodes=new Set(["EACCES","EPERM","ENOENT","ENOEXEC","ENOMEM","EAGAIN","EMFILE","ENFILE"]);
export function classifySpawnError(code){return errorCodes.has(code)?code:"OTHER";}
export function classifyChromiumStderr(text){
 const checks=[["sandbox-unavailable",/no usable sandbox|sandbox.{0,100}(?:not supported|failed)/i],
  ["apparmor",/apparmor/i],["loader",/error while loading shared libraries|cannot open shared object file|ld-linux/i],
  ["namespace-permission",/failed to.{0,100}namespace|operation not permitted|permission denied/i],
  ["zygote-fork",/zygote.{0,100}fork|fork.{0,100}zygote/i]];
 const result=checks.filter(([,pattern])=>pattern.test(text)).map(([name])=>name);
 return result.length?result:text.length?["other"]:[];
}
export function createBoundedStderr(limit=65536){
 let data=Buffer.alloc(0),truncated=false;
 return {append(chunk){const bytes=Buffer.from(chunk),remaining=limit-data.length;
  if(bytes.length>remaining)truncated=true;
  if(remaining>0)data=Buffer.concat([data,bytes.subarray(0,remaining)]);
 },result(){return {categories:classifyChromiumStderr(data.toString("utf8")),bytes:data.length,truncated};}};
}
