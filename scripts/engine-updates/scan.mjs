import { mkdirSync, writeFileSync, appendFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { CEF_INDEX, PLATFORMS, fetchJson, latestStable, chromeStable, verifyArchive } from './upstream.mjs';
import { readSources, readPins, planUpdates, updateSources, FILES } from './pins.mjs';
import { githubClient, reportMarkdown, openCandidate, createCandidate, publishStatus, dispatchChecks } from './github.mjs';

const args = new Set(process.argv.slice(2));
for (const arg of args) if (!['--publish', '--verify-downloads'].includes(arg)) throw new Error(`Unknown option: ${arg}`);
const publish = args.has('--publish');
const repository = process.env.GITHUB_REPOSITORY ?? 'UnlikeOtherAI/kelpie';
const revision = execFileSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();
const report = { schemaVersion: 1, checkedAt: new Date().toISOString(), repository, revision,
  mode: publish ? 'publish' : 'dry-run',
  runUrl: process.env.GITHUB_RUN_ID ? `https://github.com/${repository}/actions/runs/${process.env.GITHUB_RUN_ID}` : 'Local dry run',
  modes: Object.fromEntries(FILES.map(path => [path,
    execFileSync('git', ['ls-files', '--stage', '--', path], { encoding: 'utf8' }).split(' ')[0]])) };
const api = publish ? githubClient(repository, process.env.GH_TOKEN) : null;
try {
  const sources = readSources();
  const pins = readPins(sources);
  const index = await fetchJson(CEF_INDEX);
  const candidates = await Promise.all(PLATFORMS.map(async platform => ({
    ...latestStable(index, platform), chrome: await chromeStable(platform),
  })));
  report.plan = planUpdates(pins, candidates);
  const existing = api ? await openCandidate(api) : null;
  if (existing) {
    report.pullRequest = existing.html_url;
    report.deferred = report.plan.some(p => p.update);
    await dispatchChecks(api, existing);
  } else if (report.plan.some(p => p.update) && (publish || args.has('--verify-downloads'))) {
    for (const candidate of report.plan.filter(p => p.update)) {
      console.log(`Verifying ${candidate.platform}: ${candidate.cef}`);
      candidate.sha256 = await verifyArchive(candidate);
    }
    const changes = updateSources(sources, report.plan);
    report.changedFiles = Object.keys(changes);
    if (api) {
      const pull = await createCandidate(api, report, changes);
      report.pullRequest = pull.html_url;
      await dispatchChecks(api, pull);
    }
  }
  if (api) report.statusIssue = (await publishStatus(api, report)).html_url;
} catch (error) {
  report.error = error.message;
  process.exitCode = 1;
  if (api) {
    try { report.statusIssue = (await publishStatus(api, report)).html_url; }
    catch (statusError) { report.statusError = statusError.message; }
  }
} finally {
  mkdirSync('.cache/engine-updates', { recursive: true });
  const markdown = reportMarkdown(report);
  writeFileSync('.cache/engine-updates/report.json', JSON.stringify(report, null, 2) + '\n');
  writeFileSync('.cache/engine-updates/report.md', markdown + '\n');
  if (process.env.GITHUB_STEP_SUMMARY) appendFileSync(process.env.GITHUB_STEP_SUMMARY, markdown + '\n');
  console.log(markdown);
}
