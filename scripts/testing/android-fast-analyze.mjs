import { strict as assert } from 'node:assert';
import { createHash } from 'node:crypto';
import { spawn, spawnSync } from 'node:child_process';
import { readFile, writeFile } from 'node:fs/promises';
import { consumeG08Frames } from '../../tests/capture/g08-frame-stream.mjs';
import { measureG08Frame } from '../../tests/capture/g08-pixels.mjs';
import { fitFastPointer } from '../../tests/capture/g08-fast-profile.mjs';

const [receiptPath, geometryPath, screenPath, outputPath] = process.argv.slice(2);
assert.ok(receiptPath && geometryPath && screenPath && outputPath);
const receipt = JSON.parse(await readFile(receiptPath, 'utf8'));
const geometry = JSON.parse(await readFile(geometryPath, 'utf8'));
const { start, finish } = receipt.scene;
const viewport = geometry.viewport;
assert.equal(viewport.width, start.viewport.width);
assert.equal(viewport.height, start.viewport.height);
assert.equal(viewport.offsetLeft, 0);
assert.equal(viewport.offsetTop, 0);
assert.equal(viewport.href, receipt.fixtureUrl.replace('127.0.0.1', '10.0.2.2'));
const crop = { x: geometry.left, y: geometry.top, width: geometry.right - geometry.left, height: geometry.bottom - geometry.top };
assert.ok(Object.values(crop).every(Number.isInteger) && crop.x >= 0 && crop.y >= 0 && crop.width > 0 && crop.height > 0);
const sources = [{ kind: 'native-screenrecord', file: screenPath, crop }, ...receipt.artifacts.map(item => ({ kind: item.mimeType, file: item.file, artifact: item }))];
const results = [];
for (const source of sources) {
  const result = { kind: source.kind, file: source.file, samples: [] };
  results.push(result);
  try {
    const bytes = await readFile(source.file);
    result.sha256 = createHash('sha256').update(bytes).digest('hex');
    if (source.artifact) assert.equal(result.sha256, source.artifact.sha256);
    const probe = spawnSync('ffprobe', ['-v', 'error', '-select_streams', 'v:0', '-show_frames',
      '-show_entries', 'frame=best_effort_timestamp_time:stream=width,height', '-of', 'json', source.file],
    { encoding: 'utf8', maxBuffer: 4194304, windowsHide: true });
    assert.equal(probe.status, 0);
    const metadata = JSON.parse(probe.stdout);
    const stream = metadata.streams[0];
    const times = metadata.frames.map(frame => Number(frame.best_effort_timestamp_time) * 1000);
    assert.ok(times.length > 0 && times.length <= 8000 && times.every((v, i) => Number.isFinite(v) && (!i || v > times[i - 1])));
    if (source.artifact) assert.deepEqual(times, source.artifact.timestamps.map(value => value * 1000));
    let width = stream.width, height = stream.height;
    const filters = [];
    if (source.crop) {
      assert.ok(crop.x + crop.width <= width && crop.y + crop.height <= height);
      width = Math.min(640, crop.width);
      height = Math.round(crop.height * width / crop.width);
      filters.push('format=rgb24', 'crop=' + [crop.width, crop.height, crop.x, crop.y].join(':'), 'scale=' + width + ':' + height);
    }
    assert.ok(width <= 640 && height <= 1600);
    const scale = { x: width / viewport.width, y: height / viewport.height };
    const marker = { center: { x: finish.center.x * scale.x, y: finish.center.y * scale.y }, radius: 48 * scale.x, color: '#ff0000' };
    const args = ['-v', 'error', '-threads', '1', '-filter_threads', '1', '-i', source.file];
    if (filters.length) args.push('-vf', filters.join(','));
    args.push('-map', '0:v:0', '-fps_mode', 'passthrough', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-');
    const child = spawn('ffmpeg', args, { windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] });
    let stderr = '';
    child.stderr.on('data', chunk => { if (stderr.length < 4096) stderr += chunk.toString().slice(0, 4096 - stderr.length); });
    const exited = new Promise((resolve, reject) => { child.once('error', reject); child.once('close', code => code === 0 ? resolve() : reject(Error('Decoder failed ' + code + ' ' + stderr))); });
    void exited.catch(() => {});
    const timeout = setTimeout(() => child.kill(), 120000);
    try {
      const count = await consumeG08Frames(child.stdout, width, height, (frame, index) => {
        assert.ok(index < times.length);
        const pixel = measureG08Frame(frame, width, height, marker).pointer;
        let total = 0;
        let nonwhite = 0;
        for (let y = 0; y < height; y += 4) {
          for (let x = 0; x < width; x += 4) {
            if (Math.hypot(x - marker.center.x, y - marker.center.y) <= marker.radius * 1.6 + 8) continue;
            if (pixel && x >= pixel.x - 4 && x <= pixel.x + 68 && y >= pixel.y - 4 && y <= pixel.y + 68) continue;
            const i = (y * width + x) * 3;
            total++;
            if (Math.min(frame[i], frame[i + 1], frame[i + 2]) < 235) nonwhite++;
          }
        }
        assert.ok(total > 0 && nonwhite / total < 0.005, 'FAST_BACKGROUND_UNCERTIFIED');
        if (pixel) result.samples.push({ timeMs: times[index], x: pixel.x / scale.x, y: pixel.y / scale.y });
      });
      await exited;
      assert.equal(count, times.length);
    } finally {
      clearTimeout(timeout);
      if (child.exitCode === null) child.kill();
      await exited.catch(() => {});
    }
    result.fit = fitFastPointer(result.samples, { from: start.center, to: finish.center, curve: 'c' });
    result.status = receipt.durationOmitted ? 'measured-350' : 'unexpected-350-fit';
  } catch (error) {
    result.error = String(error.message).slice(0, 1024);
    result.status = result.error.includes('INSUFFICIENT') ? 'insufficient' :
      result.error.includes('FAST_DURATION_MISMATCH') ? 'not-matched' : 'invalid';
  }
}
await writeFile(outputPath, JSON.stringify({ receiptPath, geometryPath, durationOmitted: receipt.durationOmitted, capture: receipt.capture, results }, null, 2));