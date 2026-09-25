#!/usr/bin/env node
import assert from 'node:assert/strict';
import { mkdtemp, readFile, stat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { spawn } from 'node:child_process';
import { runCoreAcceptance } from '../windows/lib/acceptance.mjs';
import { startFixtureServer } from '../windows/lib/fixture.mjs';
import { control, waitFor } from '../windows/lib/http.mjs';
import { fileExists, waitForReadiness } from '../windows/lib/process.mjs';

// Run under a real X11 or Wayland desktop: viewport tests exercise GTK resize.
const exe=resolve(process.argv[2] ?? 'apps/linux/build/kelpie-linux');
const profile=await mkdtemp(join(tmpdir(),'kelpie-linux-acceptance-'));
const readinessFile=join(profile,'readiness.json');
const fixture=await startFixtureServer();
let child, readiness;
function start(extra=[]) {
  child=spawn(exe,['--profile-dir',profile,'--port','0','--width','1280','--height','720',...extra],{stdio:['ignore','ignore','pipe']});
  let errors=''; child.stderr.on('data',data=>{errors=(errors+data).slice(-8192);});
  child.on('error',error=>{errors+=error.message;});
  return async()=>{
    try { readiness=await waitForReadiness(readinessFile,30000); }
    catch(error){throw new Error(`${error.message}\n${errors}`);}
  };
}
async function close() {
  if(!child || child.exitCode!==null)return;
  await control(readiness,'close-browser',{});
  await waitFor(()=>child.exitCode!==null,'graceful Linux shutdown',15000);
  assert.equal(await fileExists(readinessFile),false,'shutdown removes readiness');
}
try {
  await start(['--url',fixture.baseUrl+'/'])();
  assert.equal((await stat(profile)).mode&0o777,0o700);
  assert.equal((await stat(readinessFile)).mode&0o777,0o600);
  const contender=spawn(exe,['--profile-dir',profile,'--port','0'],{stdio:'ignore'});
  await waitFor(()=>contender.exitCode!==null,'profile lock rejection',10000);
  assert.notEqual(contender.exitCode,0);
  assert.equal(JSON.parse(await readFile(readinessFile,'utf8')).launchId,readiness.launchId);
  await runCoreAcceptance(readiness,fixture.baseUrl+'/');
  const saved=await control(readiness,'new-tab',{url:fixture.baseUrl+'/',partition:'linux-persistent',persistent:true,name:'Persistent Linux tab'});
  await control(readiness,'new-tab',{url:fixture.baseUrl+'/',partition:'linux-transient',persistent:false});
  await close();
  await start()();
  const restored=await control(readiness,'get-tabs',{});
  assert(restored.tabs.some(tab=>tab.id===saved.tab.id && tab.partition==='linux-persistent' && tab.name==='Persistent Linux tab'));
  assert(!restored.tabs.some(tab=>tab.partition==='linux-transient'));
  await close();
  console.log('PASS Linux native HTTP/MCP, trusted input, screenshots, partitions, profile ownership, session restore and readiness cleanup');
} finally {
  if(child && child.exitCode===null)await close().catch(error=>{child.kill('SIGTERM');console.error(error.message);});
  await fixture.close();
}

