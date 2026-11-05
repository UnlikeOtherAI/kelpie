import assert from "node:assert/strict";

// The pre-release brand must not be treated as evidence for a replacement target.
export async function runBrandReleaseCases({check,navigate,api,workflow,tabId}) {
  await check("brand proof never permits captured input navigation", async () => {
    await navigate();
    const setup="(()=>{document.body.innerHTML='<input id=brand-input type=text>';" +
      "document.querySelector('#brand-input').oninput=()=>{location.href='/next'};return true})()";
    assert.equal((await api("evaluate",{tabId,expression:setup})).success,true);
    const result=await api("play-script",{...workflow([{action:"type",target:{selector:"#brand-input"},text:"safe"}]),
      capture:{formats:["screenshots"],maxWidth:640}});
    assert.equal(result.success,false,JSON.stringify(result));
    assert.equal(result.mayHaveCompleted,true);
    assert.deepEqual(result.artifacts,[]);
  });
  await check("brand proof does not consume a late release acknowledgement", async () => {
    await navigate();
    const setup="(()=>{document.body.innerHTML='<button id=slow-release>Slow release</button>';window.__slowClicks=0;" +
      "const e=document.querySelector('#slow-release');e.onmouseup=()=>{const end=performance.now()+11000;while(performance.now()<end){}};" +
      "e.onclick=()=>window.__slowClicks++;return true})()";
    assert.equal((await api("evaluate",{tabId,expression:setup})).success,true);
    const result=await api("play-script",{...workflow([{action:"click",target:{selector:"#slow-release"}}]),
      capture:{formats:["screenshots"],maxWidth:640,maxDurationMs:30000}});
    assert.equal(result.success,false);
    assert.equal(result.mayHaveCompleted,true);
    assert.deepEqual(result.artifacts,[]);
    let observed;
    const end=Date.now()+15000;
    while(Date.now()<end){
      observed=await api("evaluate",{tabId,expression:"window.__slowClicks"});
      if(observed.success)break;
      await new Promise(resolve=>setTimeout(resolve,100));
    }
    assert.equal(observed?.success,true,"late operation did not retire");
    assert.ok(observed.result<=1,"late release was replayed");
    assert.equal((await api("play-script",workflow([{action:"wait",ms:0}]))).success,true);
    return {code:result.error?.code,clicks:observed.result};
  });
  await check("brand proof does not retarget after pointerup replacement", async () => {
    await navigate();
    const setup = "(()=>{document.body.innerHTML='<button id=old style=\\\"position:absolute;left:80px;top:80px;width:120px;height:60px\\\">Old</button>';" +
      "window.__releaseEvents=[];for(const type of ['pointerup','mouseup','click'])" +
      "document.addEventListener(type,e=>window.__releaseEvents.push({type,id:e.target.id,trusted:e.isTrusted}),true);" +
      "document.querySelector('#old').addEventListener('pointerup',e=>{const replacement=document.createElement('input');" +
      "replacement.id='replacement-password';replacement.type='password';replacement.style.cssText=e.currentTarget.style.cssText;" +
      "e.currentTarget.replaceWith(replacement)});return true})()";
    assert.equal((await api("evaluate",{tabId,expression:setup})).success,true);
    const result=await api("play-script",{...workflow([{action:"click",target:{selector:"#old"}}]),
      capture:{formats:["screenshots"],maxWidth:640}});
    const events=(await api("evaluate",{tabId,expression:"window.__releaseEvents"})).result;
    assert.ok(events.some(event=>event.type==="pointerup" && event.id==="old" && event.trusted));
    assert.ok(!events.some(event=>event.id==="replacement-password" && event.trusted),
      "Trusted release event reached a replacement password target: "+JSON.stringify(events));
    // Same-realm post-ACK classification must not discard ordinary screenshots.
    assert.equal(result.success,true,JSON.stringify(result));
    assert.ok(result.artifacts.some(item=>item.mimeType==="image/png" && !item.partial));
    return {events};
  });
}
