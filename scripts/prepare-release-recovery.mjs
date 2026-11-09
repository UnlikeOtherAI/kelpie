import { appendFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

export function validateRecovery(run, workflow, release, commit, artifacts) {
  if (run.event !== 'release' || run.workflow_id !== workflow.id || run.status !== 'completed') throw new Error('Recovery requires a completed run of the release workflow.');
  const tag = run.head_branch;
  if (!/^release\/\d{4}-\d{2}-\d{2}(\.\d+)?$/.test(tag) || release.tag_name !== tag || release.draft || release.prerelease || commit.sha !== run.head_sha) {
    throw new Error('Release tag, source revision and completed build must match.');
  }
  const body = release.body ?? '';
  const selected = component => !body.startsWith('<!-- kelpie-release-components:') || body.includes(`<!-- kelpie-release-component: ${component} -->`);
  const expected = [...(selected('linux') ? ['linux-release-ubuntu-22.04', 'linux-release-fedora-40'] : []),
    ...(selected('android') ? ['android-release'] : []), ...(selected('cli') ? ['cli-release'] : [])];
  if (!expected.length || expected.some(name => !artifacts.some(artifact => artifact.name === name && !artifact.expired))) throw new Error('All selected components must have completed build artifacts.');
  return { tag, linux: selected('linux') };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const id = process.argv[2];
  if (!/^\d+$/.test(id ?? '')) throw new Error('A numeric release workflow run ID is required.');
  const api = path => JSON.parse(execFileSync('gh', ['api', `repos/UnlikeOtherAI/kelpie/${path}`], { encoding: 'utf8' }));
  const run = api(`actions/runs/${id}`);
  const result = validateRecovery(run, api('actions/workflows/release.yml'),
    api(`releases/tags/${encodeURIComponent(run.head_branch)}`), api(`commits/${encodeURIComponent(run.head_branch)}`),
    api(`actions/runs/${id}/artifacts?per_page=100`).artifacts);
  appendFileSync(process.env.GITHUB_OUTPUT, `tag=${result.tag}\nlinux=${result.linux}\n`);
  console.log(`Validated ${result.tag} artifacts from ${run.head_sha}.`);
}
