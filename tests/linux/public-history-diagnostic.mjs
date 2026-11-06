// Public calls only. No raw page data, protocol IDs or endpoint values are retained.
export function createPublicHistoryReport() {
  return { version: 1, stages: [], limitations: {
    noHistory: 'insufficient', iframe: 'insufficient', replacement: 'insufficient',
    rawDispatchCount: 'not-observed',
  }, complete: false };
}
export async function publicHistoryDiagnostic({ call, origin, lifecycle, delay, report = createPublicHistoryReport() }) {
  const stop = Symbol('stop');
  async function stage(name, method, params, check = () => true) {
    let result;
    try { result = await call(method, params); }
    catch { report.stages.push({ name, status: 'call-failed' }); throw stop; }
    if (!result || result.ok !== true || Object.hasOwn(result, 'error') || !check(result.value)) {
      report.stages.push({ name, status: 'invalid-or-refused' }); throw stop;
    }
    report.stages.push({ name, status: 'passed' });
  }
  const url = expected => value => value === origin + expected;
  const ready = value => value?.ready === true && ['interactive', 'complete'].includes(value.documentState);
  try {
    await stage('root', 'tab.goto', { url: origin + '/' });
    await delay(250);
    await stage('next', 'tab.goto', { url: origin + '/next' });
    await delay(250);
    let mark = lifecycle.mark();
    await stage('back', 'tab.back', {});
    await stage('back-url', 'tab.url', {}, url('/'));
    await stage('back-ready', 'tab.ready', { state: 'interactive' }, ready);
    await delay(250);
    report.backLifecycle = lifecycle.result(mark, 'root');
    mark = lifecycle.mark();
    await stage('forward', 'tab.forward', {});
    await stage('forward-url', 'tab.url', {}, url('/next'));
    await stage('forward-ready', 'tab.ready', { state: 'interactive' }, ready);
    await delay(250);
    report.forwardLifecycle = lifecycle.result(mark, 'next');
    await stage('hash-one', 'tab.goto', { url: origin + '/next#one' });
    await stage('hash-two', 'tab.goto', { url: origin + '/next#two' });
    await delay(250);
    mark = lifecycle.mark();
    await stage('hash-back', 'tab.back', {});
    await stage('hash-back-url', 'tab.url', {}, url('/next#one'));
    await stage('hash-back-ready', 'tab.ready', { state: 'interactive' }, ready);
    await delay(250);
    report.hashBack = lifecycle.hashResult(mark, 'h1');
    mark = lifecycle.mark();
    await stage('hash-forward', 'tab.forward', {});
    await stage('hash-forward-url', 'tab.url', {}, url('/next#two'));
    await stage('hash-forward-ready', 'tab.ready', { state: 'interactive' }, ready);
    await delay(250);
    report.hashForward = lifecycle.hashResult(mark, 'h2');
    report.complete = report.backLifecycle.status === 'restored-from-bfcache'
      && report.forwardLifecycle.status === 'restored-from-bfcache'
      && report.hashBack.status === 'observed' && report.hashForward.status === 'observed';
  } catch (error) { if (error !== stop) throw error; }
  return report;
}
