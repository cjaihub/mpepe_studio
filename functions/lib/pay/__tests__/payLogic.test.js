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
const payLogic_1 = require("../payLogic");
const off = { sandbox: false, wallet: false, mpesa: false, momo: false, flutterwave: false, paystack: false };
(0, node_test_1.test)('no partner keys: no ways to pay', () => {
    assert.deepEqual((0, payLogic_1.methodsFor)('KE', off), []);
});
(0, node_test_1.test)('sandbox: every rail, served by the sandbox', () => {
    const m = (0, payLogic_1.methodsFor)('KE', Object.assign(Object.assign({}, off), { sandbox: true, wallet: true }));
    assert.equal(m[0].id, 'balance');
    assert.ok(m.some((x) => x.id === 'momo:MPESA' && x.provider === 'sandbox' && x.sandbox));
    assert.ok(m.some((x) => x.id === 'card' && x.provider === 'sandbox'));
});
(0, node_test_1.test)('real partners win over the sandbox, by country', () => {
    const ke = (0, payLogic_1.methodsFor)('KE', Object.assign(Object.assign({}, off), { sandbox: true, mpesa: true, flutterwave: true }));
    assert.equal(ke.find((x) => x.id === 'momo:MPESA').provider, 'mpesa');
    assert.equal(ke.find((x) => x.id === 'momo:AIRTEL').provider, 'flutterwave');
    assert.equal(ke.find((x) => x.id === 'card').kind, 'hosted');
    const ug = (0, payLogic_1.methodsFor)('UG', Object.assign(Object.assign({}, off), { momo: true }));
    assert.equal(ug.find((x) => x.id === 'momo:MTN').provider, 'mtn_momo');
    assert.equal(ug.find((x) => x.id === 'momo:AIRTEL'), undefined);
    // M-Pesa keys only open M-Pesa in Kenya.
    assert.equal((0, payLogic_1.methodsFor)('TZ', Object.assign(Object.assign({}, off), { mpesa: true })).length, 0);
});
(0, node_test_1.test)('intent states: late approvals still count, finals stay final', () => {
    assert.ok((0, payLogic_1.canMoveIntent)('pending_payer', 'succeeded'));
    assert.ok((0, payLogic_1.canMoveIntent)('expired', 'succeeded'));
    assert.ok((0, payLogic_1.canMoveIntent)('cancelled', 'succeeded'));
    assert.ok(!(0, payLogic_1.canMoveIntent)('failed', 'succeeded'));
    assert.ok(!(0, payLogic_1.canMoveIntent)('refunded', 'succeeded'));
    assert.ok((0, payLogic_1.canMoveIntent)('succeeded', 'refunded'));
});
(0, node_test_1.test)('ledger postings must balance per currency', () => {
    assert.ok((0, payLogic_1.ledgerBalanced)([{ account: 'a', currency: 'KES', amountMinor: -500 }, { account: 'b', currency: 'KES', amountMinor: 500 }]));
    assert.ok(!(0, payLogic_1.ledgerBalanced)([{ account: 'a', currency: 'KES', amountMinor: -500 }, { account: 'b', currency: 'UGX', amountMinor: 500 }]));
    assert.ok(!(0, payLogic_1.ledgerBalanced)([{ account: 'a', currency: 'KES', amountMinor: 1.5 }, { account: 'b', currency: 'KES', amountMinor: -1.5 }]));
    assert.ok(!(0, payLogic_1.ledgerBalanced)([]));
});
(0, node_test_1.test)('order split sums exactly to the total', () => {
    const s = (0, payLogic_1.orderSplit)(999999, 15000, 10);
    assert.equal(s.platform, 99999);
    assert.equal(s.seller + s.rider + s.platform, s.total);
    assert.equal((0, payLogic_1.orderSplit)(100, 0, 99).platform, 50); // commission capped at 50%
    assert.throws(() => (0, payLogic_1.orderSplit)(1.5, 0, 10));
});
(0, node_test_1.test)('balance payout fees round up to the platform', () => {
    assert.equal((0, payLogic_1.balancePayoutFee)('mobile_money', 10000), 150);
    assert.equal((0, payLogic_1.balancePayoutFee)('bank', 101), 2);
});
(0, node_test_1.test)('live deals: active, scoped, rounded per currency', async () => {
    const { liveDealFor, dealPrice } = await Promise.resolve().then(() => __importStar(require('../../commerce/orderEscrow')));
    const ts = (ms) => ({ toMillis: () => ms });
    const now = 1000000;
    assert.deepEqual(liveDealFor({ title: 'Flash', percentOff: 20, endsAt: ts(now + 1), productIds: [] }, 'p1', now), { title: 'Flash', percentOff: 20 });
    assert.equal(liveDealFor({ percentOff: 20, endsAt: ts(now), productIds: [] }, 'p1', now), null); // ended
    assert.equal(liveDealFor({ percentOff: 20, endsAt: ts(now + 1), productIds: ['p2'] }, 'p1', now), null); // other product
    assert.equal(liveDealFor({ percentOff: 90, endsAt: ts(now + 1) }, 'p1', now), null); // out of range
    assert.equal(dealPrice(9999, 20, 'KES'), 7999.2);
    assert.equal(dealPrice(12.99, 15, 'USD'), 11.04);
    assert.equal(dealPrice(999, 20, 'UGX'), 799);
});
// ── Scan to pay ──────────────────────────────────────────────────────────────
const payLogic_2 = require("../payLogic");
(0, node_test_1.test)('scan to pay: only Oneova Pay codes are accepted', () => {
    const code = 'Ab3_dE5-fG7hJ9kL1mN2pQ';
    assert.equal((0, payLogic_2.qrCodeFrom)(`https://oneova.web.app/p/${code}`), code);
    assert.equal((0, payLogic_2.qrCodeFrom)(`https://oneova.web.app/p/${code}?ref=x`), code);
    assert.equal((0, payLogic_2.qrCodeFrom)(code), code);
    assert.equal((0, payLogic_2.qrCodeFrom)('https://evil.example/p/Ab3_dE5-fG7hJ9kL1mN2pQ'), null);
    assert.equal((0, payLogic_2.qrCodeFrom)('https://oneova.web.app/p/short'), null);
    assert.equal((0, payLogic_2.qrCodeFrom)(''), null);
});
(0, node_test_1.test)('scan to pay: merchant fee rounds down and the lines balance', () => {
    assert.equal(payLogic_2.MERCHANT_FEE_BPS, 100);
    assert.equal((0, payLogic_2.merchantFee)(100000), 1000); // KES 1,000 → KES 10
    assert.equal((0, payLogic_2.merchantFee)(99), 0); // under a shilling → no fee
    assert.throws(() => (0, payLogic_2.merchantFee)(0));
    const lines = (0, payLogic_2.merchantLines)('user:payer', 'shop1', 'KES', 100000, 1000);
    assert.ok((0, payLogic_1.ledgerBalanced)(lines));
    assert.deepEqual(lines.map((l) => [l.account, l.amountMinor]), [['user:payer', -100000], ['biz:shop1', 99000], ['platform:revenue', 1000]]);
    assert.ok((0, payLogic_1.ledgerBalanced)((0, payLogic_2.merchantLines)('clearing:mpesa', 'shop1', 'KES', 50, 0)));
});
(0, node_test_1.test)('scan to pay: inactive, used or expired codes cannot be paid', () => {
    const now = 1000000;
    const at = (ms) => ({ toMillis: () => ms });
    assert.equal((0, payLogic_2.qrProblem)({ active: true, oneTime: false, paid: false, expiresAt: null }, now), null);
    assert.ok((0, payLogic_2.qrProblem)(undefined, now));
    assert.ok((0, payLogic_2.qrProblem)({ active: false }, now));
    assert.ok((0, payLogic_2.qrProblem)({ active: true, oneTime: true, paid: true }, now));
    assert.ok((0, payLogic_2.qrProblem)({ active: true, oneTime: true, paid: false, expiresAt: at(now - 1) }, now));
    assert.equal((0, payLogic_2.qrProblem)({ active: true, oneTime: false, paid: true }, now), null); // a shop code is paid many times
});
const payLogic_3 = require("../payLogic");
(0, node_test_1.test)('personal and business balances are separate accounts', () => {
    assert.equal((0, payLogic_3.ownerAccount)('personal', 'u1'), 'user:u1');
    assert.equal((0, payLogic_3.ownerAccount)('business', 'u1'), 'biz:u1');
    assert.equal((0, payLogic_3.balanceKind)('business'), 'business');
    assert.equal((0, payLogic_3.balanceKind)('anything else'), 'personal');
    assert.equal((0, payLogic_3.userOf)('biz:u1'), null);
    assert.equal((0, payLogic_3.businessOf)('biz:u1'), 'u1');
    assert.equal((0, payLogic_3.businessOf)('user:u1'), null);
});
//# sourceMappingURL=payLogic.test.js.map