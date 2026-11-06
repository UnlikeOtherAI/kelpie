// Controlled preflight observation; the random binding is never reported.
export function createNoHistoryProbe(binding) {
 if (typeof binding !== 'string' || !/^[a-f0-9]{64}$/.test(binding)) throw Error('INVALID_BINDING');
 let count=0, one=false, invalid=false;
 return {
  script(){return `<script>addEventListener("pageshow",()=>navigator.sendBeacon("/__kelpie_no_history","${binding}:"+(history.length===1?"one":"other")));</script>`;},
  record(value){
   count=Math.min(count+1,2);
   if (value===binding+':one') one=true;
   else if (value!==binding+':other') invalid=true;
  },
  result(){
   const beacon=invalid?'mismatch':count===0?'missing':count>1?'duplicate':one?'one':'other';
   return {status:beacon==='one'?'one-entry':'insufficient',beacon};
  },
 };
}
