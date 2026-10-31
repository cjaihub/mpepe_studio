"use strict";
/**
 * Ova Guard — link and scam heuristics (pure, no I/O, unit-tested).
 *
 * `analyzeText()` finds links and scam wording in a message, comment or bio
 * and returns points + plain-language reasons. It never decides alone that
 * something is dangerous: a known-bad URL from Web Risk (reputation.ts) or a
 * confident Vertex verdict is needed to block. Heuristics only pick which
 * texts are worth the paid checks.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.extractUrls = extractUrls;
exports.hostOf = hostOf;
exports.registrableDomain = registrableDomain;
exports.skeleton = skeleton;
exports.editDistance = editDistance;
exports.isOfficial = isOfficial;
exports.analyzeUrl = analyzeUrl;
exports.analyzeText = analyzeText;
exports.looksLikeName = looksLikeName;
exports.verdictFor = verdictFor;
const URL_RE = /\b((?:https?:\/\/|www\.)[^\s<>"')\]]+|[a-z0-9][a-z0-9-]{1,62}(?:\.[a-z0-9-]{1,62})*\.(?:com|net|org|app|io|co|me|xyz|top|click|link|info|online|site|live|shop|ru|cn|tk|ml|ga|cf|gq|ke|ng|za|tz|ug|gh)\b(?:\/[^\s<>"')\]]*)?)/gi;
/** Brands people get phished for, by the label that must not be imitated. */
const PROTECTED = {
    oneova: ['oneova.com', 'oneova.app', 'mpepe-2b4bd.web.app', 'mpepe-2b4bd.firebaseapp.com'],
    google: ['google.com', 'youtube.com', 'goo.gl', 'g.co', 'gmail.com'],
    paypal: ['paypal.com', 'paypal.me'],
    safaricom: ['safaricom.co.ke', 'mpesa.co.ke'],
    mpesa: ['safaricom.co.ke', 'mpesa.co.ke'],
    facebook: ['facebook.com', 'fb.com', 'fb.me', 'meta.com'],
    instagram: ['instagram.com'],
    whatsapp: ['whatsapp.com', 'wa.me'],
    tiktok: ['tiktok.com'],
    apple: ['apple.com', 'icloud.com'],
    microsoft: ['microsoft.com', 'live.com', 'outlook.com'],
    binance: ['binance.com'],
    coinbase: ['coinbase.com'],
    stripe: ['stripe.com'],
    flutterwave: ['flutterwave.com'],
    paystack: ['paystack.com'],
    netflix: ['netflix.com'],
    amazon: ['amazon.com'],
};
const SHORTENERS = new Set(['bit.ly', 'tinyurl.com', 't.co', 'cutt.ly', 'is.gd', 'rb.gy', 'shorturl.at', 'ow.ly', 'rebrand.ly', 'tiny.cc', 'v.gd', 's.id']);
const RISKY_TLDS = new Set(['xyz', 'top', 'click', 'link', 'tk', 'ml', 'ga', 'cf', 'gq', 'zip', 'mov', 'icu', 'rest', 'cam', 'sbs']);
/** Two-part public suffixes common for our users, so "x.co.ke" keeps "x". */
const TWO_PART = new Set(['co.ke', 'co.uk', 'co.za', 'com.ng', 'co.tz', 'co.ug', 'com.gh', 'com.au', 'co.in', 'com.br']);
const SCAM_PATTERNS = [
    { category: 'giveaway', points: 30, reason: 'Promises a prize, free coins or a giveaway', re: /\b(you(?:'ve| have)? won|claim (?:your|the) (?:prize|reward|gift)|free (?:coins|diamonds|followers|money|iphone)|giveaway winner|double your (?:money|coins|crypto|btc))\b/i },
    { category: 'payment', points: 25, reason: 'Asks you to send money, a gift card or crypto', re: /\b(send (?:me )?(?:money|cash|mpesa|m-pesa|btc|usdt|crypto)|gift ?cards?|western union|moneygram|processing fee|registration fee|verification fee|unlock fee|pay (?:a )?small fee|wallet address)\b/i },
    { category: 'credentials', points: 35, reason: 'Asks for your password, code or to "verify" your account', re: /\b(verify your (?:account|identity|wallet)|your account (?:will be|has been) (?:suspended|disabled|locked|deleted)|confirm your (?:password|login)|(?:send|share|give) (?:me )?(?:the |your )?(?:otp|code|pin|password)|log ?in (?:here|now) to (?:keep|avoid))\b/i },
    { category: 'urgency', points: 10, reason: 'Pushes you to act right now', re: /\b(within 24 ?hours|act now|last chance|urgent(?:ly)?|immediately or)\b/i },
    { category: 'impersonation', points: 30, reason: 'Claims to be Oneova staff or support', re: /\b(oneova (?:support|team|security|admin|official)|official oneova|from the oneova team)\b/i },
    { category: 'investment', points: 25, reason: 'Promises guaranteed investment returns', re: /\b(guaranteed (?:profit|returns?|income)|\d{2,4}% (?:profit|returns?) (?:daily|weekly|in \d+ days)|forex signals?|recover your (?:lost )?(?:funds|crypto))\b/i },
];
function extractUrls(text, max = 10) {
    const out = new Set();
    for (const m of text.matchAll(URL_RE)) {
        let u = m[1].replace(/[.,;:!?]+$/, '');
        if (!/^https?:\/\//i.test(u))
            u = `http://${u}`;
        out.add(u);
        if (out.size >= max)
            break;
    }
    return [...out];
}
function hostOf(url) {
    try {
        return new URL(url).hostname.toLowerCase().replace(/^www\./, '');
    }
    catch (_a) {
        return null;
    }
}
/** "login.paypal.com.evil.xyz" → "evil.xyz"; "shop.co.ke" stays. */
function registrableDomain(host) {
    const parts = host.split('.');
    if (parts.length <= 2)
        return host;
    const last2 = parts.slice(-2).join('.');
    return TWO_PART.has(last2) ? parts.slice(-3).join('.') : last2;
}
/** Undo the usual look-alike tricks: digits for letters, rn→m, vv→w. */
function skeleton(label) {
    return label
        .toLowerCase()
        .replace(/rn/g, 'm')
        .replace(/vv/g, 'w')
        .replace(/0/g, 'o')
        .replace(/[1l|!]/g, 'l')
        .replace(/3/g, 'e')
        .replace(/4/g, 'a')
        .replace(/5/g, 's')
        .replace(/7/g, 't')
        .replace(/8/g, 'b')
        .replace(/-/g, '');
}
function editDistance(a, b) {
    if (Math.abs(a.length - b.length) > 3)
        return 99;
    const dp = Array.from({ length: a.length + 1 }, (_, i) => [i, ...Array(b.length).fill(0)]);
    for (let j = 1; j <= b.length; j++)
        dp[0][j] = j;
    for (let i = 1; i <= a.length; i++) {
        for (let j = 1; j <= b.length; j++) {
            dp[i][j] = Math.min(dp[i - 1][j] + 1, dp[i][j - 1] + 1, dp[i - 1][j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
        }
    }
    return dp[a.length][b.length];
}
function isOfficial(host) {
    return Object.values(PROTECTED).some((list) => list.some((d) => host === d || host.endsWith(`.${d}`)));
}
/** Points and reasons for one link, from the URL alone. */
function analyzeUrl(url) {
    var _a;
    const host = hostOf(url);
    if (!host)
        return null;
    const finding = { url: url.slice(0, 500), host, points: 0, reasons: [] };
    const add = (p, r) => {
        finding.points += p;
        finding.reasons.push(r);
    };
    if (isOfficial(host))
        return finding;
    const domain = registrableDomain(host);
    const label = domain.split('.')[0];
    const tld = (_a = domain.split('.').pop()) !== null && _a !== void 0 ? _a : '';
    if (host.startsWith('xn--') || host.includes('.xn--'))
        add(35, `${host} uses look-alike letters from another alphabet`);
    if (/^\d{1,3}(\.\d{1,3}){3}$/.test(host))
        add(30, 'The link goes to a bare IP address instead of a website name');
    if (/^https?:\/\/[^/]*@/i.test(url))
        add(30, 'The link hides its real address after an "@"');
    if (SHORTENERS.has(host))
        add(15, `${host} is a link shortener that hides where it goes`);
    if (RISKY_TLDS.has(tld))
        add(10, `.${tld} addresses are often used for scams`);
    if (host.split('.').length >= 5)
        add(10, 'The address has an unusual number of parts');
    const sk = skeleton(label);
    for (const [brand, official] of Object.entries(PROTECTED)) {
        if (sk === brand || (brand.length >= 6 && editDistance(sk, brand) <= (brand.length >= 8 ? 2 : 1))) {
            add(55, `${domain} looks like ${brand} but is not the real ${official[0]}`);
            break;
        }
        if (brand.length >= 5 && new RegExp(`(^|[.-])${brand}([.-]|$)`).test(host)) {
            add(40, `${host} uses the name "${brand}" but is not the real ${official[0]}`);
            break;
        }
    }
    if (/\b(login|signin|verify|secure|account|wallet|bonus|claim|gift|free)\b/i.test(host.replace(/[.-]/g, ' '))) {
        add(10, 'The address uses words like "login", "verify" or "free"');
    }
    return finding;
}
function analyzeText(text) {
    const t = String(text !== null && text !== void 0 ? text : '').slice(0, 5000);
    const links = extractUrls(t).map(analyzeUrl).filter((x) => !!x);
    const reasons = [];
    const categories = [];
    let points = links.reduce((m, l) => Math.max(m, l.points), 0);
    for (const l of links)
        reasons.push(...l.reasons);
    for (const p of SCAM_PATTERNS) {
        if (p.re.test(t)) {
            points += p.points;
            reasons.push(p.reason);
            categories.push(p.category);
        }
    }
    // Scam wording next to a link is much worse than either alone.
    if (links.length && categories.length)
        points += 10;
    return { links, points: Math.min(100, points), reasons: [...new Set(reasons)].slice(0, 6), categories };
}
/** True when a display name copies a verified account's name closely. */
function looksLikeName(candidate, verified) {
    const a = skeleton(candidate.normalize('NFKD').replace(/[^\p{L}\p{N}]/gu, ''));
    const b = skeleton(verified.normalize('NFKD').replace(/[^\p{L}\p{N}]/gu, ''));
    if (a.length < 4 || b.length < 4)
        return false;
    return a === b || editDistance(a, b) <= (b.length >= 10 ? 2 : 1);
}
function verdictFor(points, knownBad, aiVerdict, aiConfidence = 0) {
    if (knownBad)
        return 'dangerous';
    if ((aiVerdict === 'phishing' || aiVerdict === 'scam') && aiConfidence >= 0.85)
        return 'dangerous';
    if (points >= 40 || ((aiVerdict === 'phishing' || aiVerdict === 'scam') && aiConfidence >= 0.6))
        return 'suspicious';
    return 'safe';
}
//# sourceMappingURL=linkSafety.js.map