import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, mkdir, readFile, writeFile, symlink} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {copyReviewedEvidence} from './worker-evidence-allowlist.mjs';

test('copies only explicit evidence paths, never profiles or unknown files', async()=>{
 const root=await mkdtemp(join(tmpdir(),'kelpie-evidence-'));
  const src=join(root,'src'),out=join(root,'out');
  await mkdir(join(src,'worker-ab-evidence','playwright','home','chromium'),{recursive:true});
  await writeFile(join(src,'worker-ab-evidence','playwright','report.json'),'{}');
  await writeFile(join(src,'worker-ab-evidence','playwright','unknown.json'),'private');
  await writeFile(join(src,'worker-ab-evidence','playwright','home','chromium','profile'),'private');
  assert.equal(await copyReviewedEvidence(src,out),1);
  assert.equal(await readFile(join(out,'worker-ab-evidence','playwright','report.json'),'utf8'),'{}');
  await assert.rejects(readFile(join(out,'worker-ab-evidence','playwright','unknown.json')));
  await assert.rejects(readFile(join(out,'worker-ab-evidence','playwright','home','chromium','profile')));
});

test('normal and diagnostic runs upload only the staged allowlist', async()=>{
 const workflow=await readFile(new URL('../../.github/workflows/worker-comparison.yml',import.meta.url),'utf8');
 const stage=workflow.indexOf('name: Stage allowlisted evidence only');
 const upload=workflow.indexOf('name: Retain scoped evidence and failures');
 assert.ok(stage>=0&&upload>stage);
 const fragment=workflow.slice(upload);
 const block=fragment.match(/^ {10}path: \|\r?\n((?: {12}[^\r\n]+\r?\n)+)/m);
 assert.ok(block);
 assert.deepEqual(block[1].trim().split(/\r?\n/).map(line=>line.trim()),['${{ runner.temp }}/worker-ab-upload/']);
});

test('rejects an in-root parent symlink even when its target is allowlisted in shape', async()=>{
 const root=await mkdtemp(join(tmpdir(),'kelpie-evidence-link-'));
 const src=join(root,'src'),target=join(src,'different'),arm=join(src,'worker-ab-evidence');
 await mkdir(target,{recursive:true});await mkdir(arm,{recursive:true});
 await writeFile(join(target,'report.json'),'{}');
 await symlink(target,join(arm,'playwright'),process.platform==='win32'?'junction':'dir');
 await assert.rejects(copyReviewedEvidence(src,join(root,'out')),/EVIDENCE_INVALID/);
});
