"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.candidates = candidates;
exports.routePayout = routePayout;
exports.reconcileAction = reconcileAction;
function candidates(providers, req, opts = {}) {
    var _a, _b;
    const now = (_a = opts.now) !== null && _a !== void 0 ? _a : Date.now();
    const pref = (_b = opts.preference) !== null && _b !== void 0 ? _b : [];
    const rank = (p) => (pref.includes(p.id) ? pref.indexOf(p.id) : pref.length);
    return providers
        .filter((p) => p.supports(req.country, req.rail, req.currency))
        .filter((p) => { var _a, _b; var _c; return ((_c = (_b = (_a = opts.health) === null || _a === void 0 ? void 0 : _a[p.id]) === null || _b === void 0 ? void 0 : _b.openUntil) !== null && _c !== void 0 ? _c : 0) <= now; })
        .sort((a, b) => rank(a) - rank(b));
}
async function routePayout(providers, req, opts = {}) {
    var _a, _b, _c, _d, _e;
    if (!Number.isSafeInteger(req.amountMinor) || req.amountMinor <= 0) {
        return { outcome: { kind: 'rejected', reason: 'invalid amount', retryable: false }, provider: null, attempts: [], health: Object.assign({}, opts.health) };
    }
    const now = (_a = opts.now) !== null && _a !== void 0 ? _a : Date.now();
    const threshold = (_b = opts.failThreshold) !== null && _b !== void 0 ? _b : 3;
    const cooldown = (_c = opts.cooldownMs) !== null && _c !== void 0 ? _c : 5 * 60000;
    const health = Object.assign({}, opts.health);
    const attempts = [];
    const mark = (id, ok) => {
        var _a;
        const h = (_a = health[id]) !== null && _a !== void 0 ? _a : { consecutiveFailures: 0, openUntil: 0 };
        const failures = ok ? 0 : h.consecutiveFailures + 1;
        health[id] = { consecutiveFailures: failures, openUntil: failures >= threshold ? now + cooldown : h.openUntil };
    };
    for (const p of candidates(providers, req, opts)) {
        let outcome;
        try {
            outcome = await p.payout(req);
        }
        catch (e) {
            // An adapter that throws broke its contract; treat it as unknown (safe side).
            outcome = { kind: 'unknown', reason: `adapter error: ${String((_d = e === null || e === void 0 ? void 0 : e.message) !== null && _d !== void 0 ? _d : e).slice(0, 120)}` };
        }
        attempts.push({ provider: p.id, outcome });
        if (outcome.kind === 'accepted') {
            mark(p.id, true);
            return { outcome, provider: p.id, attempts, health };
        }
        if (outcome.kind === 'unknown') {
            mark(p.id, false);
            return { outcome, provider: p.id, attempts, health };
        }
        if (!outcome.retryable) {
            mark(p.id, true); // the provider is healthy; the request was refused
            return { outcome, provider: p.id, attempts, health };
        }
        mark(p.id, false);
    }
    const last = attempts[attempts.length - 1];
    return {
        outcome: (last === null || last === void 0 ? void 0 : last.outcome.kind) === 'rejected' ? last.outcome : { kind: 'rejected', reason: 'No payout partner is available for this method right now.', retryable: true },
        provider: (_e = last === null || last === void 0 ? void 0 : last.provider) !== null && _e !== void 0 ? _e : null,
        attempts,
        health,
    };
}
function reconcileAction(status, ageMs, opts = {}) {
    var _a;
    const reviewAfter = (_a = opts.reviewAfterMs) !== null && _a !== void 0 ? _a : 24 * 3600000;
    if (status === 'paid')
        return 'settle_paid';
    if (status === 'failed')
        return 'settle_failed';
    if (status === 'not_found') {
        // Only for providers whose lookup by reference is documented and reliable.
        const finalAfter = opts.notFoundIsFinalAfterMs;
        if (finalAfter != null && ageMs >= finalAfter)
            return 'settle_failed';
        return ageMs >= reviewAfter ? 'review' : 'wait';
    }
    return ageMs >= reviewAfter ? 'review' : 'wait';
}
//# sourceMappingURL=router.js.map