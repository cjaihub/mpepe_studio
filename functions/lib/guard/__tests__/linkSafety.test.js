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
const linkSafety_1 = require("../linkSafety");
(0, node_test_1.test)('extracts links with and without a scheme', () => {
    assert.deepEqual((0, linkSafety_1.extractUrls)('see https://a.com/x, and www.b.org.'), ['https://a.com/x', 'http://www.b.org']);
    assert.deepEqual((0, linkSafety_1.extractUrls)('go to paypa1-login.xyz now'), ['http://paypa1-login.xyz']);
});
(0, node_test_1.test)('official domains are clean', () => {
    assert.equal((0, linkSafety_1.analyzeUrl)('https://www.paypal.com/signin').points, 0);
    assert.equal((0, linkSafety_1.analyzeUrl)('https://m.facebook.com/x').points, 0);
});
(0, node_test_1.test)('look-alike and brand-in-host domains are flagged', () => {
    assert.ok((0, linkSafety_1.analyzeUrl)('https://paypa1.com/login').points >= 55);
    assert.ok((0, linkSafety_1.analyzeUrl)('https://g00gle.com').points >= 55);
    assert.ok((0, linkSafety_1.analyzeUrl)('https://paypal.com.secure-check.xyz').points >= 40);
    assert.ok((0, linkSafety_1.analyzeUrl)('https://xn--pypal-4ve.com').points >= 35);
    assert.ok((0, linkSafety_1.analyzeUrl)('http://192.168.4.1/claim').points >= 30);
});
(0, node_test_1.test)('ordinary names are not look-alikes', () => {
    assert.ok((0, linkSafety_1.analyzeUrl)('https://applebees.com').points < 40);
    assert.ok((0, linkSafety_1.analyzeUrl)('https://apply.example.org').points < 40);
    assert.equal((0, linkSafety_1.registrableDomain)('shop.safaricom.co.ke'), 'safaricom.co.ke');
});
(0, node_test_1.test)('scam wording plus link is suspicious, normal chat is safe', () => {
    const scam = (0, linkSafety_1.analyzeText)('Congratulations you won! Claim your prize at bit.ly/xyz, just pay a small fee');
    assert.ok(scam.points >= 40, String(scam.points));
    assert.ok(scam.categories.includes('giveaway') && scam.categories.includes('payment'));
    assert.equal((0, linkSafety_1.verdictFor)(scam.points, false), 'suspicious');
    const ok = (0, linkSafety_1.analyzeText)('See you at 5, the menu is on https://example.com/menu');
    assert.equal((0, linkSafety_1.verdictFor)(ok.points, false), 'safe');
});
(0, node_test_1.test)('known-bad or confident AI verdicts block', () => {
    assert.equal((0, linkSafety_1.verdictFor)(0, true), 'dangerous');
    assert.equal((0, linkSafety_1.verdictFor)(30, false, 'phishing', 0.9), 'dangerous');
    assert.equal((0, linkSafety_1.verdictFor)(30, false, 'phishing', 0.5), 'safe');
});
(0, node_test_1.test)('display-name impersonation', () => {
    assert.ok((0, linkSafety_1.looksLikeName)('0neova Supp0rt', 'Oneova Support'));
    assert.ok(!(0, linkSafety_1.looksLikeName)('Jane Doe', 'Oneova Support'));
});
//# sourceMappingURL=linkSafety.test.js.map