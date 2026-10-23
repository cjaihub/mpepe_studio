/**
 * Server-side smoke test for Live Studio v2 against a LiveKit server
 * (default: the local dev server from docker-compose.dev.yml).
 *
 *   npm --prefix functions run test:livestudio   # builds .ls-build first
 *   node tools/livekit/smoke_server.js
 *
 * Uses the real role→grant mapping from functions/src/liveStudio/media_logic.ts
 * and checks: room create/list, token claims per role, data send API,
 * participant permission update API, room delete.
 */
const path = require('path');
const { createRequire } = require('module');
const fnRequire = createRequire(path.join(__dirname, '../../functions/package.json'));
const { RoomServiceClient, AccessToken, TokenVerifier, DataPacket_Kind, TrackSource } = fnRequire('livekit-server-sdk');
// Same mapping lsToken applies (functions/src/liveStudio/media.ts).
const SOURCE = { camera: TrackSource.CAMERA, microphone: TrackSource.MICROPHONE, screen_share: TrackSource.SCREEN_SHARE };
const { grantForRole, TOKEN_TTL_SECONDS } = fnRequire('./.ls-build/liveStudio/media_logic.js');

const URL = process.env.LIVEKIT_HTTP || 'http://127.0.0.1:7880';
const KEY = process.env.LIVEKIT_API_KEY || 'devkey';
const SECRET = process.env.LIVEKIT_API_SECRET || 'secret';

let failures = 0;
const check = (ok, label) => { console.log(`${ok ? 'PASS' : 'FAIL'}  ${label}`); if (!ok) failures++; };

(async () => {
  const svc = new RoomServiceClient(URL, KEY, SECRET);
  const room = `studio_smoke_${Date.now()}`;

  await svc.createRoom({ name: room, emptyTimeout: 60 });
  const rooms = await svc.listRooms([room]);
  check(rooms.length === 1 && rooms[0].name === room, 'createRoom + listRooms');

  const verifier = new TokenVerifier(KEY, SECRET);
  for (const role of ['host', 'coHost', 'guest', 'viewer']) {
    const at = new AccessToken(KEY, SECRET, { identity: `u_${role}`, name: role, ttl: TOKEN_TTL_SECONDS });
    const g = grantForRole(role, room);
    at.addGrant({ ...g, canPublishSources: g.canPublishSources.map((x) => SOURCE[x]) });
    const claims = await verifier.verify(await at.toJwt());
    const v = claims.video || {};
    const expectPublish = role !== 'viewer';
    check(v.room === room && v.roomJoin === true && v.canSubscribe === true, `${role}: joins + subscribes`);
    check(Boolean(v.canPublish) === expectPublish, `${role}: canPublish=${expectPublish}`);
    check(v.canPublishData === false, `${role}: canPublishData=false`);
    const srcs = (v.canPublishSources || []).slice().sort().join(',');
    check(expectPublish ? srcs === 'camera,microphone,screen_share' : srcs === '', `${role}: sources [${srcs}]`);
  }

  // Server → room data fan-out (no participants yet: must still be accepted).
  try {
    await svc.sendData(room, new TextEncoder().encode(JSON.stringify({ v: 1, type: 'counts', viewers: 0, participants: 0, ts: Date.now() })),
      DataPacket_Kind.LOSSY, { topic: 'counts' });
    check(true, 'sendData accepted');
  } catch (e) {
    check(false, `sendData: ${e.message}`);
  }

  await svc.updateRoomMetadata(room, JSON.stringify({ studioVersion: 2 }));
  const [r2] = await svc.listRooms([room]);
  check(r2 && JSON.parse(r2.metadata).studioVersion === 2, 'updateRoomMetadata');

  await svc.deleteRoom(room);
  check((await svc.listRooms([room])).length === 0, 'deleteRoom');

  console.log(failures ? `\n${failures} FAILED` : '\nALL PASSED');
  process.exit(failures ? 1 : 0);
})().catch((e) => { console.error('ERROR', e); process.exit(2); });
