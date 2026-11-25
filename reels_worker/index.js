'use strict';
/**
 * Reels transcode job (Cloud Run Job, one execution per upload).
 *
 * Env (set per run by the onReelUploaded function):
 *   SOURCE_BUCKET, SOURCE_OBJECT, CONTENT_ID
 * Env (set on the job once):
 *   REELS_BUCKET    public bucket behind Cloud CDN, e.g. mpepe-2b4bd-reels
 *   REELS_CDN_BASE  public base URL, e.g. https://reels.example.com
 *                   (defaults to https://storage.googleapis.com/<REELS_BUCKET>)
 */
const { execFile } = require('node:child_process');
const { promisify } = require('node:util');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');
const admin = require('firebase-admin');
const { Storage } = require('@google-cloud/storage');
const { parseProbe, chooseRungs, buildHlsArgs, buildPosterArgs } = require('./ladder');

const run = promisify(execFile);
const IMMUTABLE = 'public, max-age=31536000, immutable';

function env(name, fallback) {
  const v = process.env[name] ?? fallback;
  if (v === undefined || v === '') throw new Error(`missing env ${name}`);
  return v;
}

function contentTypeFor(file) {
  if (file.endsWith('.m3u8')) return 'application/vnd.apple.mpegurl';
  if (file.endsWith('.ts')) return 'video/mp2t';
  if (file.endsWith('.jpg')) return 'image/jpeg';
  return 'application/octet-stream';
}

async function listFiles(dir) {
  const out = [];
  for (const entry of await fs.readdir(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...(await listFiles(full)));
    else out.push(full);
  }
  return out;
}

/** Uploads with a small worker pool; segments are many small files. */
async function uploadAll(bucket, localDir, prefix) {
  const files = await listFiles(localDir);
  let next = 0;
  async function worker() {
    while (next < files.length) {
      const file = files[next++];
      const rel = path.relative(localDir, file).split(path.sep).join('/');
      await bucket.upload(file, {
        destination: `${prefix}/${rel}`,
        resumable: false,
        metadata: { contentType: contentTypeFor(file), cacheControl: IMMUTABLE },
      });
    }
  }
  await Promise.all(Array.from({ length: 16 }, worker));
}

async function main() {
  const sourceBucket = env('SOURCE_BUCKET');
  const sourceObject = env('SOURCE_OBJECT');
  const contentId = env('CONTENT_ID');
  const reelsBucketName = env('REELS_BUCKET');
  const cdnBase = env('REELS_CDN_BASE', `https://storage.googleapis.com/${reelsBucketName}`)
    .replace(/\/+$/, '');

  admin.initializeApp();
  const db = admin.firestore();
  const storage = new Storage();
  const ref = db.collection('content').doc(contentId);

  const work = await fs.mkdtemp(path.join(os.tmpdir(), 'reel-'));
  const input = path.join(work, 'input');
  const out = path.join(work, 'out');
  await fs.mkdir(out);

  try {
    await storage.bucket(sourceBucket).file(sourceObject).download({ destination: input });

    const { stdout } = await run('ffprobe', [
      '-v', 'error', '-show_streams', '-show_format', '-of', 'json', input,
    ]);
    const probe = parseProbe(JSON.parse(stdout));
    if (probe.duration > 600) throw new Error('too_long');
    const rungs = chooseRungs(probe.width, probe.height);

    await run('ffmpeg', buildHlsArgs(input, out, rungs, probe.hasAudio, probe.fps), {
      maxBuffer: 64 * 1024 * 1024,
    });
    await run('ffmpeg', buildPosterArgs(
      input, path.join(out, 'poster.jpg'), path.join(work, 'tiny.jpg'), probe.duration,
    ));

    const tiny = (await fs.readFile(path.join(work, 'tiny.jpg'))).toString('base64');
    const firstSegment = await fs.stat(path.join(out, 'v0', 'seg_000.ts'));

    const prefix = `reels/${contentId}`;
    await uploadAll(storage.bucket(reelsBucketName), out, prefix);

    const base = `${cdnBase}/${prefix}`;
    await ref.update({
      status: 'ready',
      mediaUrl: `${base}/master.m3u8`,
      'mediaMetadata.isAdaptiveBitrate': true,
      'mediaMetadata.aspectRatio': probe.width / probe.height,
      'mediaMetadata.resolutions': rungs.map((r) => `${Math.min(r.width, r.height)}p`),
      'mediaMetadata.rungHeights': rungs.map((r) => r.height),
      'mediaMetadata.durationMs': Math.round(probe.duration * 1000),
      'mediaMetadata.thumbnailUrl': `${base}/poster.jpg`,
      'mediaMetadata.posterFrameUrl': `${base}/poster.jpg`,
      'mediaMetadata.tinyPreview': tiny,
      'mediaMetadata.firstSegmentBytes': firstSegment.size,
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log(JSON.stringify({ msg: 'reel ready', contentId, rungs: rungs.length }));
  } catch (err) {
    console.error(JSON.stringify({ msg: 'reel failed', contentId, err: String(err) }));
    await ref.update({
      status: 'failed',
      processingError: String(err && err.message ? err.message : err).slice(0, 200),
    });
    process.exitCode = 1;
  } finally {
    await fs.rm(work, { recursive: true, force: true });
  }
}

main();
