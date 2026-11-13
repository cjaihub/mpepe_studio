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
const variant_logic_1 = require("../commerce/variant_logic");
const shoe = {
    stock: 5,
    variants: [
        { id: 'blue', name: 'Blue', stock: 2 },
        { id: 'white', name: 'White' },
    ],
};
(0, node_test_1.test)('a product without variants needs no choice', () => {
    assert.equal((0, variant_logic_1.pickVariant)({ stock: 3 }, undefined, 1), null);
});
(0, node_test_1.test)('a product without variants rejects a variant id', () => {
    assert.throws(() => (0, variant_logic_1.pickVariant)({ stock: 3 }, 'blue', 1), variant_logic_1.VariantError);
});
(0, node_test_1.test)('a product with variants requires a valid choice', () => {
    var _a;
    assert.throws(() => (0, variant_logic_1.pickVariant)(shoe, '', 1), /Choose an option/);
    assert.throws(() => (0, variant_logic_1.pickVariant)(shoe, 'red', 1), /no longer available/);
    assert.equal((_a = (0, variant_logic_1.pickVariant)(shoe, 'blue', 2)) === null || _a === void 0 ? void 0 : _a.name, 'Blue');
});
(0, node_test_1.test)('variant stock is checked', () => {
    var _a;
    assert.throws(() => (0, variant_logic_1.pickVariant)(shoe, 'blue', 3), /Not enough Blue/);
    assert.equal((_a = (0, variant_logic_1.pickVariant)(shoe, 'white', 20)) === null || _a === void 0 ? void 0 : _a.stock, null); // untracked variant stock
});
(0, node_test_1.test)('a sale lowers product and variant stock', () => {
    const { update, shortfall } = (0, variant_logic_1.stockAfterSale)(shoe, 'blue', 2);
    assert.equal(shortfall, false);
    assert.equal(update.stock, 3);
    const v = update.variants;
    assert.equal(v[0].stock, 0);
    assert.equal(v[1].stock, undefined);
});
(0, node_test_1.test)('selling the last unit marks the product out of stock', () => {
    const { update } = (0, variant_logic_1.stockAfterSale)({ stock: 1 }, null, 1);
    assert.equal(update.stock, 0);
    assert.equal(update.inStock, false);
});
(0, node_test_1.test)('overselling never goes below zero and is reported', () => {
    const { update, shortfall } = (0, variant_logic_1.stockAfterSale)({ stock: 1 }, null, 3);
    assert.equal(update.stock, 0);
    assert.equal(shortfall, true);
});
(0, node_test_1.test)('untracked stock is left alone', () => {
    const { update, shortfall } = (0, variant_logic_1.stockAfterSale)({ price: 10 }, null, 4);
    assert.deepEqual(update, {});
    assert.equal(shortfall, false);
});
//# sourceMappingURL=variant_logic.test.js.map