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
const payoutLogic_1 = require("../payoutLogic");
const all = { flutterwave: true, paystack: true };
(0, node_test_1.test)('state machine only moves forward', () => {
    assert.ok((0, payoutLogic_1.canMove)('pending', 'processing'));
    assert.ok((0, payoutLogic_1.canMove)('processing', 'paid'));
    assert.ok((0, payoutLogic_1.canMove)('processing', 'failed'));
    assert.ok(!(0, payoutLogic_1.canMove)('paid', 'failed'));
    assert.ok(!(0, payoutLogic_1.canMove)('processing', 'cancelled'));
    assert.ok(!(0, payoutLogic_1.canMove)('pending', 'paid'));
});
(0, node_test_1.test)('rails: Africa gets mobile money and banks, elsewhere none yet', () => {
    const ke = (0, payoutLogic_1.railsFor)('KE', all);
    assert.equal(ke[0].rail, 'mobile_money');
    assert.ok(ke[0].networks.some((n) => n.id === 'MPESA'));
    assert.deepEqual((0, payoutLogic_1.railsFor)('FR', all), []);
    // Paystack only offers its own networks.
    const gh = (0, payoutLogic_1.railsFor)('GH', { flutterwave: false, paystack: true });
    assert.equal(gh[0].provider, 'paystack');
    assert.deepEqual((0, payoutLogic_1.railsFor)('UG', { flutterwave: false, paystack: true }), []);
});
(0, node_test_1.test)('phone numbers get the dial code', () => {
    assert.equal((0, payoutLogic_1.normalizeMsisdn)('0712 345 678', 'KE'), '254712345678');
    assert.equal((0, payoutLogic_1.normalizeMsisdn)('+254712345678', 'KE'), '254712345678');
    assert.equal((0, payoutLogic_1.normalizeMsisdn)('12', 'KE'), null);
});
(0, node_test_1.test)('fees, rounding, conversion', () => {
    assert.equal((0, payoutLogic_1.payoutFeeUsd)('mobile_money', 10), 0.2);
    assert.equal((0, payoutLogic_1.payoutFeeUsd)('mobile_money', 100), 1.5);
    assert.equal((0, payoutLogic_1.payoutFeeUsd)('bank', 100), 1);
    assert.equal((0, payoutLogic_1.roundLocal)(1234.9, 'KES'), 1234);
    assert.equal((0, payoutLogic_1.roundLocal)(12.349, 'GHS'), 12.34);
    assert.equal((0, payoutLogic_1.usdToDiamonds)(10), 1000);
});
(0, node_test_1.test)('fraud checks flag risky withdrawals', () => {
    const ok = { amountUsd: 20, accountAgeDays: 30, deviceAgeHours: 400, paidBefore: 2, kycCountry: 'KE', locationCountry: 'KE', payoutCountry: 'KE' };
    assert.deepEqual((0, payoutLogic_1.fraudReasons)(ok), []);
    assert.deepEqual((0, payoutLogic_1.fraudReasons)(Object.assign(Object.assign({}, ok), { deviceAgeHours: 3 })), ['new_device']);
    assert.deepEqual((0, payoutLogic_1.fraudReasons)(Object.assign(Object.assign({}, ok), { locationCountry: 'NG' })), ['location_mismatch']);
    assert.deepEqual((0, payoutLogic_1.fraudReasons)(Object.assign(Object.assign({}, ok), { paidBefore: 0, amountUsd: 800 })), ['large_first_withdrawal']);
});
//# sourceMappingURL=payoutLogic.test.js.map