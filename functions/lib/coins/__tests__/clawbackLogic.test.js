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
const clawbackLogic_1 = require("../clawbackLogic");
const gift_logic_1 = require("../../liveStudio/gift_logic");
(0, node_test_1.test)('refund taken from balance first, the rest becomes debt', () => {
    assert.deepEqual((0, clawbackLogic_1.clawbackPlan)(1000, 700), { takeFromBalance: 700, addDebt: 0 });
    assert.deepEqual((0, clawbackLogic_1.clawbackPlan)(200, 700), { takeFromBalance: 200, addDebt: 500 });
    assert.deepEqual((0, clawbackLogic_1.clawbackPlan)(-5, 70), { takeFromBalance: 0, addDebt: 70 });
});
(0, node_test_1.test)('a new pack pays the debt first', () => {
    assert.deepEqual((0, clawbackLogic_1.creditWithDebt)(350, 500), { credit: 0, debtPaid: 350 });
    assert.deepEqual((0, clawbackLogic_1.creditWithDebt)(700, 500), { credit: 200, debtPaid: 500 });
    assert.deepEqual((0, clawbackLogic_1.creditWithDebt)(70, 0), { credit: 70, debtPaid: 0 });
});
(0, node_test_1.test)('gift recipients since the purchase, summed', () => {
    const r = (0, clawbackLogic_1.giftRecipients)([
        { type: 'user_gift_sent', toUid: 'a', amount: -100, createdAtMs: 2000 },
        { type: 'live_gift_sent', toUid: 'a', amount: -50, createdAtMs: 3000 },
        { type: 'live_gift_sent', toUid: 'b', amount: -10, createdAtMs: 500 }, // before the purchase
        { type: 'coin_purchase', amount: 700, createdAtMs: 2500 },
    ], 1000);
    assert.deepEqual([...r.entries()], [['a', 150]]);
});
(0, node_test_1.test)('gift id: same requestId gives the same id; bad ones fall back', () => {
    assert.equal((0, gift_logic_1.giftId)('u1', 'abcd1234-ef', 1), (0, gift_logic_1.giftId)('u1', 'abcd1234-ef', 999));
    assert.notEqual((0, gift_logic_1.giftId)('u1', 'short', 1), (0, gift_logic_1.giftId)('u1', 'short', 2));
    assert.notEqual((0, gift_logic_1.giftId)('u1', 'bad/../id-xxxxxx', 1), 'u1_rbad/../id-xxxxxx');
});
//# sourceMappingURL=clawbackLogic.test.js.map