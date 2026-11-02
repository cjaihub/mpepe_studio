"use strict";
/**
 * LIVE STUDIO v2 — 8-Ball Billiards Physics & Regulation Rules Engine
 *
 * Deterministic, sub-stepped 2D continuous billiards simulation with:
 * - 16 balls (0: Cue, 1-7: Solids, 8: 8-Ball, 9-15: Stripes)
 * - Apex-on-foot-spot triangle rack
 * - Ball-ball elastic collisions with throw friction & restitution (0.94)
 * - 6-pocket capture geometry (4 corners + 2 sides)
 * - Cushion bounce with English / side spin (spinX) rebound angle transfer
 * - Cue-ball draw (backspin) & follow (topspin) post-impact deflection
 * - Full 8-ball rules: open table group assignment, legal break, fouls,
 *   ball-in-hand placement, called 8-ball pocket, and win/loss resolution.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.POCKETS = exports.SIDE_POCKET_RADIUS = exports.CORNER_POCKET_RADIUS = exports.BALL_DIAMETER = exports.BALL_RADIUS = exports.TABLE_HEIGHT = exports.TABLE_WIDTH = void 0;
exports.createInitialRack = createInitialRack;
exports.ballGroupOf = ballGroupOf;
exports.countRemainingGroupBalls = countRemainingGroupBalls;
exports.simulatePoolShot = simulatePoolShot;
exports.TABLE_WIDTH = 2.0;
exports.TABLE_HEIGHT = 1.0;
exports.BALL_RADIUS = 0.028;
exports.BALL_DIAMETER = exports.BALL_RADIUS * 2;
exports.CORNER_POCKET_RADIUS = 0.048;
exports.SIDE_POCKET_RADIUS = 0.052;
exports.POCKETS = [
    { id: 0, x: 0.0, y: 0.0, isSide: false },
    { id: 1, x: 1.0, y: 0.0, isSide: true },
    { id: 2, x: 2.0, y: 0.0, isSide: false },
    { id: 3, x: 2.0, y: 1.0, isSide: false },
    { id: 4, x: 1.0, y: 1.0, isSide: true },
    { id: 5, x: 0.0, y: 1.0, isSide: false },
];
/** Standard regulation triangle rack with 8-ball centered and solid/stripe opposite corners. */
function createInitialRack() {
    const balls = [];
    // 0: Cue ball in kitchen (head spot)
    balls.push({
        id: 0,
        x: 0.5,
        y: 0.5,
        vx: 0,
        vy: 0,
        pocketed: false,
    });
    // Apex on foot spot
    const footX = 1.45;
    const footY = 0.5;
    const dx = exports.BALL_RADIUS * Math.sqrt(3) + 0.0008;
    const dy = exports.BALL_DIAMETER + 0.0008;
    // Standard official 8-ball rack configuration
    const rackPattern = [
        [1], // Row 0: Apex (Solid)
        [9, 2], // Row 1: Stripe, Solid
        [3, 8, 10], // Row 2: Solid, 8-BALL in center, Stripe
        [11, 4, 12, 5], // Row 3
        [6, 13, 7, 14, 15], // Row 4: Corners: 6 (Solid), 15 (Stripe)
    ];
    for (let row = 0; row < rackPattern.length; row++) {
        const rowBalls = rackPattern[row];
        const rowX = footX + row * dx;
        const startY = footY - (row * dy) / 2;
        for (let col = 0; col < rowBalls.length; col++) {
            const id = rowBalls[col];
            const y = startY + col * dy;
            balls.push({
                id,
                x: rowX,
                y,
                vx: 0,
                vy: 0,
                pocketed: false,
            });
        }
    }
    // Sort by id 0..15
    return balls.sort((a, b) => a.id - b.id);
}
/** Group classifier: 1-7 = solids, 8 = 8-ball, 9-15 = stripes */
function ballGroupOf(id) {
    if (id === 0)
        return 'cue';
    if (id === 8)
        return '8ball';
    return id <= 7 ? 'solids' : 'stripes';
}
/** Check if player has cleared all remaining balls of their group */
function countRemainingGroupBalls(balls, group) {
    return balls.filter((b) => !b.pocketed && ballGroupOf(b.id) === group).length;
}
/**
 * Runs deterministic 2D continuous sub-stepped physics simulation of a pool shot.
 */
function simulatePoolShot(currentBalls, input, context) {
    // Deep clone balls
    const balls = currentBalls.map((b) => (Object.assign({}, b)));
    const cue = balls.find((b) => b.id === 0);
    // Ball-in-hand placement validation
    if (input.cueBallPlacement && cue.pocketed) {
        cue.pocketed = false;
        cue.x = Math.max(exports.BALL_RADIUS * 1.5, Math.min(exports.TABLE_WIDTH - exports.BALL_RADIUS * 1.5, input.cueBallPlacement.x));
        cue.y = Math.max(exports.BALL_RADIUS * 1.5, Math.min(exports.TABLE_HEIGHT - exports.BALL_RADIUS * 1.5, input.cueBallPlacement.y));
    }
    else if (input.cueBallPlacement && !cue.pocketed) {
        cue.x = Math.max(exports.BALL_RADIUS * 1.5, Math.min(exports.TABLE_WIDTH - exports.BALL_RADIUS * 1.5, input.cueBallPlacement.x));
        cue.y = Math.max(exports.BALL_RADIUS * 1.5, Math.min(exports.TABLE_HEIGHT - exports.BALL_RADIUS * 1.5, input.cueBallPlacement.y));
    }
    // Apply cue impulse
    const clampedPower = Math.max(0.05, Math.min(1.0, input.power));
    const maxSpeed = 13.5; // m/s equivalent in normalized space
    const initialSpeed = clampedPower * maxSpeed;
    cue.vx = Math.cos(input.angle) * initialSpeed;
    cue.vy = Math.sin(input.angle) * initialSpeed;
    let spinX = Math.max(-1.0, Math.min(1.0, input.spinX)); // Side english
    let spinY = Math.max(-1.0, Math.min(1.0, input.spinY)); // Follow / Draw
    const dt = 1 / 120; // 120Hz fixed physics step for deterministic simulation
    const subSteps = 4; // Sub-steps per frame to prevent high-speed tunneling
    const subDt = dt / subSteps;
    const maxSteps = 1600; // ~13.3 seconds max
    const rollingFriction = 0.42;
    const ballRestitution = 0.94;
    const railRestitution = 0.80;
    const minSpeedThreshold = 0.006;
    const pocketed = [];
    const keyframes = [];
    let firstContactBallId = null;
    let railsHitAfterContact = 0;
    let numberedBallsHitRailsOnBreak = 0;
    const numberedHitRails = new Set();
    const minX = exports.BALL_RADIUS;
    const maxX = exports.TABLE_WIDTH - exports.BALL_RADIUS;
    const minY = exports.BALL_RADIUS;
    const maxY = exports.TABLE_HEIGHT - exports.BALL_RADIUS;
    for (let step = 0; step < maxSteps; step++) {
        const tMs = Math.round(step * dt * 1000);
        // Record keyframe every 4 steps (30fps) for network broadcast & smooth rendering
        if (step % 4 === 0) {
            keyframes.push({
                tMs,
                balls: balls.map((b) => ({ id: b.id, x: b.x, y: b.y, pocketed: b.pocketed })),
            });
        }
        let anyMoving = false;
        // Sub-stepped physics integration
        for (let sub = 0; sub < subSteps; sub++) {
            // 1. Move balls and apply table cloth friction
            for (const b of balls) {
                if (b.pocketed)
                    continue;
                const speed = Math.hypot(b.vx, b.vy);
                if (speed > minSpeedThreshold) {
                    anyMoving = true;
                    b.x += b.vx * subDt;
                    b.y += b.vy * subDt;
                    // Friction deceleration
                    const decel = rollingFriction * subDt;
                    const newSpeed = Math.max(0, speed - decel);
                    const factor = speed > 0 ? newSpeed / speed : 0;
                    b.vx *= factor;
                    b.vy *= factor;
                    // Pocket check
                    for (const p of exports.POCKETS) {
                        const pr = p.isSide ? exports.SIDE_POCKET_RADIUS : exports.CORNER_POCKET_RADIUS;
                        const distSq = (b.x - p.x) * (b.x - p.x) + (b.y - p.y) * (b.y - p.y);
                        if (distSq <= pr * pr) {
                            b.pocketed = true;
                            b.pocketId = p.id;
                            b.vx = 0;
                            b.vy = 0;
                            pocketed.push({ ballId: b.id, pocketId: p.id, tMs });
                            break;
                        }
                    }
                }
                else {
                    b.vx = 0;
                    b.vy = 0;
                }
            }
            // 2. Ball-to-ball collisions
            for (let i = 0; i < balls.length; i++) {
                const b1 = balls[i];
                if (b1.pocketed)
                    continue;
                for (let j = i + 1; j < balls.length; j++) {
                    const b2 = balls[j];
                    if (b2.pocketed)
                        continue;
                    const dx = b2.x - b1.x;
                    const dy = b2.y - b1.y;
                    const distSq = dx * dx + dy * dy;
                    const minDist = exports.BALL_DIAMETER;
                    if (distSq < minDist * minDist && distSq > 0.000001) {
                        const dist = Math.sqrt(distSq);
                        const nx = dx / dist;
                        const ny = dy / dist;
                        // Separate overlapping balls
                        const overlap = (minDist - dist) * 0.501;
                        b1.x -= nx * overlap;
                        b1.y -= ny * overlap;
                        b2.x += nx * overlap;
                        b2.y += ny * overlap;
                        // Relative velocity
                        const kx = b1.vx - b2.vx;
                        const ky = b1.vy - b2.vy;
                        const p = 2 * (nx * kx + ny * ky) / 2; // Equal mass
                        if (p > 0) {
                            b1.vx -= p * nx * ballRestitution;
                            b1.vy -= p * ny * ballRestitution;
                            b2.vx += p * nx * ballRestitution;
                            b2.vy += p * ny * ballRestitution;
                            // Track cue ball first contact
                            if (b1.id === 0 && firstContactBallId === null) {
                                firstContactBallId = b2.id;
                                if (Math.abs(spinY) > 0.05) {
                                    const spinImpulse = spinY * clampedPower * 3.5;
                                    b1.vx += Math.cos(input.angle) * spinImpulse;
                                    b1.vy += Math.sin(input.angle) * spinImpulse;
                                    spinY *= 0.3;
                                }
                            }
                            else if (b2.id === 0 && firstContactBallId === null) {
                                firstContactBallId = b1.id;
                                if (Math.abs(spinY) > 0.05) {
                                    const spinImpulse = spinY * clampedPower * 3.5;
                                    b2.vx += Math.cos(input.angle) * spinImpulse;
                                    b2.vy += Math.sin(input.angle) * spinImpulse;
                                    spinY *= 0.3;
                                }
                            }
                        }
                    }
                }
            }
            // 3. Ball-to-cushion rail collisions
            for (const b of balls) {
                if (b.pocketed)
                    continue;
                let nearPocket = false;
                for (const p of exports.POCKETS) {
                    const pr = (p.isSide ? exports.SIDE_POCKET_RADIUS : exports.CORNER_POCKET_RADIUS) * 1.35;
                    if ((b.x - p.x) * (b.x - p.x) + (b.y - p.y) * (b.y - p.y) < pr * pr) {
                        nearPocket = true;
                        break;
                    }
                }
                if (nearPocket)
                    continue;
                let hitRail = false;
                // Left rail
                if (b.x < minX) {
                    b.x = minX;
                    b.vx = -b.vx * railRestitution;
                    if (b.id === 0 && Math.abs(spinX) > 0.05) {
                        b.vy += spinX * 1.2;
                        spinX *= 0.6;
                    }
                    hitRail = true;
                }
                // Right rail
                else if (b.x > maxX) {
                    b.x = maxX;
                    b.vx = -b.vx * railRestitution;
                    if (b.id === 0 && Math.abs(spinX) > 0.05) {
                        b.vy -= spinX * 1.2;
                        spinX *= 0.6;
                    }
                    hitRail = true;
                }
                // Top rail
                if (b.y < minY) {
                    b.y = minY;
                    b.vy = -b.vy * railRestitution;
                    if (b.id === 0 && Math.abs(spinX) > 0.05) {
                        b.vx -= spinX * 1.2;
                        spinX *= 0.6;
                    }
                    hitRail = true;
                }
                // Bottom rail
                else if (b.y > maxY) {
                    b.y = maxY;
                    b.vy = -b.vy * railRestitution;
                    if (b.id === 0 && Math.abs(spinX) > 0.05) {
                        b.vx -= spinX * 1.2;
                        spinX *= 0.6;
                    }
                    hitRail = true;
                }
                if (hitRail) {
                    if (context.isBreaking && b.id > 0) {
                        numberedHitRails.add(b.id);
                    }
                    else if (firstContactBallId !== null) {
                        railsHitAfterContact++;
                    }
                }
            }
        }
        if (!anyMoving && step > 10) {
            break;
        }
    }
    // Ensure last resting keyframe is recorded
    keyframes.push({
        tMs: Math.round(maxSteps * dt * 1000),
        balls: balls.map((b) => ({ id: b.id, x: b.x, y: b.y, pocketed: b.pocketed })),
    });
    numberedBallsHitRailsOnBreak = numberedHitRails.size;
    // ──────────────────────────────────────────────────────────────────────────
    // 8-Ball Regulation Rules Arbiter
    // ──────────────────────────────────────────────────────────────────────────
    const isP1 = context.shooterUid === context.p1Uid;
    const opponentUid = isP1 ? context.p2Uid : context.p1Uid;
    let shooterGroup = isP1 ? context.p1Group : context.p2Group;
    let tableState = context.tableState;
    let p1Group = context.p1Group;
    let p2Group = context.p2Group;
    const cueScratch = pocketed.some((p) => p.ballId === 0);
    const eightBallPocketed = pocketed.some((p) => p.ballId === 8);
    const eightBallEvent = pocketed.find((p) => p.ballId === 8);
    let foul = null;
    let winnerUid = null;
    let winReason = null;
    let extraTurn = false;
    let ballInHand = false;
    let ballInHandKitchenOnly = false;
    // 1. Break Shot Evaluation
    if (context.isBreaking) {
        const numberedPocketed = pocketed.filter((p) => p.ballId > 0 && p.ballId !== 8).length;
        const legalBreak = numberedPocketed >= 1 || numberedBallsHitRailsOnBreak >= 4;
        if (eightBallPocketed) {
            // 8-ball pocketed on break: re-spot 8-ball on foot spot
            const eightBall = balls.find((b) => b.id === 8);
            eightBall.pocketed = false;
            eightBall.x = 1.45;
            eightBall.y = 0.5;
            eightBall.vx = 0;
            eightBall.vy = 0;
            const idx = pocketed.findIndex((p) => p.ballId === 8);
            if (idx >= 0)
                pocketed.splice(idx, 1);
        }
        if (cueScratch) {
            foul = { reason: 'scratch', message: 'Scratch on break — opponent gets ball in hand behind headstring.' };
            ballInHand = true;
            ballInHandKitchenOnly = true;
        }
        else if (!legalBreak) {
            foul = { reason: 'illegal_break', message: 'Illegal break — fewer than 4 balls contacted cushions.' };
            ballInHand = true;
            ballInHandKitchenOnly = true;
        }
        else if (numberedPocketed > 0) {
            // Table remains OPEN after the break even if balls were pocketed
            extraTurn = true;
        }
    }
    // 2. Normal Shot Evaluation
    else {
        // Check Cue Scratch
        if (cueScratch) {
            foul = { reason: 'scratch', message: 'Scratch — Cue ball pocketed.' };
            ballInHand = true;
        }
        // Check First Contact
        else if (firstContactBallId === null) {
            foul = { reason: 'wrong_group_first', message: 'Foul — Cue ball did not contact any ball.' };
            ballInHand = true;
        }
        else {
            const contactGroup = ballGroupOf(firstContactBallId);
            const shooterRemaining = shooterGroup ? countRemainingGroupBalls(balls, shooterGroup) : 7;
            if (tableState === 'open') {
                // Table is open: cue cannot hit 8-ball first
                if (contactGroup === '8ball') {
                    foul = { reason: 'wrong_group_first', message: 'Foul — Cannot hit 8-ball first while table is open.' };
                    ballInHand = true;
                }
            }
            else {
                // Table has groups assigned
                if (shooterRemaining > 0) {
                    if (contactGroup !== shooterGroup) {
                        foul = {
                            reason: 'wrong_group_first',
                            message: `Foul — Did not hit a ${shooterGroup} ball first.`,
                        };
                        ballInHand = true;
                    }
                }
                else {
                    // On 8-ball: must hit 8-ball first!
                    if (contactGroup !== '8ball') {
                        foul = { reason: 'wrong_group_first', message: 'Foul — Must hit the 8-ball first when on the 8.' };
                        ballInHand = true;
                    }
                }
            }
            // Check cushion contact after hit (if nothing pocketed)
            if (!foul && pocketed.length === 0 && railsHitAfterContact === 0) {
                foul = {
                    reason: 'no_rail_after_contact',
                    message: 'Foul — No ball contacted a cushion after contact.',
                };
                ballInHand = true;
            }
        }
        // 3. 8-Ball Pocketing Resolution
        if (eightBallPocketed && eightBallEvent) {
            const shooterRemaining = shooterGroup ? countRemainingGroupBalls(balls, shooterGroup) : 7;
            if (cueScratch) {
                winnerUid = opponentUid;
                winReason = 'Opponent pocketed the 8-ball and scratched.';
            }
            else if (tableState === 'open' || shooterRemaining > 0) {
                winnerUid = opponentUid;
                winReason = 'Opponent pocketed the 8-ball early before clearing their group.';
            }
            else if (foul) {
                winnerUid = opponentUid;
                winReason = 'Opponent fouled while pocketing the 8-ball.';
            }
            else if (input.calledPocket !== undefined && input.calledPocket !== eightBallEvent.pocketId) {
                winnerUid = opponentUid;
                winReason = `Opponent pocketed the 8-ball in pocket #${eightBallEvent.pocketId + 1} instead of called pocket #${input.calledPocket + 1}.`;
            }
            else {
                winnerUid = context.shooterUid;
                winReason = 'Legally pocketed the 8-ball in the called pocket!';
            }
        }
        // 4. Open Table Group Assignment (post-break)
        if (!foul && tableState === 'open' && !eightBallPocketed) {
            const legalPockets = pocketed.filter((p) => p.ballId > 0 && p.ballId !== 8);
            if (legalPockets.length > 0) {
                const firstPotGroup = ballGroupOf(legalPockets[0].ballId);
                const otherGroup = firstPotGroup === 'solids' ? 'stripes' : 'solids';
                if (isP1) {
                    p1Group = firstPotGroup;
                    p2Group = otherGroup;
                }
                else {
                    p2Group = firstPotGroup;
                    p1Group = otherGroup;
                }
                tableState = firstPotGroup;
                shooterGroup = firstPotGroup;
                extraTurn = true;
            }
        }
        else if (!foul && shooterGroup && !eightBallPocketed) {
            // Check if shooter legally pocketed at least one ball of their own group
            const myPockets = pocketed.filter((p) => ballGroupOf(p.ballId) === shooterGroup);
            if (myPockets.length > 0) {
                extraTurn = true;
            }
        }
    }
    // If cue ball scratched, reset its position in kitchen for next shot
    if (cueScratch) {
        const cueBall = balls.find((b) => b.id === 0);
        cueBall.pocketed = false;
        cueBall.x = 0.5;
        cueBall.y = 0.5;
        cueBall.vx = 0;
        cueBall.vy = 0;
    }
    const nextTurnUid = winnerUid ? context.shooterUid : extraTurn && !foul ? context.shooterUid : opponentUid;
    return {
        finalBalls: balls,
        pocketed,
        foul,
        tableState,
        p1Group,
        p2Group,
        nextTurnUid,
        ballInHand: ballInHand || !!foul,
        ballInHandKitchenOnly,
        winnerUid,
        winReason,
        durationMs: keyframes.length > 0 ? keyframes[keyframes.length - 1].tMs : 3000,
        keyframes,
        firstContactBallId,
        railsHitAfterContact,
    };
}
//# sourceMappingURL=pool_logic.js.map