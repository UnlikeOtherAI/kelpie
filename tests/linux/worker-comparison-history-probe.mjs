// Controlled fixture-only lifecycle facts; no URLs or page values leave memory.
export function createHistoryProbe(){
 const events=[];let invalid=false;
 return {
  script(page){
   if(page!=="root"&&page!=="next")throw Error("PAGE_INVALID");
   const marker=page==="root"?"r":"n";
   return `<script>addEventListener("pageshow",e=>{navigator.sendBeacon("/__kelpie_history", "${marker}"+(e.persisted?"1":"0"));});</script>`;
  },
  record(body){
   if(typeof body!=="string"||!["r0","r1","n0","n1"].includes(body)||events.length>=64){invalid=true;return;}
   events.push(body);
  },
  mark(){return events.length;},
  result(mark){
   if(invalid||!Number.isInteger(mark)||mark<0||mark>events.length)return {status:"insufficient"};
   const before=events.slice(0,mark),after=events.slice(mark),root=after.filter(x=>x[0]==="r");
   const anchors={root:before.includes("r0"),next:before.some(x=>x[0]==="n")},postRootEvents=root.length;
   if(!anchors.root||!anchors.next)return {status:"insufficient",anchors,postRootEvents};
   if(root.length===0)return {status:"not-observed",anchors,postRootEvents};
   if(root.length!==1)return {status:"ambiguous",anchors,postRootEvents};
   return {status:root[0]==="r1"?"restored-from-bfcache":"normal-pageshow",anchors,postRootEvents};
  },
 };
}
