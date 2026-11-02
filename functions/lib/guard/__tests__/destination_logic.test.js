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
const destination_logic_1 = require("../../feed/destination_logic");
(0, node_test_1.test)('product id wins and maps to checkout', () => {
    const r = (0, destination_logic_1.parseDestination)({ productId: 'abc_123', url: 'https://x.com' });
    assert.ok(r.ok);
    if (r.ok) {
        assert.equal(r.value.kind, 'product');
        assert.equal(r.value.route, '/biz/checkout/abc_123');
    }
    assert.equal((0, destination_logic_1.parseDestination)({ productId: '../x' }).ok, false);
});
(0, node_test_1.test)('web links are normalised to https', () => {
    const r = (0, destination_logic_1.parseDestination)({ url: 'shop.example.com/item?id=4' });
    assert.ok(r.ok);
    if (r.ok) {
        assert.equal(r.value.kind, 'web');
        assert.equal(r.value.url, 'https://shop.example.com/item?id=4');
        assert.equal(r.value.host, 'shop.example.com');
    }
    const h = (0, destination_logic_1.parseDestination)({ url: 'http://example.org' });
    assert.ok(h.ok && h.value.url === 'https://example.org/');
});
(0, node_test_1.test)('dangerous shapes are rejected', () => {
    for (const url of ['javascript:alert(1)', 'data:text/html,hi', 'intent://x', 'https://user:pw@bank.com', 'http://localhost:3000',
        'https://192.168.1.4/', 'https://10.0.0.1', 'ftp://example.com', 'https://nodot', 'has space.com', '']) {
        assert.equal((0, destination_logic_1.parseDestination)({ url }).ok, false, url);
    }
    assert.equal((0, destination_logic_1.parseDestination)({ url: `https://a.com/${'x'.repeat(600)}` }).ok, false);
});
(0, node_test_1.test)('first-party links open in the app', () => {
    var _a, _b, _c;
    const r = (0, destination_logic_1.parseDestination)({ url: 'https://oneova.web.app/product/p1' });
    assert.ok(r.ok && r.value.kind === 'product' && r.value.route === '/biz/checkout/p1');
    assert.equal((_a = (0, destination_logic_1.firstPartyRoute)('/shop')) === null || _a === void 0 ? void 0 : _a.route, '/biz_feed');
    assert.equal((_b = (0, destination_logic_1.firstPartyRoute)('/live/s1')) === null || _b === void 0 ? void 0 : _b.route, '/live/viewer/s1');
    assert.equal((_c = (0, destination_logic_1.firstPartyRoute)('/profile/u1')) === null || _c === void 0 ? void 0 : _c.route, '/profile/u1');
    const other = (0, destination_logic_1.parseDestination)({ url: 'https://oneova.web.app/deletion' });
    assert.ok(other.ok && other.value.kind === 'web');
});
(0, node_test_1.test)('labels', () => {
    assert.equal((0, destination_logic_1.defaultLabel)('web', 'www.nike.com'), 'nike.com');
    assert.equal((0, destination_logic_1.defaultLabel)('product', null, 'Red sneakers'), 'Red sneakers');
    assert.equal((0, destination_logic_1.parseDestination)({ url: 'a.com', label: '  Buy\u0000 now  ' }).ok, true);
});
//# sourceMappingURL=destination_logic.test.js.map