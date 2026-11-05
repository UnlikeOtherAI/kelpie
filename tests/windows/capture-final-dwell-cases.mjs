import assert from "node:assert/strict";

// A five-second indicator separates movie finalization from PNG-only completion.
export async function runFinalDwellCases({check,navigate,api,workflow,download,click}) {
  for (const [name,formats,explicit,movie] of [
    ["screenshots",["screenshots"],false,false],
    ["explicit PNG",null,true,false],
    ["movie",["gif"],false,true],
    ["combined",["screenshots","gif"],false,true],
  ]) await check("final dwell " + name, async () => {
    await navigate();
    const actions=[click("Confirm order")];
    if (explicit) actions.push({action:"screenshot"});
    const body={...workflow(actions),pointer:{enabled:false},
      tapIndicator:{color:"#F54242",radius:24,durationMs:5000,wobble:true,fade:true}};
    if (formats) body.capture={formats,fps:15,maxWidth:1000,maxDurationMs:30000,maxBytes:16777216};
    const result=await api("play-script",body);
    assert.equal(result.success,true,JSON.stringify(result.error));
    assert.equal(result.actionsExecuted,actions.length);
    const duration=result.totalDurationMs;
    assert.ok(Number.isFinite(duration));
    if (movie) assert.ok(duration>=4500,"movie endpoint completed before marker expiry: "+duration);
    else assert.ok(duration<4500,"PNG-only run waited for movie expiry or was too slow: "+duration);
    const expected=movie?"image/gif":"image/png";
    assert.ok(result.artifacts.some(artifact=>artifact.mimeType===expected));
    await download(result);
    return {runId:result.runId,durationMs:duration,formats:formats??["explicit PNG"]};
  });
}
