import test from 'node:test';
import assert from 'node:assert/strict';
import { githubClient, createCandidate, openCandidate, dispatchChecks, publishStatus, reportMarkdown, workflows } from '../../scripts/engine-updates/github.mjs';

const report = { repository: 'owner/repo', revision: 'a'.repeat(40), checkedAt: '2026-11-18T00:00:00Z',
  runUrl: 'https://github.com/owner/repo/actions/runs/123', modes: { 'scripts/download-cef.sh': '100755' }, plan: [] };
const notFound = () => Object.assign(new Error('not found'), { status: 404 });

test('GitHub credentials stay in the header and API errors propagate', async () => {
  const api = githubClient('owner/repo', 'test-token', async (url, options) => {
    assert.ok(!url.includes('test-token'));
    assert.equal(options.headers.Authorization, 'Bearer test-token');
    assert.equal(options.redirect, 'error');
    return Response.json({ message: 'Forbidden' }, { status: 403 });
  });
  await assert.rejects(api('POST', '/pulls', {}), /403 Forbidden/);
  assert.throws(() => githubClient('not/a/repository', 'token'));
});

test('open candidate discovery paginates and ignores fork branches', async () => {
  const fork = { head: { ref: 'engine-update/chromium-a', repo: { full_name: 'other/repo' } }, base: { repo: { full_name: 'owner/repo' } } };
  const own = { ...fork, head: { ...fork.head, repo: { full_name: 'owner/repo' } } };
  let calls = 0;
  const found = await openCandidate(async (_method, path) => {
    calls++;
    if (path.endsWith('page=1')) return Array(100).fill(fork);
    return [own];
  });
  assert.equal(found, own);
  assert.equal(calls, 2);
});

test('dispatch recovers partially started checks without repeating existing runs', async () => {
  const posts = [];
  await dispatchChecks(async (method, path, body) => {
    if (method === 'GET') return { workflow_runs: path.includes(workflows[0]) ? [{ id: 1 }] : [] };
    posts.push({ path, body });
  }, { head: { sha: 'b'.repeat(40), ref: 'engine-update/chromium-123' } });
  assert.equal(posts.length, workflows.length - 1);
  assert.ok(posts.every(p => p.body.ref === 'engine-update/chromium-123'));
});

function candidateApi({ branchExists = false, wrongTree = false, closed = false } = {}) {
  const calls = [];
  const api = async (method, path, body) => {
    calls.push({ method, path, body });
    if (path === '/git/ref/heads/main') return { object: { sha: report.revision } };
    if (path === `/git/commits/${report.revision}`) return { tree: { sha: 'base-tree' } };
    if (path === '/git/blobs') return { sha: 'blob' };
    if (path === '/git/trees') return { sha: 'new-tree' };
    if (path.startsWith('/git/ref/heads/engine-update/')) {
      if (!branchExists) throw notFound();
      return { object: { sha: 'candidate' } };
    }
    if (path === '/git/commits/candidate') return { tree: { sha: wrongTree ? 'human-edits' : 'new-tree' }, parents: [{ sha: 'original-base' }] };
    if (path === '/git/commits/original-base') return { tree: { sha: 'older-base-tree' } };
    if (path === '/git/commits' && method === 'POST') return { sha: 'candidate' };
    if (path === '/git/refs') return { object: { sha: 'candidate' } };
    if (path.startsWith('/pulls?')) return closed ? [{ state: 'closed', html_url: 'closed-pr' }] : [];
    if (path === '/pulls' && method === 'POST') return { number: 123, html_url: 'candidate-pr' };
    throw new Error(`Unexpected API request: ${method} ${path}`);
  };
  return { api, calls };
}

test('candidate creation preserves executable mode, never writes main, and creates one PR', async () => {
  const { api, calls } = candidateApi();
  const pull = await createCandidate(api, report, { 'scripts/download-cef.sh': '#!/bin/bash\n' });
  assert.equal(pull.number, 123);
  assert.equal(calls.find(c => c.path === '/git/trees').body.tree[0].mode, '100755');
  assert.ok(calls.find(c => c.path === '/git/refs').body.ref.startsWith('refs/heads/engine-update/chromium-'));
  assert.ok(calls.every(c => c.method !== 'PATCH' && c.method !== 'DELETE'));
});

test('retry recovers a branch created before PR creation failed', async () => {
  const { api, calls } = candidateApi({ branchExists: true });
  await createCandidate(api, report, { 'scripts/download-cef.sh': 'candidate' });
  assert.equal(calls.filter(c => c.path === '/git/refs').length, 0);
  assert.equal(calls.filter(c => c.path === '/pulls').length, 1);
  assert.equal(calls.find(c => c.path === '/git/trees').body.base_tree, 'older-base-tree');
});

test('human edits, closed decisions, empty diffs and advancing main are preserved', async () => {
  await assert.rejects(createCandidate(candidateApi({ branchExists: true, wrongTree: true }).api,
    report, { 'scripts/download-cef.sh': 'candidate' }), /preserving/);
  await assert.rejects(createCandidate(candidateApi({ branchExists: true, closed: true }).api,
    report, { 'scripts/download-cef.sh': 'candidate' }), /already closed/);
  await assert.rejects(createCandidate(candidateApi().api, report, {}), /empty/);
  await assert.rejects(createCandidate(async () => ({ object: { sha: 'advanced' } }),
    report, { 'scripts/download-cef.sh': 'candidate' }), /advanced/);
});

test('public status reuses its issue and retains the timestamp and failure evidence', async () => {
  const calls = [];
  const failure = { ...report, error: 'CEF archive checksum/size mismatch' };
  await publishStatus(async (method, path, body) => {
    calls.push({ method, path, body });
    if (path.startsWith('/issues?')) return [{ number: 12, body: '<!-- kelpie-chromium-pipeline -->' }];
    return { html_url: 'status-issue' };
  }, failure);
  const patch = calls.find(c => c.method === 'PATCH');
  assert.equal(patch.path, '/issues/12');
  assert.ok(patch.body.body.includes(failure.checkedAt));
  assert.ok(patch.body.body.includes(failure.error));
  assert.ok(reportMarkdown(report).includes('do not certify installed or shipped'));
});
