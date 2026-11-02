"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = require("node:test");
const strict_1 = __importDefault(require("node:assert/strict"));
const pool_logic_1 = require("../pool_logic");
(0, node_test_1.describe)('Pool Logic & Billiards Physics', () => {
    (0, node_test_1.it)('creates standard 16-ball regulation rack with 8-ball centered', () => {
        const rack = (0, pool_logic_1.createInitialRack)();
        strict_1.default.equal(rack.length, 16);
        const cue = rack.find((b) => b.id === 0);
        strict_1.default.equal(cue.x, 0.5);
        strict_1.default.equal(cue.y, 0.5);
        const eight = rack.find((b) => b.id === 8);
        strict_1.default.ok(!eight.pocketed);
        const solids = rack.filter((b) => (0, pool_logic_1.ballGroupOf)(b.id) === 'solids');
        const stripes = rack.filter((b) => (0, pool_logic_1.ballGroupOf)(b.id) === 'stripes');
        strict_1.default.equal(solids.length, 7);
        strict_1.default.equal(stripes.length, 7);
    });
    (0, node_test_1.it)('simulates break shot: cue hits apex ball and generates motion/keyframes', () => {
        const rack = (0, pool_logic_1.createInitialRack)();
        const result = (0, pool_logic_1.simulatePoolShot)(rack, {
            angle: 0.0, // Shoot straight at apex
            power: 0.85,
            spinX: 0.0,
            spinY: 0.2,
        }, {
            shooterUid: 'user_p1',
            p1Uid: 'user_p1',
            p2Uid: 'user_p2',
            tableState: 'open',
            p1Group: null,
            p2Group: null,
            isBreaking: true,
        });
        strict_1.default.equal(result.firstContactBallId, 1); // Apex ball #1
        strict_1.default.ok(result.keyframes.length > 5);
        strict_1.default.ok(result.durationMs > 500);
        strict_1.default.equal(result.tableState, 'open');
    });
    (0, node_test_1.it)('assigns solids to P1 and stripes to P2 when P1 legally pockets a solid on open table', () => {
        // Cue cuts solid #3 directly into corner pocket 0 (0,0) with a stop shot
        const balls = [
            { id: 0, x: 0.20, y: 0.20, vx: 0, vy: 0, pocketed: false },
            { id: 3, x: 0.10, y: 0.10, vx: 0, vy: 0, pocketed: false },
        ];
        const result = (0, pool_logic_1.simulatePoolShot)(balls, {
            angle: Math.atan2(0.10 - 0.20, 0.10 - 0.20),
            power: 0.25,
            spinX: 0.0,
            spinY: 0.0,
        }, {
            shooterUid: 'user_p1',
            p1Uid: 'user_p1',
            p2Uid: 'user_p2',
            tableState: 'open',
            p1Group: null,
            p2Group: null,
            isBreaking: false,
        });
        strict_1.default.equal(result.foul, null);
        strict_1.default.equal(result.p1Group, 'solids');
        strict_1.default.equal(result.p2Group, 'stripes');
        strict_1.default.equal(result.nextTurnUid, 'user_p1'); // Extra turn after potting legal ball!
    });
    (0, node_test_1.it)('awards ball-in-hand to opponent when shooter scratches cue ball', () => {
        var _a;
        const balls = [
            { id: 0, x: 0.95, y: 0.04, vx: 0, vy: 0, pocketed: false }, // Aim directly into top-center side pocket
            { id: 2, x: 1.5, y: 0.5, vx: 0, vy: 0, pocketed: false },
        ];
        const result = (0, pool_logic_1.simulatePoolShot)(balls, {
            angle: Math.atan2(0.0 - 0.04, 1.0 - 0.95),
            power: 0.6,
            spinX: 0.0,
            spinY: 0.0,
        }, {
            shooterUid: 'user_p1',
            p1Uid: 'user_p1',
            p2Uid: 'user_p2',
            tableState: 'solids',
            p1Group: 'solids',
            p2Group: 'stripes',
            isBreaking: false,
        });
        strict_1.default.ok(result.foul !== null);
        strict_1.default.equal((_a = result.foul) === null || _a === void 0 ? void 0 : _a.reason, 'scratch');
        strict_1.default.equal(result.ballInHand, true);
        strict_1.default.equal(result.nextTurnUid, 'user_p2');
    });
    (0, node_test_1.it)('declares shooter winner when pocketing 8-ball in called pocket after clearing group', () => {
        var _a;
        // P1 has 0 solids remaining, shooting 8-ball into corner pocket 0 (0,0)
        const balls = [
            { id: 0, x: 0.20, y: 0.20, vx: 0, vy: 0, pocketed: false },
            { id: 8, x: 0.10, y: 0.10, vx: 0, vy: 0, pocketed: false },
        ];
        const result = (0, pool_logic_1.simulatePoolShot)(balls, {
            angle: Math.atan2(0.10 - 0.20, 0.10 - 0.20),
            power: 0.25,
            spinX: 0.0,
            spinY: 0.0,
            calledPocket: 0, // Called pocket #0
        }, {
            shooterUid: 'user_p1',
            p1Uid: 'user_p1',
            p2Uid: 'user_p2',
            tableState: 'solids',
            p1Group: 'solids',
            p2Group: 'stripes',
            isBreaking: false,
        });
        strict_1.default.equal(result.foul, null);
        strict_1.default.equal(result.winnerUid, 'user_p1');
        strict_1.default.ok((_a = result.winReason) === null || _a === void 0 ? void 0 : _a.includes('called pocket'));
    });
    (0, node_test_1.it)('declares opponent winner if 8-ball is pocketed early before clearing group', () => {
        var _a;
        // P1 still has solid #2 on table, but pockets 8-ball
        const balls = [
            { id: 0, x: 0.20, y: 0.20, vx: 0, vy: 0, pocketed: false },
            { id: 8, x: 0.10, y: 0.10, vx: 0, vy: 0, pocketed: false },
            { id: 2, x: 1.7, y: 0.8, vx: 0, vy: 0, pocketed: false }, // Remaining solid!
        ];
        const result = (0, pool_logic_1.simulatePoolShot)(balls, {
            angle: Math.atan2(0.10 - 0.20, 0.10 - 0.20),
            power: 0.25,
            spinX: 0.0,
            spinY: 0.0,
            calledPocket: 0,
        }, {
            shooterUid: 'user_p1',
            p1Uid: 'user_p1',
            p2Uid: 'user_p2',
            tableState: 'solids',
            p1Group: 'solids',
            p2Group: 'stripes',
            isBreaking: false,
        });
        strict_1.default.equal(result.winnerUid, 'user_p2');
        strict_1.default.ok((_a = result.winReason) === null || _a === void 0 ? void 0 : _a.includes('early'));
    });
});
//# sourceMappingURL=pool_logic.test.js.map