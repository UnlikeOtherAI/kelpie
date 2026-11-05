import assert from "node:assert/strict";
// The fixture may use an opaque about:blank origin. Its identity is supplied
// by the test process rather than relying on a secure-context-only page API.
export function nativeWindowFixtureExpression(documentId){
 assert.match(documentId,/^[a-f0-9-]{36}$/);
 return "(()=>{document.body.innerHTML='<button id=\"native-capture-target\" style=\"position:fixed;left:150px;top:150px;width:160px;height:60px\">Capture target</button>';document.body.style.cssText='margin:0;height:100vh;background:white';window.__nativeCaptureDocument="+JSON.stringify(documentId)+";const b=document.getElementById('native-capture-target');b.onclick=e=>{window.__nativeCaptureClick={trusted:e.isTrusted,x:e.clientX,y:e.clientY,rect:b.getBoundingClientRect().toJSON(),documentId:window.__nativeCaptureDocument,dpr:devicePixelRatio,visualScale:visualViewport.scale};};const r=b.getBoundingClientRect();return{target:{x:r.left+r.width/2,y:r.top+r.height/2},viewport:{width:innerWidth,height:innerHeight,dpr:devicePixelRatio,visualScale:visualViewport.scale},documentId:window.__nativeCaptureDocument};})()";
}
