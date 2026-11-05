// Preserve the first failure while allowing independent, settled renderer phases to run.
export async function runIndependentPhase(name,operation,failures,childState){
 try{await operation();}
 catch(error){
  const code=typeof error.code==="string"&&/^[A-Z0-9_]{1,64}$/.test(error.code)?error.code:"HOSTED_RUNTIME_FAILED";
  failures.push({phase:name,code,...childState()});
 }
}
