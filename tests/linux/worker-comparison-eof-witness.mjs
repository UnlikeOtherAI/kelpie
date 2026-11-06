// Bounded in-memory classifications from one original CDP connection.
// Never serialize or expose request, context, or target identifiers.
export function createEofWitness(){
 let stage="create",pending=null,context=null,target=null,bad=null,eof=false,count=0;
 const fail=reason=>{bad??=reason;};
 const validId=x=>typeof x==="string"&&x.length>0&&x.length<=512;
 const validRequest=x=>Number.isSafeInteger(x)&&x>0;
 return {
  request(value){
   if(bad)return;
   if(++count>4096){fail("MESSAGE_LIMIT");return;}
   const method=value?.method;
   if(!["Target.createBrowserContext","Target.createTarget","Target.disposeBrowserContext"].includes(method))return;
   if(Object.hasOwn(value,"sessionId")||!validRequest(value.id)||pending){fail("REQUEST_INVALID");return;}
   if(method==="Target.createBrowserContext"&&stage==="create"&&!eof)pending={id:value.id,kind:"create"};
   else if(method==="Target.createTarget"&&stage==="target"&&!eof&&value.params?.browserContextId===context)pending={id:value.id,kind:"target"};
   else if(method==="Target.disposeBrowserContext"&&stage==="dispose"&&eof&&value.params?.browserContextId===context)pending={id:value.id,kind:"dispose"};
   else fail("REQUEST_ORDER_OR_CONTEXT");
  },
  response(value){
   if(bad)return;
   if(++count>4096){fail("MESSAGE_LIMIT");return;}
   if(!pending||value?.id!==pending.id)return;
   if(Object.hasOwn(value,"sessionId")||Object.hasOwn(value,"error")||!value.result||typeof value.result!=="object"||Array.isArray(value.result)){
    fail("RESPONSE_ERROR");return;
   }
   if(pending.kind==="create"){
    if(!validId(value.result.browserContextId)){fail("CONTEXT_INVALID");return;}
    context=value.result.browserContextId;stage="target";
   }else if(pending.kind==="target"){
    if(!validId(value.result.targetId)){fail("TARGET_INVALID");return;}
    target=value.result.targetId;stage="dispose";
   }else stage="done";
   pending=null;
  },
  markEof(){if(bad||eof||pending||stage!=="dispose"||!context||!target){fail("EOF_NOT_READY");return false;}eof=true;return true;},
  fail(reason){fail(reason);},
  result(){return {ok:!bad&&eof&&stage==="done"&&!pending,category:bad??(stage==="done"?"complete":"incomplete"),eof,stage};},
 };
}
