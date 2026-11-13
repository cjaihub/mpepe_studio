"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
const node_test_1 = require("node:test");
const assert = __importStar(require("node:assert/strict"));
const outbox_1 = require("../outbox");
(0, node_test_1.test)('backoff doubles from 1 minute and caps at 6 hours', () => {
    assert.equal((0, outbox_1.nextDelayMs)(1), 60000);
    assert.equal((0, outbox_1.nextDelayMs)(3), 240000);
    assert.equal((0, outbox_1.nextDelayMs)(30), 6 * 3600000);
});
(0, node_test_1.test)('only "won\'t ever work" errors stop retries', () => {
    assert.ok((0, outbox_1.isPermanent)(400));
    assert.ok((0, outbox_1.isPermanent)(409)); // same key, different journal: a person must look
    assert.ok(!(0, outbox_1.isPermanent)(422)); // insufficient funds: an earlier movement may still be on its way
    assert.ok(!(0, outbox_1.isPermanent)(429));
    assert.ok(!(0, outbox_1.isPermanent)(503));
});
(0, node_test_1.test)('outbox id is stable per key', () => {
    assert.equal((0, outbox_1.outboxId)('play_abc'), (0, outbox_1.outboxId)('play_abc'));
    assert.notEqual((0, outbox_1.outboxId)('play_abc'), (0, outbox_1.outboxId)('play_abd'));
});
// Contract test against a running ledger: LEDGER_URL=http://localhost:8099 npm run test:pay
(0, node_test_1.test)('functions and the Python ledger agree on every template', { skip: !process.env.LEDGER_URL }, async () => {
    const run = Date.now().toString(36);
    const steps = [
        ['coin_purchase', { uid: `a${run}`, coins: 700, debt_paid: 0, order_id: null }],
        ['gift', { sender: `a${run}`, coins: 100, receiver: `b${run}`, receiver_diamonds: 80 }],
        ['release', { uid: `b${run}`, diamonds: 80 }],
        ['withdrawal_lock', { uid: `b${run}`, diamonds: 50, withdrawal_id: 'w1' }],
        ['withdrawal_returned', { uid: `b${run}`, diamonds: 20, withdrawal_id: 'w1' }],
        ['withdrawal_paid', { uid: `b${run}`, diamonds: 30, withdrawal_id: 'w1' }],
        ['coin_void', { uid: `a${run}`, take_from_balance: 600, add_debt: 100, order_id: null }],
    ];
    for (const [i, [template, args]] of steps.entries()) {
        const r = await (0, outbox_1.send)(template, `contract_${run}_${i}`, args);
        assert.equal(r.status, 200, `${template}: ${JSON.stringify(r.body)}`);
    }
    const again = await (0, outbox_1.send)('coin_purchase', `contract_${run}_0`, steps[0][1]);
    assert.equal(again.body.replayed, true);
});
//# sourceMappingURL=outbox.test.js.map