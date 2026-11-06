import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, mkdir, readFile, writeFile} from 'node:fs/promises';
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
 assert.ok(fragment.includes('/worker-ab-upload/'));
 assert.ok(!fragment.includes('/worker-ab-evidence/')&&!fragment.includes('/worker-ab-setup/'));
});
