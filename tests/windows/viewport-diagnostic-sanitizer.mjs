const fences=new Set(["initial-size","inter-frame","before-after","after-read-failed"]);
const metricKeys=new Set(["width","height","visual_offsetLeft","visual_offsetTop","visual_width","visual_height","visual_scale"]);
export function parseViewportDiagnostic(line) {
 const prefix="KELPIE_CAPTURE_VIEWPORT_DIAGNOSTIC ";
 if(!line.startsWith(prefix))return null;
 try{
  const value=JSON.parse(line.slice(prefix.length));
  if(!fences.has(value.fence))return null;
  const clean={fence:value.fence};
  for(const field of ["before","after"]){
   clean[field]={};const input=value[field];
   if(!input||typeof input!=="object"||Array.isArray(input))return null;
   for(const [key,number] of Object.entries(input)){
    if(!metricKeys.has(key)||!Number.isFinite(number)||Math.abs(number)>1000000)return null;
    clean[field][key]=number;
   }
  }
  return clean;
 }catch{return null;}
}
