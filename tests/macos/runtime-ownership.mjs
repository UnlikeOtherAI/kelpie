// Missing is a normal startup state; a different or ambiguous owner is never ready.
export function listenerState(owners,pid){
 if(owners.length===0)return "missing";
 return owners.length===1&&owners[0]===pid?"owned":"foreign";
}
