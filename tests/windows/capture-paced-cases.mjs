import assert from "node:assert/strict";

export async function runPacedCases({check,navigate,api,workflow,download,click,tabId,fixture}) {
  await check("paced fill emits trusted Unicode scalars with intervals", async () => {
    await navigate();
    const setup="(()=>{document.body.innerHTML='<input id=paced value=old style=display:block>';window.__paced=[];" +
      "document.querySelector('#paced').oninput=e=>window.__paced.push({data:e.data,time:performance.now(),trusted:e.isTrusted});" +
      "window.__geometry=[];const record=kind=>{const e=document.querySelector('#paced'),r=e.getBoundingClientRect(),v=visualViewport;if(window.__geometry.length<160)window.__geometry.push({kind,time:performance.now(),rect:[r.x,r.y,r.width,r.height],scroll:[scrollX,scrollY],viewport:[innerWidth,innerHeight,v.width,v.height,v.offsetLeft,v.offsetTop,v.scale]})};" +
      "const e=document.querySelector('#paced');e.addEventListener('focus',()=>record('focus'));e.addEventListener('input',()=>record('input'));record('setup');window.__geometryTimer=setInterval(()=>record('sample'),25);return true})()";
    assert.equal((await api("evaluate",{tabId,expression:setup})).success,true);
    const result=await api("play-script",{...workflow([{action:"fill",target:{selector:"#paced"},text:"A😀B",typingDelayMs:120}]),
      capture:{formats:["gif","screenshots"],fps:15,maxWidth:640,maxDurationMs:12000,maxBytes:8388608}});
    const geometry=(await api("evaluate",{tabId,expression:"(clearInterval(window.__geometryTimer),window.__geometry)"})).result;
    if(!result.success)throw new Error(JSON.stringify({code:result.error?.code,mayHaveCompleted:result.mayHaveCompleted===true,actionsExecuted:result.actionsExecuted,artifactCount:result.artifacts?.length,geometry}));
    const events=(await api("evaluate",{tabId,expression:"window.__paced"})).result;
    const inserted=events.filter(event=>event.data!==null);
    assert.deepEqual(inserted.map(event=>event.data),["A","😀","B"]);
    assert.ok(inserted.every(event=>event.trusted===true));
    assert.ok(inserted[1].time-inserted[0].time>=90 && inserted[2].time-inserted[1].time>=90);
    assert.equal((await api("evaluate",{tabId,expression:"document.querySelector('#paced').value"})).result,"A😀B");
    assert.ok(result.artifacts.some(item=>item.mimeType==="image/gif"));
    assert.ok(result.artifacts.some(item=>item.mimeType==="image/png"));
    await download(result);
    return {events:events.length,intervals:[inserted[1].time-inserted[0].time,inserted[2].time-inserted[1].time],geometry};
  });
  await check("paced type appends Unicode and empty fill clears once", async () => {
    await navigate();
    const setup="(()=>{document.body.innerHTML='<input id=append value=X><input id=clear value=old>';window.__append=[];window.__clear=[];" +
      "document.querySelector('#append').oninput=e=>window.__append.push({data:e.data,time:performance.now()});" +
      "document.querySelector('#clear').oninput=e=>window.__clear.push(e.data);return true})()";
    assert.equal((await api("evaluate",{tabId,expression:setup})).success,true);
    const result=await api("play-script",workflow([
      {action:"type",target:{selector:"#append"},text:"é😀",typingDelayMs:120},
      {action:"fill",target:{selector:"#clear"},text:"",typingDelayMs:1000}]));
    assert.equal(result.success,true,JSON.stringify(result));
    const observed=(await api("evaluate",{tabId,expression:"({append:document.querySelector('#append').value,clear:document.querySelector('#clear').value,events:window.__append,clears:window.__clear})"})).result;
    assert.equal(observed.append,"Xé😀");assert.equal(observed.clear,"");
    assert.deepEqual(observed.events.map(event=>event.data),["é","😀"]);
    assert.ok(observed.events[1].time-observed.events[0].time>=90);
    assert.equal(observed.clears.length,1);
  });
  await check("ordinary paced text remains available in named output", async () => {
    await navigate();
    const setup="(()=>{document.title='ordinary-visible-42';document.body.innerHTML='<input id=ordinary-paced>';return true})()";
    assert.equal((await api("evaluate",{tabId,expression:setup})).success,true);
    const result=await api("play-script",workflow([
      {action:"type",target:{selector:"#ordinary-paced"},text:"ordinary-visible-42",typingDelayMs:2},
      {action:"output",name:"title",source:"title"}]));
    assert.equal(result.success,true,JSON.stringify(result));
    assert.equal(result.outputs.title,"ordinary-visible-42");
  });
  await check("empty paced type validates without focus or input", async () => {
    await navigate();
    const setup="(()=>{document.body.innerHTML='<input id=empty-paced>';window.__emptyFocus=0;window.__emptyInput=0;" +
      "const e=document.querySelector('#empty-paced');e.onfocus=()=>window.__emptyFocus++;e.oninput=()=>window.__emptyInput++;return true})()";
    assert.equal((await api("evaluate",{tabId,expression:setup})).success,true);
    const result=await api("play-script",{...workflow([{action:"type",target:{selector:"#empty-paced"},text:"",typingDelayMs:1000}]),
      capture:{formats:["screenshots"],maxWidth:640}});
    assert.equal(result.success,true,JSON.stringify(result));
    assert.ok(result.artifacts.some(item=>item.mimeType==="image/png"));
    assert.deepEqual((await api("evaluate",{tabId,expression:"[window.__emptyFocus,window.__emptyInput]"})).result,[0,0]);
    await download(result);
  });
  await check("paced typing stops on focus drift without refocus", async () => {
    await navigate();
    const setup="(()=>{document.body.innerHTML='<input id=drift><input id=other>';window.__drift=[];" +
      "document.querySelector('#drift').oninput=e=>{window.__drift.push(e.data);document.querySelector('#other').focus()};return true})()";
    assert.equal((await api("evaluate",{tabId,expression:setup})).success,true);
    const result=await api("play-script",workflow([{action:"type",target:{selector:"#drift"},text:"ABC",typingDelayMs:100}]));
    assert.equal(result.success,false);assert.equal(result.mayHaveCompleted,true);
    assert.equal(result.error?.code,"INPUT_UNCERTAIN");
    assert.deepEqual((await api("evaluate",{tabId,expression:"window.__drift"})).result,["A"]);
    assert.equal((await api("evaluate",{tabId,expression:"document.activeElement.id"})).result,"other");
    assert.equal((await api("play-script",workflow([{action:"wait",ms:0}]))).success,true);
  });
  await check("paced edit sensitivity change discards capture", async () => {
    await navigate();
    const setup="(()=>{document.title='ABC';document.body.innerHTML='<input id=paced-secret>';window.__pacedSecret=0;" +
      "document.querySelector('#paced-secret').oninput=e=>{window.__pacedSecret++;e.currentTarget.type='password'};return true})()";
    assert.equal((await api("evaluate",{tabId,expression:setup})).success,true);
    const result=await api("play-script",{...workflow([{action:"output",name:"prior",source:"title"},{action:"type",target:{selector:"#paced-secret"},text:"ABC",typingDelayMs:100}]),
      capture:{formats:["gif","screenshots"],fps:15,maxWidth:640,maxDurationMs:12000,maxBytes:8388608}});
    assert.equal(result.success,false);assert.equal(result.mayHaveCompleted,true);
    assert.equal(result.error?.code,"SENSITIVE_CAPTURE_REFUSED");
    assert.deepEqual(result.artifacts,[]);
    assert.ok(!JSON.stringify(result).includes("ABC"),"inferred sensitive literal leaked");
    assert.equal((await api("evaluate",{tabId,expression:"window.__pacedSecret"})).result,1);
  });
  await check("paced navigation uncertainty scrubs the full literal", async () => {
    await navigate();
    const setup="(()=>{document.title='AB';document.body.innerHTML='<input id=paced-navigate>';" +
      "document.querySelector('#paced-navigate').oninput=()=>{location.href='/next'};return true})()";
    assert.equal((await api("evaluate",{tabId,expression:setup})).success,true);
    const result=await api("play-script",workflow([{action:"output",name:"prior",source:"title"},
      {action:"type",target:{selector:"#paced-navigate"},text:"AB",typingDelayMs:100}]));
    assert.equal(result.success,false);assert.equal(result.mayHaveCompleted,true);
    assert.ok(!JSON.stringify(result).includes("AB"),"unknown edit leaked its full literal");
  });
  await check("paced typing abort stops without replay and safely handles capture", async () => {
    await navigate();
    const baseline=fixture.events.length;
    const setup="(()=>{document.body.innerHTML='<input id=abort-paced>';" +
      "document.querySelector('#abort-paced').oninput=()=>fetch('/events',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({documentId:'paced-abort-proof',type:'paced-first'})});return true})()";
    assert.equal((await api("evaluate",{tabId,expression:setup})).success,true);
    const pending=api("play-script",{...workflow([{action:"type",target:{selector:"#abort-paced"},
      text:"ABCDEFGHIJ",typingDelayMs:1000}]),
      capture:{formats:["gif","screenshots"],fps:15,maxWidth:640,maxDurationMs:20000,maxBytes:8388608}});
    let status;
    for(let attempt=0;attempt<50;attempt++){
      status=await api("get-script-status");if(status.playing)break;
      await new Promise(resolve=>setTimeout(resolve,100));
    }
    assert.equal(status.playing,true);
    const end=Date.now()+10000;
    while(!fixture.events.slice(baseline).some(event=>event.type==="paced-first") && Date.now()<end)
      await new Promise(resolve=>setTimeout(resolve,25));
    assert.ok(fixture.events.slice(baseline).some(event=>event.type==="paced-first"),"first input was not observed");
    assert.equal((await api("abort-script",{runId:status.runId})).success,true);
    const result=await pending;
    assert.equal(result.success,false);assert.equal(result.aborted,true);assert.equal(result.mayHaveCompleted,true);
    assert.ok(result.artifacts.every(item=>item.partial));
    if(result.artifacts.length) await download(result);
    const value=(await api("evaluate",{tabId,expression:"document.querySelector('#abort-paced').value"})).result;
    assert.ok(value.length>=1 && value.length<10);
    assert.equal("ABCDEFGHIJ".startsWith(value),true);
    assert.equal((await api("play-script",workflow([{action:"wait",ms:0}]))).success,true);
  });
  await check("paced plan rejects excess duration before any action", async () => {
    await navigate();
    assert.equal((await api("evaluate",{tabId,expression:"window.__planned=0;document.querySelector('#unique').onclick=()=>window.__planned++;true"})).success,true);
    const result=await api("play-script",workflow([click("Confirm order"),
      {action:"type",target:{selector:"#unique"},text:"x".repeat(62),typingDelayMs:1000}]));
    assert.equal(result.success,false);assert.equal(result.error?.code,"INVALID_PACED_TYPING");
    assert.equal((await api("evaluate",{tabId,expression:"window.__planned"})).result,0);
  });
}
