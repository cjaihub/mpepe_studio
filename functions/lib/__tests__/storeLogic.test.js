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
const storeLogic_1 = require("../commerce/storeLogic");
const shoe = {
    customization: [
        { id: 'sole', label: 'Sole', type: 'choice', required: true, choices: [
                { id: 'white', label: 'White' }, { id: 'gold', label: 'Gold', priceDelta: 5, modelVariant: 'GoldSole' },
            ] },
        { id: 'name', label: 'Engraving', type: 'text', maxLength: 10, priceDelta: 3 },
    ],
};
(0, node_test_1.test)('customization: prices choices and text', () => {
    const lines = (0, storeLogic_1.priceCustomization)(shoe, { sole: 'gold', name: 'AMANI' });
    assert.equal((0, storeLogic_1.customizationExtra)(lines), 8);
    assert.equal(lines[0].modelVariant, 'GoldSole');
});
(0, node_test_1.test)('customization: required option and unknown choice are refused', () => {
    assert.throws(() => (0, storeLogic_1.priceCustomization)(shoe, {}), storeLogic_1.StoreRuleError);
    assert.throws(() => (0, storeLogic_1.priceCustomization)(shoe, { sole: 'red' }), storeLogic_1.StoreRuleError);
    assert.throws(() => (0, storeLogic_1.priceCustomization)(shoe, { sole: 'white', name: 'X'.repeat(11) }), storeLogic_1.StoreRuleError);
});
(0, node_test_1.test)('customization: client price deltas are ignored', () => {
    const lines = (0, storeLogic_1.priceCustomization)(shoe, { sole: 'white', name: '' });
    assert.equal((0, storeLogic_1.customizationExtra)(lines), 0);
});
(0, node_test_1.test)('codes: percent, amount, limits', () => {
    const now = 1000;
    assert.equal((0, storeLogic_1.codeDiscount)({ percentOff: 10 }, 200, 'KES', now), 20);
    assert.equal((0, storeLogic_1.codeDiscount)({ amountOff: 50, currency: 'KES' }, 30, 'KES', now), 30);
    assert.throws(() => (0, storeLogic_1.codeDiscount)({ percentOff: 10, endsAtMs: 900 }, 100, 'KES', now));
    assert.throws(() => (0, storeLogic_1.codeDiscount)({ percentOff: 10, maxUses: 2, uses: 2 }, 100, 'KES', now));
    assert.throws(() => (0, storeLogic_1.codeDiscount)({ percentOff: 10, minSpend: 500 }, 100, 'KES', now));
    assert.throws(() => (0, storeLogic_1.codeDiscount)({ amountOff: 5, currency: 'USD' }, 100, 'KES', now));
    assert.equal((0, storeLogic_1.normalizeCode)(' live-20 '), 'LIVE20');
});
(0, node_test_1.test)('fulfilment moves one step at a time', () => {
    assert.ok((0, storeLogic_1.canFulfil)(undefined, 'packed'));
    assert.ok((0, storeLogic_1.canFulfil)('packed', 'ready'));
    assert.ok(!(0, storeLogic_1.canFulfil)('new', 'shipped'));
});
(0, node_test_1.test)('rating average', () => {
    assert.deepEqual((0, storeLogic_1.nextRating)(4, 1, 5), { rating: 4.5, reviewCount: 2 });
    assert.deepEqual((0, storeLogic_1.nextRating)(undefined, undefined, 9), { rating: 5, reviewCount: 1 });
});
//# sourceMappingURL=storeLogic.test.js.map