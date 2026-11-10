"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.MockProvider = void 0;
class MockProvider {
    constructor(opts = {}) {
        var _a;
        this.opts = opts;
        /** reference → what the provider "knows". */
        this.book = new Map();
        this.calls = 0;
        this.id = (_a = opts.id) !== null && _a !== void 0 ? _a : 'mock';
    }
    supports(country, rail) {
        return (!this.opts.countries || this.opts.countries.includes(country)) && (!this.opts.rails || this.opts.rails.includes(rail));
    }
    async payout(req) {
        this.calls++;
        if (this.opts.down)
            return { kind: 'rejected', reason: 'provider unavailable', retryable: true };
        const seen = this.book.get(req.reference);
        // Idempotent: the same reference never pays twice.
        if (seen && seen.status !== 'not_found')
            return { kind: 'accepted', providerRef: seen.providerRef };
        const ref = `${this.id}_${req.reference}`;
        switch (req.amountMinor % 100) {
            case 90: return { kind: 'rejected', reason: 'account not found', retryable: false };
            case 91: return { kind: 'rejected', reason: 'provider busy', retryable: true };
            case 92:
                this.book.set(req.reference, { status: 'paid', providerRef: ref, amountMinor: req.amountMinor });
                return { kind: 'unknown', reason: 'timeout' };
            case 93:
                return { kind: 'unknown', reason: 'timeout' };
            case 94:
                this.book.set(req.reference, { status: 'failed', providerRef: ref, amountMinor: req.amountMinor });
                return { kind: 'accepted', providerRef: ref };
            default:
                this.book.set(req.reference, { status: 'paid', providerRef: ref, amountMinor: req.amountMinor });
                return { kind: 'accepted', providerRef: ref };
        }
    }
    async status(reference) {
        const b = this.book.get(reference);
        if (!b)
            return { status: 'not_found' };
        return { status: b.status, providerRef: b.providerRef };
    }
    /** Total paid out for a reference (to prove nothing paid twice). */
    paidCount(reference) {
        var _a;
        return ((_a = this.book.get(reference)) === null || _a === void 0 ? void 0 : _a.status) === 'paid' ? 1 : 0;
    }
}
exports.MockProvider = MockProvider;
//# sourceMappingURL=mockProvider.js.map