"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.lsPool = void 0;
/**
 * LIVE STUDIO v2 — Interactive Multiplayer 8-Ball Billiards (`lsPool`).
 *
 * Operations:
 *  - `open`: Host/co-host opens live billiards arena (best-of series, challenger slots).
 *  - `join`: Viewer or guest takes P2 player seat (auto-promotes camera to live stage).
 *  - `aim`: Active shooter broadcasts cue telemetry (angle, power, spin) live to all viewers.
 *  - `placeCueBall`: Active shooter with ball-in-hand repositions the cue ball.
 *  - `callPocket`: Active shooter calls 8-ball target pocket (0..5).
 *  - `shoot`: Fires authoritative physics simulation, keyframes & regulation rules.
 *  - `timeout`: Turn timer expiration switch with ball-in-hand.
 *  - `rematch`: Re-racks table for next frame in best-of series.
 *  - `leave`: Player resigns or leaves; queue promotes next challenger.
 *  - `close`: Host closes the live billiards arena.
 */
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-admin/firestore");
const livekit_server_sdk_1 = require("livekit-server-sdk");
const contracts_1 = require("./contracts");
const shared_1 = require("./shared");
const pool_logic_1 = require("./pool_logic");
const poolDocPath = (streamId) => `${contracts_1.Paths.streams}/${streamId}/studio/pool`;
async function userProfile(uid) {
    try {
        const snap = await (0, shared_1.db)().doc(`users/${uid}`).get();
        if (snap.exists) {
            const d = snap.data();
            const name = d.displayName || d.username || d.name || 'Player';
            const avatarUrl = d.photoURL || d.avatarUrl || '';
            return { name, avatarUrl };
        }
    }
    catch (e) {
        console.warn(`[lsPool] failed to load profile for ${uid}:`, e);
    }
    return { name: 'Player', avatarUrl: '' };
}
async function promoteToStageGuest(streamId, uid, name, avatarUrl) {
    try {
        const memberRef = (0, shared_1.db)().doc(`${contracts_1.Paths.members(streamId)}/${uid}`);
        await memberRef.set({
            uid,
            role: 'guest',
            name,
            avatarUrl,
            cameraOn: true,
            micOn: true,
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        }, { merge: true });
        await (0, shared_1.roomService)().updateParticipant((0, shared_1.roomName)(streamId), uid, {
            attributes: { role: 'guest' },
            permission: {
                canSubscribe: true,
                canPublish: true,
                canPublishData: true,
                canPublishSources: [livekit_server_sdk_1.TrackSource.CAMERA, livekit_server_sdk_1.TrackSource.MICROPHONE],
            },
        });
    }
    catch (e) {
        console.warn(`[lsPool] promoteToStageGuest failed for ${uid}:`, e.message);
    }
}
exports.lsPool = (0, https_1.onCall)({ secrets: shared_1.LIVEKIT_SECRETS }, async (req) => {
    var _a;
    const uid = (0, shared_1.requireUid)(req);
    const data = (req.data && typeof req.data === 'object' ? req.data : {});
    const streamId = (0, shared_1.requireString)(data.streamId, 'streamId', 128);
    const op = (0, shared_1.requireString)(data.op, 'op', 32);
    const state = await (0, shared_1.loadState)(streamId);
    (0, shared_1.requireLive)(state);
    if (await (0, shared_1.isBlocked)(streamId, uid)) {
        throw new https_1.HttpsError('permission-denied', 'You are blocked from this live.');
    }
    const poolRef = (0, shared_1.db)().doc(poolDocPath(streamId));
    const now = Date.now();
    // ─────────────────────────────────────────────────────────────────────────
    // OP: OPEN (Host or CoHost opens the pool arena)
    // ─────────────────────────────────────────────────────────────────────────
    if (op === 'open') {
        await (0, shared_1.requireRole)(streamId, uid, ['host', 'coHost'], state);
        await (0, shared_1.rateLimit)(streamId, uid, 'pool_admin', 10, 60000);
        const bestOfRaw = typeof data.bestOf === 'number' ? data.bestOf : 1;
        const bestOf = Math.min(Math.max(bestOfRaw, 1), 7);
        const targetP2Uid = typeof data.p2Uid === 'string' && data.p2Uid.trim() ? data.p2Uid.trim() : null;
        const p1Prof = await userProfile(uid);
        let p2Prof = targetP2Uid ? await userProfile(targetP2Uid) : null;
        if (targetP2Uid && p2Prof) {
            await promoteToStageGuest(streamId, targetP2Uid, p2Prof.name, p2Prof.avatarUrl);
        }
        const initialMatch = {
            v: 1,
            status: targetP2Uid ? 'in_progress' : 'waiting',
            bestOf,
            rackNumber: 1,
            tableState: 'open',
            p1Uid: uid,
            p1Name: p1Prof.name,
            p1Avatar: p1Prof.avatarUrl,
            p1Score: 0,
            p1Group: null,
            p2Uid: targetP2Uid,
            p2Name: p2Prof ? p2Prof.name : null,
            p2Avatar: p2Prof ? p2Prof.avatarUrl : null,
            p2Score: 0,
            p2Group: null,
            shooterUid: uid,
            balls: (0, pool_logic_1.createInitialRack)(),
            ballInHand: false,
            ballInHandKitchenOnly: false,
            calledPocket: null,
            turnEndsAtMs: now + 45000,
            lastShot: null,
            winnerUid: null,
            winReason: null,
            challengerQueue: [],
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        };
        await poolRef.set(initialMatch);
        await (0, shared_1.broadcast)(streamId, 'studio.pool', {
            v: 1,
            type: 'pool.open',
            pool: initialMatch,
            ts: now,
        });
        return { ok: true, pool: initialMatch };
    }
    // ─────────────────────────────────────────────────────────────────────────
    // Read existing pool match state for ongoing operations
    // ─────────────────────────────────────────────────────────────────────────
    const poolSnap = await poolRef.get();
    if (!poolSnap.exists) {
        throw new https_1.HttpsError('not-found', 'No pool game is currently active on this live.');
    }
    const match = poolSnap.data();
    if (match.status === 'closed') {
        throw new https_1.HttpsError('failed-precondition', 'The pool game has already ended.');
    }
    // ─────────────────────────────────────────────────────────────────────────
    // OP: JOIN (Viewer or guest joins as Player 2 or enters challenger queue)
    // ─────────────────────────────────────────────────────────────────────────
    if (op === 'join') {
        await (0, shared_1.rateLimit)(streamId, uid, 'pool_join', 6, 10000);
        const prof = await userProfile(uid);
        let updatedMatch = Object.assign({}, match);
        let joinedAsP2 = false;
        if (!match.p2Uid || match.status === 'waiting') {
            if (match.p1Uid === uid) {
                throw new https_1.HttpsError('invalid-argument', 'You are already Player 1.');
            }
            joinedAsP2 = true;
            updatedMatch.p2Uid = uid;
            updatedMatch.p2Name = prof.name;
            updatedMatch.p2Avatar = prof.avatarUrl;
            updatedMatch.status = 'in_progress';
            updatedMatch.turnEndsAtMs = now + 45000;
            updatedMatch.challengerQueue = (match.challengerQueue || []).filter((q) => q.uid !== uid);
            // Promote to stage guest so their live camera & audio streams activate!
            await promoteToStageGuest(streamId, uid, prof.name, prof.avatarUrl);
        }
        else {
            if (match.p1Uid === uid || match.p2Uid === uid) {
                throw new https_1.HttpsError('failed-precondition', 'You are already playing in this match.');
            }
            const queue = [...(match.challengerQueue || [])];
            if (!queue.some((q) => q.uid === uid)) {
                queue.push({ uid, name: prof.name, avatarUrl: prof.avatarUrl, joinedAt: now });
                updatedMatch.challengerQueue = queue;
            }
        }
        updatedMatch.updatedAt = firestore_1.FieldValue.serverTimestamp();
        await poolRef.set(updatedMatch);
        await (0, shared_1.broadcast)(streamId, 'studio.pool', {
            v: 1,
            type: joinedAsP2 ? 'pool.joined' : 'pool.queued',
            p2Uid: updatedMatch.p2Uid,
            p2Name: updatedMatch.p2Name,
            status: updatedMatch.status,
            challengerQueue: updatedMatch.challengerQueue,
            ts: now,
        });
        return { ok: true, joinedAsP2, pool: updatedMatch };
    }
    // ─────────────────────────────────────────────────────────────────────────
    // OP: AIM (Real-time live aiming telemetry broadcast)
    // ─────────────────────────────────────────────────────────────────────────
    if (op === 'aim') {
        if (match.shooterUid !== uid) {
            throw new https_1.HttpsError('permission-denied', 'It is not your turn to aim.');
        }
        const angle = Number(data.angle) || 0;
        const power = Math.max(0, Math.min(1, Number(data.power) || 0));
        const spinX = Math.max(-1, Math.min(1, Number(data.spinX) || 0));
        const spinY = Math.max(-1, Math.min(1, Number(data.spinY) || 0));
        const cueBallX = typeof data.cueBallX === 'number' ? data.cueBallX : undefined;
        const cueBallY = typeof data.cueBallY === 'number' ? data.cueBallY : undefined;
        // Fast lossy data broadcast over LiveKit so opponent & viewers see aim line in real time
        await (0, shared_1.broadcast)(streamId, 'studio.pool', {
            v: 1,
            type: 'pool.aim',
            shooterUid: uid,
            angle,
            power,
            spinX,
            spinY,
            cueBallX,
            cueBallY,
            ts: now,
        }, { lossy: true });
        return { ok: true };
    }
    // ─────────────────────────────────────────────────────────────────────────
    // OP: PLACE CUE BALL (Ball-in-hand placement)
    // ─────────────────────────────────────────────────────────────────────────
    if (op === 'placeCueBall') {
        if (match.shooterUid !== uid) {
            throw new https_1.HttpsError('permission-denied', 'It is not your turn.');
        }
        if (!match.ballInHand) {
            throw new https_1.HttpsError('failed-precondition', 'You do not have ball in hand.');
        }
        const x = Number(data.x);
        const y = Number(data.y);
        if (isNaN(x) || isNaN(y)) {
            throw new https_1.HttpsError('invalid-argument', 'Valid x and y coordinates are required.');
        }
        const minX = 0.05;
        const maxX = match.ballInHandKitchenOnly ? 0.50 : 1.95;
        const minY = 0.05;
        const maxY = 0.95;
        if (x < minX || x > maxX || y < minY || y > maxY) {
            throw new https_1.HttpsError('invalid-argument', match.ballInHandKitchenOnly
                ? 'Cue ball must be placed behind the headstring (kitchen).'
                : 'Cue ball must be within table playing boundaries.');
        }
        // Verify distance from any unpocketed object ball
        for (const b of match.balls) {
            if (b.id === 0 || b.pocketed)
                continue;
            const dx = b.x - x;
            const dy = b.y - y;
            if (dx * dx + dy * dy < (pool_logic_1.BALL_RADIUS * 2.05) ** 2) {
                throw new https_1.HttpsError('invalid-argument', 'Cannot place cue ball overlapping another ball.');
            }
        }
        const nextBalls = match.balls.map((b) => (b.id === 0 ? Object.assign(Object.assign({}, b), { x, y, vx: 0, vy: 0, pocketed: false }) : b));
        await poolRef.update({
            balls: nextBalls,
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        });
        await (0, shared_1.broadcast)(streamId, 'studio.pool', {
            v: 1,
            type: 'pool.cuePlaced',
            shooterUid: uid,
            x,
            y,
            ts: now,
        });
        return { ok: true, x, y };
    }
    // ─────────────────────────────────────────────────────────────────────────
    // OP: CALL POCKET (Call pocket for 8-ball)
    // ─────────────────────────────────────────────────────────────────────────
    if (op === 'callPocket') {
        if (match.shooterUid !== uid) {
            throw new https_1.HttpsError('permission-denied', 'It is not your turn.');
        }
        const pocketId = Number(data.pocketId);
        if (isNaN(pocketId) || pocketId < 0 || pocketId > 5) {
            throw new https_1.HttpsError('invalid-argument', 'pocketId must be 0 to 5.');
        }
        await poolRef.update({
            calledPocket: pocketId,
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        });
        await (0, shared_1.broadcast)(streamId, 'studio.pool', {
            v: 1,
            type: 'pool.calledPocket',
            shooterUid: uid,
            pocketId,
            ts: now,
        });
        return { ok: true, pocketId };
    }
    // ─────────────────────────────────────────────────────────────────────────
    // OP: SHOOT (Execute authoritative shot physics & rules)
    // ─────────────────────────────────────────────────────────────────────────
    if (op === 'shoot') {
        if (match.shooterUid !== uid) {
            throw new https_1.HttpsError('permission-denied', 'It is not your turn to shoot.');
        }
        if (match.status !== 'in_progress') {
            throw new https_1.HttpsError('failed-precondition', 'Game is not currently in progress.');
        }
        const angle = Number(data.angle);
        const power = Math.max(0.01, Math.min(1.0, Number(data.power) || 0.5));
        const spinX = Math.max(-1.0, Math.min(1.0, Number(data.spinX) || 0.0));
        const spinY = Math.max(-1.0, Math.min(1.0, Number(data.spinY) || 0.0));
        const calledPocket = typeof data.calledPocket === 'number' && data.calledPocket >= 0 && data.calledPocket <= 5
            ? data.calledPocket
            : (_a = match.calledPocket) !== null && _a !== void 0 ? _a : undefined;
        if (isNaN(angle)) {
            throw new https_1.HttpsError('invalid-argument', 'Valid shot angle is required.');
        }
        const isBreaking = match.balls.every((b) => b.id === 0 || !b.pocketed) && match.tableState === 'open';
        const input = {
            angle,
            power,
            spinX,
            spinY,
            calledPocket,
        };
        const simResult = (0, pool_logic_1.simulatePoolShot)(match.balls, input, {
            shooterUid: uid,
            p1Uid: match.p1Uid,
            p2Uid: match.p2Uid || '',
            tableState: match.tableState,
            p1Group: match.p1Group,
            p2Group: match.p2Group,
            isBreaking,
        });
        let nextStatus = 'in_progress';
        let p1Score = match.p1Score;
        let p2Score = match.p2Score;
        let winnerUid = simResult.winnerUid;
        let winReason = simResult.winReason;
        const gamesToWin = Math.ceil(match.bestOf / 2);
        if (winnerUid) {
            if (winnerUid === match.p1Uid) {
                p1Score++;
            }
            else {
                p2Score++;
            }
            if (p1Score >= gamesToWin || p2Score >= gamesToWin) {
                nextStatus = 'game_over';
            }
            else {
                // Frame finished, series continues
                nextStatus = 'game_over'; // Players can press rematch for next rack
            }
        }
        const lastShot = {
            angle,
            power,
            spinX,
            spinY,
            pocketed: simResult.pocketed,
            foul: simResult.foul,
            at: now,
        };
        const nextMatch = Object.assign(Object.assign({}, match), { status: nextStatus, tableState: simResult.tableState, p1Group: simResult.p1Group, p2Group: simResult.p2Group, p1Score,
            p2Score, balls: simResult.finalBalls, shooterUid: winnerUid ? match.shooterUid : simResult.nextTurnUid, ballInHand: simResult.ballInHand, ballInHandKitchenOnly: simResult.ballInHandKitchenOnly, calledPocket: null, turnEndsAtMs: now + 45000, lastShot,
            winnerUid,
            winReason, updatedAt: firestore_1.FieldValue.serverTimestamp() });
        await poolRef.set(nextMatch);
        // Reliable broadcast with full animation keyframes so everyone sees the shot play smoothly in lockstep!
        await (0, shared_1.broadcast)(streamId, 'studio.pool', {
            v: 1,
            type: 'pool.shot',
            shooterUid: uid,
            input,
            keyframes: simResult.keyframes,
            pocketed: simResult.pocketed,
            foul: simResult.foul,
            ballInHand: simResult.ballInHand,
            ballInHandKitchenOnly: simResult.ballInHandKitchenOnly,
            tableState: simResult.tableState,
            p1Group: simResult.p1Group,
            p2Group: simResult.p2Group,
            nextShooterUid: nextMatch.shooterUid,
            winnerUid,
            winReason,
            p1Score,
            p2Score,
            status: nextStatus,
            ts: now,
        }, { lossy: false });
        return {
            ok: true,
            result: {
                foul: simResult.foul,
                pocketed: simResult.pocketed,
                winnerUid,
                winReason,
                nextShooterUid: nextMatch.shooterUid,
                tableState: simResult.tableState,
                p1Group: simResult.p1Group,
                p2Group: simResult.p2Group,
            },
        };
    }
    // ─────────────────────────────────────────────────────────────────────────
    // OP: TIMEOUT (Turn clock expiration switch)
    // ─────────────────────────────────────────────────────────────────────────
    if (op === 'timeout') {
        if (match.status !== 'in_progress') {
            throw new https_1.HttpsError('failed-precondition', 'Game is not in progress.');
        }
        if (now < match.turnEndsAtMs) {
            throw new https_1.HttpsError('failed-precondition', 'Turn time has not expired yet.');
        }
        const nextShooter = match.shooterUid === match.p1Uid ? match.p2Uid || match.p1Uid : match.p1Uid;
        const timeoutMatch = Object.assign(Object.assign({}, match), { shooterUid: nextShooter, ballInHand: true, ballInHandKitchenOnly: false, turnEndsAtMs: now + 45000, updatedAt: firestore_1.FieldValue.serverTimestamp() });
        await poolRef.set(timeoutMatch);
        await (0, shared_1.broadcast)(streamId, 'studio.pool', {
            v: 1,
            type: 'pool.timeout',
            expiredShooterUid: match.shooterUid,
            nextShooterUid: nextShooter,
            ts: now,
        });
        return { ok: true, nextShooterUid: nextShooter };
    }
    // ─────────────────────────────────────────────────────────────────────────
    // OP: REMATCH (Re-rack balls for next rack in series)
    // ─────────────────────────────────────────────────────────────────────────
    if (op === 'rematch') {
        const isPlayer = uid === match.p1Uid || uid === match.p2Uid;
        const isHost = state.hostId === uid;
        if (!isPlayer && !isHost) {
            throw new https_1.HttpsError('permission-denied', 'Only players or the host can initiate a rematch.');
        }
        const nextBreaker = match.winnerUid || (match.shooterUid === match.p1Uid ? match.p2Uid || match.p1Uid : match.p1Uid);
        const freshRack = (0, pool_logic_1.createInitialRack)();
        const rematched = Object.assign(Object.assign({}, match), { status: match.p2Uid ? 'in_progress' : 'waiting', rackNumber: match.rackNumber + 1, tableState: 'open', p1Group: null, p2Group: null, balls: freshRack, shooterUid: nextBreaker, ballInHand: false, ballInHandKitchenOnly: false, calledPocket: null, turnEndsAtMs: now + 45000, lastShot: null, winnerUid: null, winReason: null, updatedAt: firestore_1.FieldValue.serverTimestamp() });
        await poolRef.set(rematched);
        await (0, shared_1.broadcast)(streamId, 'studio.pool', {
            v: 1,
            type: 'pool.rematch',
            rackNumber: rematched.rackNumber,
            shooterUid: nextBreaker,
            balls: freshRack,
            ts: now,
        });
        return { ok: true, pool: rematched };
    }
    // ─────────────────────────────────────────────────────────────────────────
    // OP: LEAVE (Player resigns or leaves; queue promotes next challenger)
    // ─────────────────────────────────────────────────────────────────────────
    if (op === 'leave') {
        let nextMatch = Object.assign({}, match);
        const queue = [...(match.challengerQueue || [])];
        if (uid === match.p2Uid) {
            if (queue.length > 0) {
                const nextUser = queue.shift();
                nextMatch.p2Uid = nextUser.uid;
                nextMatch.p2Name = nextUser.name;
                nextMatch.p2Avatar = nextUser.avatarUrl;
                nextMatch.challengerQueue = queue;
                nextMatch.balls = (0, pool_logic_1.createInitialRack)();
                nextMatch.tableState = 'open';
                nextMatch.p1Group = null;
                nextMatch.p2Group = null;
                nextMatch.shooterUid = match.p1Uid;
                nextMatch.status = 'in_progress';
                nextMatch.turnEndsAtMs = now + 45000;
                await promoteToStageGuest(streamId, nextUser.uid, nextUser.name, nextUser.avatarUrl);
            }
            else {
                nextMatch.p2Uid = null;
                nextMatch.p2Name = null;
                nextMatch.p2Avatar = null;
                nextMatch.status = 'waiting';
            }
        }
        else if (uid === match.p1Uid) {
            // P1 left: if P2 present, P2 becomes P1 and next in queue becomes P2
            if (match.p2Uid) {
                nextMatch.p1Uid = match.p2Uid;
                nextMatch.p1Name = match.p2Name || 'Player 1';
                nextMatch.p1Avatar = match.p2Avatar || '';
                nextMatch.p1Score = 0;
                nextMatch.p2Score = 0;
                if (queue.length > 0) {
                    const nextUser = queue.shift();
                    nextMatch.p2Uid = nextUser.uid;
                    nextMatch.p2Name = nextUser.name;
                    nextMatch.p2Avatar = nextUser.avatarUrl;
                    nextMatch.challengerQueue = queue;
                    await promoteToStageGuest(streamId, nextUser.uid, nextUser.name, nextUser.avatarUrl);
                }
                else {
                    nextMatch.p2Uid = null;
                    nextMatch.p2Name = null;
                    nextMatch.p2Avatar = null;
                    nextMatch.status = 'waiting';
                }
                nextMatch.balls = (0, pool_logic_1.createInitialRack)();
                nextMatch.tableState = 'open';
                nextMatch.p1Group = null;
                nextMatch.p2Group = null;
                nextMatch.shooterUid = nextMatch.p1Uid;
            }
            else {
                nextMatch.status = 'closed';
            }
        }
        else {
            // Remove from queue if they were queued
            nextMatch.challengerQueue = queue.filter((q) => q.uid !== uid);
        }
        nextMatch.updatedAt = firestore_1.FieldValue.serverTimestamp();
        await poolRef.set(nextMatch);
        await (0, shared_1.broadcast)(streamId, 'studio.pool', {
            v: 1,
            type: 'pool.leave',
            leavingUid: uid,
            pool: nextMatch,
            ts: now,
        });
        return { ok: true, pool: nextMatch };
    }
    // ─────────────────────────────────────────────────────────────────────────
    // OP: CLOSE (Host or CoHost closes the billiards table)
    // ─────────────────────────────────────────────────────────────────────────
    if (op === 'close') {
        await (0, shared_1.requireRole)(streamId, uid, ['host', 'coHost'], state);
        await poolRef.update({
            status: 'closed',
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        });
        await (0, shared_1.broadcast)(streamId, 'studio.pool', {
            v: 1,
            type: 'pool.closed',
            closedByUid: uid,
            ts: now,
        });
        return { ok: true };
    }
    throw new https_1.HttpsError('invalid-argument', `Unknown pool op: ${op}`);
});
//# sourceMappingURL=pool.js.map