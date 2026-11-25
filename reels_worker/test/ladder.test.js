'use strict';
const test = require('node:test');
const assert = require('node:assert');
const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { parseProbe, chooseRungs, buildHlsArgs, buildPosterArgs } = require('../ladder');

test('chooseRungs never upscales and keeps aspect', () => {
  const r = chooseRungs(1080, 1920);
  assert.deepStrictEqual(r.map((x) => [x.width, x.height]), [[360, 640], [540, 960], [720, 1280]]);
  assert.deepStrictEqual(chooseRungs(540, 960).map((x) => x.name), ['low', 'mid']);
  assert.deepStrictEqual(chooseRungs(240, 426).map((x) => x.name), ['low']);
  assert.deepStrictEqual(chooseRungs(1920, 1080).map((x) => [x.width, x.height])[0], [640, 360]);
});

test('parseProbe swaps sides for rotated phone video', () => {
  const p = parseProbe({
    streams: [
      { codec_type: 'video', width: 1920, height: 1080, avg_frame_rate: '30000/1001', side_data_list: [{ rotation: -90 }] },
      { codec_type: 'audio' },
    ],
    format: { duration: '12.5' },
  });
  assert.deepStrictEqual(p, { width: 1080, height: 1920, duration: 12.5, hasAudio: true, fps: 30000 / 1001 });
});

function hasFfmpeg() {
  try { execFileSync('ffmpeg', ['-version']); return true; } catch { return false; }
}

for (const withAudio of [true, false]) {
  test(`real ffmpeg run produces a playable ladder (audio=${withAudio})`, { skip: !hasFfmpeg() }, () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ladder-'));
    const input = path.join(dir, 'in.mp4');
    const src = ['-f', 'lavfi', '-i', 'testsrc2=size=720x1280:rate=60:duration=5'];
    if (withAudio) src.push('-f', 'lavfi', '-i', 'sine=frequency=440:duration=5');
    execFileSync('ffmpeg', ['-hide_banner', '-loglevel', 'error', '-y', ...src, '-shortest', input]);

    const probe = parseProbe(JSON.parse(execFileSync('ffprobe',
      ['-v', 'error', '-show_streams', '-show_format', '-of', 'json', input]).toString()));
    const rungs = chooseRungs(probe.width, probe.height);
    const out = path.join(dir, 'out');
    fs.mkdirSync(out);
    execFileSync('ffmpeg', ['-loglevel', 'error', ...buildHlsArgs(input, out, rungs, probe.hasAudio, probe.fps)]);
    execFileSync('ffmpeg', ['-loglevel', 'error',
      ...buildPosterArgs(input, path.join(out, 'poster.jpg'), path.join(dir, 'tiny.jpg'), probe.duration)]);

    const master = fs.readFileSync(path.join(out, 'master.m3u8'), 'utf8');
    assert.strictEqual((master.match(/#EXT-X-STREAM-INF/g) || []).length, 3);
    for (let i = 0; i < 3; i++) {
      const pl = fs.readFileSync(path.join(out, `v${i}`, 'index.m3u8'), 'utf8');
      assert.match(pl, /#EXT-X-ENDLIST/);
      // 5 s of video in 2 s segments -> 3 segments.
      assert.strictEqual((pl.match(/seg_\d+\.ts/g) || []).length, 3);
    }
    // Low rung is 360x640, capped at 30 fps, and segment 0 starts on a keyframe.
    const seg = path.join(out, 'v0', 'seg_000.ts');
    const s = JSON.parse(execFileSync('ffprobe', ['-v', 'error', '-select_streams', 'v:0',
      '-show_entries', 'stream=width,height,avg_frame_rate', '-of', 'json', seg]).toString()).streams[0];
    assert.deepStrictEqual([s.width, s.height, s.avg_frame_rate], [360, 640, '30/1']);
    assert.ok(fs.statSync(path.join(out, 'poster.jpg')).size > 0);
    assert.ok(fs.statSync(path.join(dir, 'tiny.jpg')).size < 2000, 'tiny preview stays small');
    fs.rmSync(dir, { recursive: true, force: true });
  });
}
