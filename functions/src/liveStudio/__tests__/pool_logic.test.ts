import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import {
  createInitialRack,
  simulatePoolShot,
  ballGroupOf,
  BallState,
} from '../pool_logic';

describe('Pool Logic & Billiards Physics', () => {
  it('creates standard 16-ball regulation rack with 8-ball centered', () => {
    const rack = createInitialRack();
    assert.equal(rack.length, 16);

    const cue = rack.find((b) => b.id === 0)!;
    assert.equal(cue.x, 0.5);
    assert.equal(cue.y, 0.5);

    const eight = rack.find((b) => b.id === 8)!;
    assert.ok(!eight.pocketed);

    const solids = rack.filter((b) => ballGroupOf(b.id) === 'solids');
    const stripes = rack.filter((b) => ballGroupOf(b.id) === 'stripes');
    assert.equal(solids.length, 7);
    assert.equal(stripes.length, 7);
  });

  it('simulates break shot: cue hits apex ball and generates motion/keyframes', () => {
    const rack = createInitialRack();
    const result = simulatePoolShot(
      rack,
      {
        angle: 0.0, // Shoot straight at apex
        power: 0.85,
        spinX: 0.0,
        spinY: 0.2,
      },
      {
        shooterUid: 'user_p1',
        p1Uid: 'user_p1',
        p2Uid: 'user_p2',
        tableState: 'open',
        p1Group: null,
        p2Group: null,
        isBreaking: true,
      },
    );

    assert.equal(result.firstContactBallId, 1); // Apex ball #1
    assert.ok(result.keyframes.length > 5);
    assert.ok(result.durationMs > 500);
    assert.equal(result.tableState, 'open');
  });

  it('assigns solids to P1 and stripes to P2 when P1 legally pockets a solid on open table', () => {
    // Cue cuts solid #3 directly into corner pocket 0 (0,0) with a stop shot
    const balls: BallState[] = [
      { id: 0, x: 0.20, y: 0.20, vx: 0, vy: 0, pocketed: false },
      { id: 3, x: 0.10, y: 0.10, vx: 0, vy: 0, pocketed: false },
    ];

    const result = simulatePoolShot(
      balls,
      {
        angle: Math.atan2(0.10 - 0.20, 0.10 - 0.20),
        power: 0.25,
        spinX: 0.0,
        spinY: 0.0,
      },
      {
        shooterUid: 'user_p1',
        p1Uid: 'user_p1',
        p2Uid: 'user_p2',
        tableState: 'open',
        p1Group: null,
        p2Group: null,
        isBreaking: false,
      },
    );

    assert.equal(result.foul, null);
    assert.equal(result.p1Group, 'solids');
    assert.equal(result.p2Group, 'stripes');
    assert.equal(result.nextTurnUid, 'user_p1'); // Extra turn after potting legal ball!
  });

  it('awards ball-in-hand to opponent when shooter scratches cue ball', () => {
    const balls: BallState[] = [
      { id: 0, x: 0.95, y: 0.04, vx: 0, vy: 0, pocketed: false }, // Aim directly into top-center side pocket
      { id: 2, x: 1.5, y: 0.5, vx: 0, vy: 0, pocketed: false },
    ];

    const result = simulatePoolShot(
      balls,
      {
        angle: Math.atan2(0.0 - 0.04, 1.0 - 0.95),
        power: 0.6,
        spinX: 0.0,
        spinY: 0.0,
      },
      {
        shooterUid: 'user_p1',
        p1Uid: 'user_p1',
        p2Uid: 'user_p2',
        tableState: 'solids',
        p1Group: 'solids',
        p2Group: 'stripes',
        isBreaking: false,
      },
    );

    assert.ok(result.foul !== null);
    assert.equal(result.foul?.reason, 'scratch');
    assert.equal(result.ballInHand, true);
    assert.equal(result.nextTurnUid, 'user_p2');
  });

  it('declares shooter winner when pocketing 8-ball in called pocket after clearing group', () => {
    // P1 has 0 solids remaining, shooting 8-ball into corner pocket 0 (0,0)
    const balls: BallState[] = [
      { id: 0, x: 0.20, y: 0.20, vx: 0, vy: 0, pocketed: false },
      { id: 8, x: 0.10, y: 0.10, vx: 0, vy: 0, pocketed: false },
    ];

    const result = simulatePoolShot(
      balls,
      {
        angle: Math.atan2(0.10 - 0.20, 0.10 - 0.20),
        power: 0.25,
        spinX: 0.0,
        spinY: 0.0,
        calledPocket: 0, // Called pocket #0
      },
      {
        shooterUid: 'user_p1',
        p1Uid: 'user_p1',
        p2Uid: 'user_p2',
        tableState: 'solids',
        p1Group: 'solids',
        p2Group: 'stripes',
        isBreaking: false,
      },
    );

    assert.equal(result.foul, null);
    assert.equal(result.winnerUid, 'user_p1');
    assert.ok(result.winReason?.includes('called pocket'));
  });

  it('declares opponent winner if 8-ball is pocketed early before clearing group', () => {
    // P1 still has solid #2 on table, but pockets 8-ball
    const balls: BallState[] = [
      { id: 0, x: 0.20, y: 0.20, vx: 0, vy: 0, pocketed: false },
      { id: 8, x: 0.10, y: 0.10, vx: 0, vy: 0, pocketed: false },
      { id: 2, x: 1.7, y: 0.8, vx: 0, vy: 0, pocketed: false }, // Remaining solid!
    ];

    const result = simulatePoolShot(
      balls,
      {
        angle: Math.atan2(0.10 - 0.20, 0.10 - 0.20),
        power: 0.25,
        spinX: 0.0,
        spinY: 0.0,
        calledPocket: 0,
      },
      {
        shooterUid: 'user_p1',
        p1Uid: 'user_p1',
        p2Uid: 'user_p2',
        tableState: 'solids',
        p1Group: 'solids',
        p2Group: 'stripes',
        isBreaking: false,
      },
    );

    assert.equal(result.winnerUid, 'user_p2');
    assert.ok(result.winReason?.includes('early'));
  });
});
