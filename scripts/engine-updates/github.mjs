import { createHash } from 'node:crypto';

const marker = '<!-- kelpie-chromium-pipeline -->';
export const label = 'engine-update';
export const workflows = ['engine-candidate.yml', 'lint.yml', 'macos.yml'];

export function githubClient(repository, token, fetcher = fetch) {
  if (!/^[\w.-]+\/[\w.-]+$/.test(repository) || !token) throw new Error('GitHub repository/token required');
  return async (method, path, body) => {
    const response = await fetcher(`https://api.github.com/repos/${repository}${path}`, {
      method, headers: { Authorization: `Bearer ${token}`, Accept: 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28', 'Content-Type': 'application/json' },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(120_000), redirect: 'error',
    });
    if (response.status === 204) return null;
    const data = await response.json();
    if (!response.ok) {
      const error = new Error(`GitHub ${method} ${path}: ${response.status} ${data.message ?? ''}`);
      error.status = response.status;
      throw error;
    }
    return data;
  };
}

export function reportMarkdown(report) {
  const lines = [marker, '# Chromium update pipeline', '', `Last check: **${report.checkedAt}**`,
    `Source: \`${report.revision}\``, `Run: ${report.runUrl}`, '',
    'These are source pins and build candidates. They do not certify installed or shipped app versions.', ''];
  if (report.error) lines.push(`**Check failed:** ${report.error}`, '');
  if (report.plan) {
    lines.push('| Platform | Source Chromium | Available CEF Chromium | Chrome stable | Action |',
      '| --- | --- | --- | --- | --- |');
    for (const p of report.plan) {
      lines.push(`| ${p.platform} | ${p.current.split('chromium-')[1]} | ${p.chromium} | ${p.chrome.version} | ${p.update ? 'Update needed' : 'No upgrade available'} |`);
    }
    lines.push('', 'Sources: [CEF builds](https://cef-builds.spotifycdn.com/index.json), ' +
      '[Chrome VersionHistory](https://developer.chrome.com/docs/web-platform/versionhistory/reference).',
    'CEF availability can lag Chrome stable; the table reports both. Older maintenance releases never downgrade a newer pin.', '');
  }
  if (report.pullRequest) lines.push(`Candidate PR: ${report.pullRequest}`, '');
  if (report.deferred) lines.push('An update PR is already open. Its commits are preserved; resolve it before a newer candidate is proposed.', '');
  if (report.plan?.some(p => p.sha256)) {
    lines.push('Verified candidate archives (SHA-256):', '');
    for (const p of report.plan.filter(p => p.sha256)) lines.push(`- [${p.platform} ${p.cef}](${p.url}): \`${p.sha256}\``);
    lines.push('');
  }
  lines.push('Merge, signing, installed-app smoke tests, and release publication remain separate gates. ' +
    'macOS qualification compiles the browser library; it does not package or sign the containing app.',
    '', 'A stale timestamp means there is no recent evidence. GitHub schedules can be delayed or disabled; ' +
    'see the workflow runs for failures and the releases page for published artifacts.');
  return lines.join('\n');
}

export async function openCandidate(api) {
  for (let page = 1; ; page++) {
    const pulls = await api('GET', `/pulls?state=open&base=main&per_page=100&page=${page}`);
    const candidate = pulls.find(pr => pr.head.ref.startsWith('engine-update/chromium-') &&
      pr.head.repo?.full_name === pr.base.repo?.full_name);
    if (candidate) return candidate;
    if (pulls.length < 100) return null;
  }
}

export async function publishStatus(api, report) {
  try { await api('GET', `/labels/${label}`); }
  catch (error) {
    if (error.status !== 404) throw error;
    await api('POST', '/labels', { name: label, color: '1d76db', description: 'Public Chromium maintenance evidence' });
  }
  let status;
  for (let page = 1; !status; page++) {
    const issues = await api('GET', `/issues?state=open&labels=${label}&per_page=100&page=${page}`);
    status = issues.find(issue => !issue.pull_request && issue.body?.startsWith(marker));
    if (issues.length < 100) break;
  }
  const body = reportMarkdown(report);
  return status ? api('PATCH', `/issues/${status.number}`, { body }) :
    api('POST', '/issues', { title: 'Chromium update pipeline status', labels: [label], body });
}

export async function createCandidate(api, report, changedFiles) {
  const paths = Object.keys(changedFiles).sort();
  if (!paths.length) throw new Error('Refusing an empty candidate');
  const suffix = createHash('sha256').update(JSON.stringify(changedFiles)).digest('hex').slice(0, 16);
  const branch = `engine-update/chromium-${suffix}`;
  const base = await api('GET', '/git/ref/heads/main');
  if (base.object.sha !== report.revision) throw new Error('main advanced during scan; next scheduled run will retry');
  const parent = await api('GET', `/git/commits/${report.revision}`);
  const entries = [];
  for (const path of paths) {
    const blob = await api('POST', '/git/blobs', { content: changedFiles[path], encoding: 'utf-8' });
    // Keep the checked-in executable bits, including the shell downloaders.
    entries.push({ path, mode: report.modes[path], type: 'blob', sha: blob.sha });
  }
  let ref;
  try { ref = await api('GET', `/git/ref/heads/${branch}`); }
  catch (error) { if (error.status !== 404) throw error; }
  if (ref) {
    const existing = await api('GET', `/git/commits/${ref.object.sha}`);
    // A previous attempt may have pushed this branch before PR creation failed,
    // while main has since advanced. Validate against that branch's own parent
    // instead of requiring today's unrelated main tree to be identical.
    if (existing.parents?.length !== 1) throw new Error('Unexpected candidate ancestry; preserving its commits');
    const originalBase = await api('GET', `/git/commits/${existing.parents[0].sha}`);
    const expected = await api('POST', '/git/trees', { base_tree: originalBase.tree.sha, tree: entries });
    if (existing.tree.sha !== expected.sha) throw new Error('Existing candidate branch differs; preserving its commits');
  } else {
    const tree = await api('POST', '/git/trees', { base_tree: parent.tree.sha, tree: entries });
    const commit = await api('POST', '/git/commits', { message: 'Update desktop CEF stable pins', tree: tree.sha, parents: [report.revision] });
    ref = await api('POST', '/git/refs', { ref: `refs/heads/${branch}`, sha: commit.sha });
  }
  const previous = await api('GET', `/pulls?state=all&head=${encodeURIComponent(report.repository.split('/')[0] + ':' + branch)}&per_page=100`);
  if (previous.length) {
    const open = previous.find(pr => pr.state === 'open');
    if (open) return open;
    throw new Error(`Candidate was already closed: ${previous[0].html_url}. Preserving the review decision.`);
  }
  const body = reportMarkdown(report) + '\n\n## Release gates\n\n' +
    '- Resolve failing candidate builds and review API compatibility.\n' +
    '- Bump each affected app version and verify the installed, signed release on its platform.\n' +
    '- Test navigation, authentication/passkeys, automation, and recovery before publication.\n' +
    '- Publish through the platform release process and link release evidence here.\n';
  return api('POST', '/pulls', { title: 'Update desktop CEF to available stable releases', head: branch, base: 'main', body });
}

// GITHUB_TOKEN-created PRs may require workflow approval. Explicit dispatch is
// supported without a PAT; its check runs attach to the candidate branch SHA.
export async function dispatchChecks(api, pull) {
  for (const workflow of workflows) {
    const runs = await api('GET', `/actions/workflows/${workflow}/runs?head_sha=${pull.head.sha}&event=workflow_dispatch&per_page=1`);
    if (runs.workflow_runs.length === 0) {
      await api('POST', `/actions/workflows/${workflow}/dispatches`, { ref: pull.head.ref });
    }
  }
}
