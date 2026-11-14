#!/usr/bin/env node
/**
 * Upload an Android App Bundle to a Google Play track via the Play Developer API.
 *
 *   node tools/play/play_publish.cjs --aab build/app/outputs/bundle/release/app-release.aab \
 *     [--track internal|alpha|beta|production] [--status completed|draft] \
 *     [--notes "What's new"] [--priority 0-5] [--rollout 0.1]
 *
 * Auth: a Google Cloud service account JSON with access granted in Play Console
 * (Users and permissions → invite the service-account email → "Release to testing tracks"
 * and, only if you want it, "Release to production"). Path from
 * PLAY_SERVICE_ACCOUNT_JSON, default android/play-service-account.json (gitignored).
 *
 * Note: Google requires the very first bundle of a new app to be uploaded in
 * Play Console by hand; this script works for every upload after that.
 */
const fs = require('fs');
const path = require('path');
const { google } = require(path.join(__dirname, '../../functions/node_modules/googleapis'));

const PACKAGE = 'com.oneova.app';
const args = Object.fromEntries(
  process.argv.slice(2).reduce((acc, a, i, all) => {
    if (a.startsWith('--')) acc.push([a.slice(2), all[i + 1] && !all[i + 1].startsWith('--') ? all[i + 1] : 'true']);
    return acc;
  }, []),
);

const aab = args.aab;
const track = args.track || 'internal';
const status = args.status || 'completed';
const keyFile = process.env.PLAY_SERVICE_ACCOUNT_JSON || path.join(__dirname, '../../android/play-service-account.json');

if (!args['version-code'] && (!aab || !fs.existsSync(aab))) throw new Error(`AAB not found: ${aab}`);
if (!fs.existsSync(keyFile)) throw new Error(`Service account JSON not found: ${keyFile}`);
if (track === 'production' && args['confirm-production'] !== 'true') {
  throw new Error('Refusing to publish to production without --confirm-production.');
}

(async () => {
  const auth = new google.auth.GoogleAuth({ keyFile, scopes: ['https://www.googleapis.com/auth/androidpublisher'] });
  const play = google.androidpublisher({ version: 'v3', auth });

  const { data: edit } = await play.edits.insert({ packageName: PACKAGE });
  console.log(`edit ${edit.id}`);

  let versionCode = args['version-code'];
  if (!versionCode) {
    const { data: bundle } = await play.edits.bundles.upload({
      packageName: PACKAGE,
      editId: edit.id,
      media: { mimeType: 'application/octet-stream', body: fs.createReadStream(aab) },
    });
    console.log(`uploaded versionCode ${bundle.versionCode} (sha256 ${bundle.sha256})`);
    versionCode = bundle.versionCode;
  } else {
    console.log(`using existing versionCode ${versionCode}`);
  }

  const release = {
    versionCodes: [String(versionCode)],
    status: args.rollout ? 'inProgress' : status,
    ...(args.rollout ? { userFraction: Number(args.rollout) } : {}),
    ...(args.priority ? { inAppUpdatePriority: Number(args.priority) } : {}),
    ...(args.notes ? { releaseNotes: [{ language: 'en-US', text: String(args.notes).slice(0, 500) }] } : {}),
  };
  await play.edits.tracks.update({
    packageName: PACKAGE,
    editId: edit.id,
    track,
    requestBody: { track, releases: [release] },
  });

  // --not-sent-for-review: needed while other Console changes are waiting; send them from Publishing overview.
  let committed;
  try {
    ({ data: committed } = await play.edits.commit({
      packageName: PACKAGE,
      editId: edit.id,
      ...(args['not-sent-for-review'] ? { changesNotSentForReview: true } : {}),
    }));
  } catch (commitErr) {
    const msg = JSON.stringify(commitErr?.errors || commitErr?.message || commitErr);
    if (!args['not-sent-for-review'] && msg.includes('changesNotSentForReview')) {
      console.log('retrying commit with changesNotSentForReview: true...');
      ({ data: committed } = await play.edits.commit({
        packageName: PACKAGE,
        editId: edit.id,
        changesNotSentForReview: true,
      }));
    } else {
      throw commitErr;
    }
  }
  console.log(`committed edit ${committed.id}: versionCode ${versionCode} → ${track} (${release.status})`);
})().catch((e) => {
  console.error(e.errors || e.message || e);
  process.exit(1);
});
