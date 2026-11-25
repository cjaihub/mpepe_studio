'use strict';
/**
 * Pure helpers for the reels transcode: probe parsing, rung choice and the
 * FFmpeg argument list. Kept free of cloud code so it can be tested locally.
 */

/**
 * The quality ladder. Sizes are for a vertical 9:16 video; `short` is the
 * short side, so landscape uploads get the same pixel budget.
 * No 1080p on purpose: about 2.5x the bytes of 720p for little visible gain
 * on a phone, and delivery bytes are the biggest cost.
 */
const LADDER = [
  { name: 'low', short: 360, videoKbps: 500, maxKbps: 650 },
  { name: 'mid', short: 540, videoKbps: 1000, maxKbps: 1300 },
  { name: 'high', short: 720, videoKbps: 2000, maxKbps: 2600 },
];

const SEGMENT_SECONDS = 2;
const MAX_FPS = 30;
const AUDIO_KBPS = 96;

/** Reads width/height/duration/audio from `ffprobe -of json` output. */
function parseProbe(probe) {
  const streams = probe.streams || [];
  const video = streams.find((s) => s.codec_type === 'video');
  if (!video) throw new Error('no_video_stream');
  let width = Number(video.width);
  let height = Number(video.height);

  // Phone videos are often stored landscape with a rotation flag.
  let rotation = Number((video.tags && video.tags.rotate) || 0);
  for (const sd of video.side_data_list || []) {
    if (sd.rotation !== undefined) rotation = Number(sd.rotation);
  }
  if (Math.abs(rotation) % 180 === 90) [width, height] = [height, width];

  const duration = Number((probe.format && probe.format.duration) || video.duration || 0);
  const hasAudio = streams.some((s) => s.codec_type === 'audio');
  const [num, den] = String(video.avg_frame_rate || video.r_frame_rate || '0/1').split('/').map(Number);
  const fps = den ? num / den : 0;
  return { width, height, duration, hasAudio, fps };
}

/** Rungs that do not upscale the source. Always at least the lowest one. */
function chooseRungs(width, height) {
  const sourceShort = Math.min(width, height);
  const portrait = height >= width;
  const fit = LADDER.filter((r) => r.short <= sourceShort);
  const rungs = fit.length ? fit : [LADDER[0]];
  return rungs.map((r) => {
    // Scale the short side to the rung, keep aspect, even dimensions.
    const long = Math.round((r.short * Math.max(width, height)) / sourceShort / 2) * 2;
    const w = portrait ? r.short : long;
    const h = portrait ? long : r.short;
    return { ...r, width: w, height: h, bandwidth: (r.maxKbps + AUDIO_KBPS) * 1000 };
  });
}

/** One FFmpeg run that writes all rungs plus master.m3u8 into `outDir`. */
function buildHlsArgs(input, outDir, rungs, hasAudio, sourceFps = 0) {
  const n = rungs.length;
  const splitOuts = rungs.map((_, i) => `[s${i}]`).join('');
  const scales = rungs
    .map((r, i) => `[s${i}]scale=${r.width}:${r.height}:flags=bicubic,setsar=1[v${i}]`)
    .join(';');
  // Cap frame rate (60 fps doubles bytes for little gain in a feed). Unknown
  // or variable rates are also normalised to 30.
  const capFps = !(sourceFps > 0) || sourceFps > MAX_FPS + 0.5;
  const fps = capFps ? `fps=${MAX_FPS},` : '';
  const filter = `[0:v]${fps}split=${n}${splitOuts};${scales}`;

  const args = ['-hide_banner', '-y', '-i', input, '-filter_complex', filter];
  rungs.forEach((r, i) => {
    args.push(
      '-map', `[v${i}]`,
      `-c:v:${i}`, 'libx264',
      `-profile:v:${i}`, 'high',
      `-b:v:${i}`, `${r.videoKbps}k`,
      `-maxrate:v:${i}`, `${r.maxKbps}k`,
      `-bufsize:v:${i}`, `${r.maxKbps * 2}k`,
    );
  });
  if (hasAudio) {
    for (let i = 0; i < n; i++) args.push('-map', '0:a:0');
    args.push('-c:a', 'aac', '-b:a', `${AUDIO_KBPS}k`, '-ac', '2', '-ar', '44100');
  }
  args.push(
    '-preset', 'medium',
    '-pix_fmt', 'yuv420p',
    // A keyframe at the start of every segment: each segment can start on
    // its own, so preloading only segment 0 is enough for an instant start.
    '-force_key_frames', `expr:gte(t,n_forced*${SEGMENT_SECONDS})`,
    '-sc_threshold', '0',
    '-f', 'hls',
    '-hls_time', String(SEGMENT_SECONDS),
    '-hls_playlist_type', 'vod',
    '-hls_flags', 'independent_segments',
    '-hls_segment_type', 'mpegts',
    '-hls_segment_filename', `${outDir}/v%v/seg_%03d.ts`,
    '-master_pl_name', 'master.m3u8',
    '-var_stream_map', rungs.map((_, i) => (hasAudio ? `v:${i},a:${i}` : `v:${i}`)).join(' '),
    `${outDir}/v%v/index.m3u8`,
  );
  return args;
}

/** Poster (540 px wide) and a 16 px tiny preview for the blurred placeholder. */
function buildPosterArgs(input, posterPath, tinyPath, duration) {
  const at = duration > 1 ? '0.5' : '0';
  return [
    '-hide_banner', '-y', '-ss', at, '-i', input,
    '-frames:v', '1', '-vf', 'scale=540:-2', '-q:v', '4', posterPath,
    '-frames:v', '1', '-vf', 'scale=16:-2', '-q:v', '10', tinyPath,
  ];
}

module.exports = { LADDER, SEGMENT_SECONDS, parseProbe, chooseRungs, buildHlsArgs, buildPosterArgs };
