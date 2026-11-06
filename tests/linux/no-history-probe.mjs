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
  result(){return {status:!invalid&&count===1&&one?'one-entry':'insufficient'};},
 };
}
