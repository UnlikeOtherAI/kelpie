import { createRequire } from 'node:module';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { mkdtemp, mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
const root = fileURLToPath(new URL('../..', import.meta.url));
await mkdir(path.join(root,'.cache'),{recursive:true});
const dir = await mkdtemp(path.join(root,'.cache/cdp-viewport-'));
await mkdir(path.join(dir, 'tmp'), {recursive:true});
process.env.TMPDIR=path.join(dir,'tmp');
const require = createRequire(path.join(root,'packages/shared/package.json'));
const { chromium } = require('playwright-core');
assert.ok(process.env.KELPIE_CHROMIUM_EXECUTABLE,'Select an existing browser with KELPIE_CHROMIUM_EXECUTABLE; this test never installs one');
let context;
const timer=setTimeout(()=>{context?.close().finally(()=>process.exit(124));},25000);
try {
 context=await chromium.launchPersistentContext(path.join(dir,'profile-pixel'),{
  headless:true,chromiumSandbox:true,
  executablePath:process.env.KELPIE_CHROMIUM_EXECUTABLE,viewport:null,
  hasTouch:true,args:['--use-mock-keychain','--window-size=800,600','--force-device-scale-factor=1'],timeout:15000
 });
 const page=context.pages()[0]??await context.newPage();
 page.setDefaultTimeout(8000);
 await page.setContent('<meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=4"><style>html,body{margin:0;width:1600px;height:2400px}body{background:repeating-linear-gradient(to bottom,#f00 0px,#f00 200px,#0f0 200px,#0f0 400px,#00f 400px,#00f 600px,#f0f 600px,#f0f 800px,#0ff 800px,#0ff 1000px,#ff0 1000px,#ff0 1200px)}</style>');
 await page.evaluate(()=>{globalThis.resizeEvents=[];for(const [object,name] of [[window,'layout'],[visualViewport,'visual']]){
  object.addEventListener('resize',()=>resizeEvents.push({name,innerWidth,innerHeight,width:visualViewport.width,height:visualViewport.height,scale:visualViewport.scale}));
 }});
 const cdp=await context.newCDPSession(page);
 const version=await cdp.send('Browser.getVersion');
 const metrics=()=>page.evaluate(()=>({scrollX,scrollY,innerWidth,innerHeight,dpr:devicePixelRatio,
  events:resizeEvents.slice(0,40),vv:{offsetX:visualViewport.offsetLeft,offsetY:visualViewport.offsetTop,pageX:visualViewport.pageLeft,
   pageY:visualViewport.pageTop,width:visualViewport.width,height:visualViewport.height,scale:visualViewport.scale}}));
 const results=[];
 for(const zoom of [1,2]){
  await cdp.send('Emulation.setPageScaleFactor',{pageScaleFactor:zoom});
  await page.evaluate(()=>scrollTo(0,600));
  await page.evaluate(()=>new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r))));
  for(const kind of ['no-clip','offset-clip','page-clip','scaled-page-clip']){
   await cdp.send('Emulation.setPageScaleFactor',{pageScaleFactor:zoom});
   await page.evaluate(()=>scrollTo(0,600));
   await page.evaluate(()=>new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r))));
   await page.evaluate(()=>{resizeEvents=[]});
   const before=await metrics();
   const v=before.vv;
   const args={format:'png',fromSurface:true,captureBeyondViewport:false};
   if(kind!=='no-clip')args.clip={x:kind.endsWith('page-clip')?v.pageX:v.offsetX,
    y:kind.endsWith('page-clip')?v.pageY:v.offsetY,width:v.width,height:v.height,scale:kind==='scaled-page-clip'?0.5:1};
   const {data}=await cdp.send('Page.captureScreenshot',args);
   await writeFile(path.join(dir,'zoom'+zoom+'-'+kind+'.png'),Buffer.from(data,'base64'));
   const pixels=await page.evaluate(async data=>{
    const blob=await (await fetch('data:image/png;base64,'+data)).blob();
    const image=await createImageBitmap(blob);const canvas=new OffscreenCanvas(image.width,image.height);
    const g=canvas.getContext('2d');g.drawImage(image,0,0);
    return {width:image.width,height:image.height,center:Array.from(g.getImageData(image.width/2,image.height/2,1,1).data)};
   },data);
   await page.evaluate(()=>new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r))));
   const after=await metrics();
   const colors=[[255,0,0,255],[0,255,0,255],[0,0,255,255],[255,0,255,255],[0,255,255,255],[255,255,0,255]];
   const expected=colors[Math.floor((before.vv.pageY+before.vv.height/2)/200)%colors.length];
   if(kind==='no-clip'){
    assert.deepEqual(pixels.center,expected,'Current surface must contain the scrolled/zoomed document');
    assert.equal(pixels.width,Math.round(before.innerWidth*before.dpr));
    assert.equal(pixels.height,Math.round(before.innerHeight*before.dpr));
    assert.deepEqual(after,before,'Current surface capture must not resize, scroll or reset page scale');
   } else if(kind==='offset-clip'){
    assert.notDeepEqual(pixels.center,expected,'Negative control must expose the old offset-only mistake');
   } else { assert.deepEqual(pixels.center,expected,'Document-origin control must select the intended band'); }
   results.push({zoom,kind,before,after,pixels});
  }
 }
 await writeFile(path.join(dir,'result.json'),JSON.stringify({version,results},null,2));
 console.log(JSON.stringify({passed:true,version,artifacts:dir,results}));
} finally { clearTimeout(timer);await context?.close(); }
