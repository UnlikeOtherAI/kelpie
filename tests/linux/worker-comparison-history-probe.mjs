// Controlled fixture-only lifecycle facts; no URLs or page values leave memory.
export function createHistoryProbe(){
 const events=[];let invalid=false;
 return {
  script(page){
   if(page!=="root"&&page!=="next")throw Error("PAGE_INVALID");
   const marker=page==="root"?"r":"n";
   return `<script>addEventListener("pageshow",e=>{navigator.sendBeacon("/__kelpie_history", "${marker}"+(e.persisted?"1":"0"));});addEventListener("hashchange",()=>{if(location.hash==="#one"||location.hash==="#two")navigator.sendBeacon("/__kelpie_history",location.hash==="#one"?"h1":"h2");});</script>`;
  },
  record(body){
   if(typeof body!=="string"||!["r0","r1","n0","n1","h1","h2"].includes(body)||events.length>=64){invalid=true;return;}
   events.push(body);
  },
  mark(){return events.length;},
  hashResult(mark,expected){
   if(invalid||!Number.isInteger(mark)||mark<0||mark>events.length||!["h1","h2"].includes(expected))return {status:"insufficient"};
   const before=events.slice(0,mark),after=events.slice(mark),hash=after.filter(x=>x==="h1"||x==="h2");
   if(!before.includes("h1")||!before.includes("h2"))return {status:"insufficient"};
   return {status:hash.length===1&&hash[0]===expected?"observed":"insufficient"};
  },
  result(mark,page="root"){
   if(invalid||!Number.isInteger(mark)||mark<0||mark>events.length||!["root","next"].includes(page))return {status:"insufficient"};
   const before=events.slice(0,mark),after=events.slice(mark),target=after.filter(x=>x[0]===(page==="root"?"r":"n"));
   const anchors={root:before.includes("r0"),next:before.some(x=>x[0]==="n")};
   const counts=page==="root"?{postRootEvents:target.length}:{postNextEvents:target.length};
   if(!anchors.root||!anchors.next)return {status:"insufficient",anchors,...counts};
   if(target.length===0)return {status:"not-observed",anchors,...counts};
   if(target.length!==1)return {status:"ambiguous",anchors,...counts};
   return {status:target[0][1]==="1"?"restored-from-bfcache":"normal-pageshow",anchors,...counts};
  },
 };
}
