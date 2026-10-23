"use strict";
/**
 * Oneova transactional email designs: one-time codes, sign-in alerts and
 * account-secured notices, plus the small web pages the expiring links open.
 *
 * Table layout + inline styles so Gmail, Outlook and Apple Mail render the
 * same. Brand: blue #0C4FA8 primary, pink #FF2D87 accent. A dark-mode block
 * in <head> is used by clients that support it (Apple Mail, Gmail app).
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.esc = esc;
exports.codeEmail = codeEmail;
exports.alertEmail = alertEmail;
exports.page = page;
const BLUE = '#0C4FA8';
const PINK = '#FF2D87';
const INK = '#0F172A';
const MUTED = '#475569';
const FAINT = '#94A3B8';
const LINE = '#E2E8F0';
function esc(s) {
    return String(s !== null && s !== void 0 ? s : '')
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}
function shell(opts) {
    var _a;
    return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light dark"><meta name="supported-color-schemes" content="light dark">
<title>Oneova</title>
<style>
  @media (prefers-color-scheme: dark) {
    .bg { background:#0A0A0A !important; }
    .card { background:#141414 !important; border-color:#262626 !important; }
    .ink { color:#F3F4F6 !important; }
    .muted { color:#9CA3AF !important; }
    .facts td { border-color:#262626 !important; }
    .code { background:#1F1F1F !important; color:#F3F4F6 !important; border-color:#262626 !important; }
  }
  @media (max-width:620px){ .wrap{ width:100% !important; } .pad{ padding:24px 20px !important; } }
</style></head>
<body style="margin:0;padding:0;" class="bg">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;">${esc(opts.preheader)}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" class="bg" style="background:#F1F5F9;">
<tr><td align="center" style="padding:28px 12px;">
  <table role="presentation" width="560" cellpadding="0" cellspacing="0" class="wrap" style="width:560px;max-width:560px;">
    <tr><td style="padding:0 4px 14px 4px;font:800 18px/1 -apple-system,Segoe UI,Roboto,Inter,Arial,sans-serif;letter-spacing:-0.3px;color:${BLUE};">
      Oneova<span style="color:${PINK};">.</span>
    </td></tr>
    <tr><td class="card pad" style="background:#FFFFFF;border:1px solid ${LINE};border-radius:16px;padding:32px 32px 28px 32px;font-family:-apple-system,Segoe UI,Roboto,Inter,Arial,sans-serif;">
      ${opts.body}
    </td></tr>
    <tr><td class="muted" style="padding:16px 8px 0 8px;font:400 11.5px/1.5 -apple-system,Segoe UI,Roboto,Inter,Arial,sans-serif;color:${FAINT};">
      ${(_a = opts.footer) !== null && _a !== void 0 ? _a : 'You received this security email because it is about your Oneova account. Oneova will never ask for your password or this code by phone, chat or email.'}
    </td></tr>
  </table>
</td></tr></table>
</body></html>`;
}
const h1 = (t) => `<h1 class="ink" style="margin:0 0 8px 0;font-size:22px;line-height:1.25;font-weight:800;letter-spacing:-0.4px;color:${INK};">${esc(t)}</h1>`;
const p = (t) => `<p class="muted" style="margin:0 0 16px 0;font-size:14px;line-height:1.55;color:${MUTED};">${t}</p>`;
const pill = (t, color) => `<span style="display:inline-block;padding:3px 8px;border-radius:999px;background:${color}1A;color:${color};font-size:10.5px;font-weight:800;letter-spacing:0.8px;text-transform:uppercase;">${esc(t)}</span>`;
function button(label, href, kind = 'primary') {
    const bg = kind === 'primary' ? BLUE : kind === 'danger' ? PINK : '#FFFFFF';
    const fg = kind === 'ghost' ? INK : '#FFFFFF';
    const border = kind === 'ghost' ? LINE : bg;
    return `<a href="${esc(href)}" style="display:inline-block;background:${bg};color:${fg};border:1px solid ${border};text-decoration:none;font-weight:700;font-size:14px;line-height:1;padding:13px 18px;border-radius:10px;margin:0 8px 8px 0;">${esc(label)}</a>`;
}
function facts(rows) {
    const tr = rows
        .filter((r) => r.value)
        .map((r) => `<tr><td class="muted" style="padding:10px 0;border-top:1px solid ${LINE};font-size:12.5px;color:${MUTED};width:38%;">${esc(r.label)}</td>` +
        `<td class="ink" style="padding:10px 0;border-top:1px solid ${LINE};font-size:13px;font-weight:600;color:${INK};">${esc(r.value)}</td></tr>`)
        .join('');
    return `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" class="facts" style="margin:4px 0 20px 0;border-bottom:1px solid ${LINE};">${tr}</table>`;
}
const PURPOSE = {
    verify_email: { subject: 'verification code', title: 'Verify your email', lead: 'Enter this code in Oneova to confirm this is your email address.' },
    sensitive_action: { subject: 'security code', title: 'Confirm it’s you', lead: 'Enter this code in Oneova to approve this change to your account.' },
};
function codeEmail(opts) {
    const pp = PURPOSE[opts.purpose];
    const spaced = opts.code.split('').join(' ');
    const body = `${pill('Security', BLUE)}<div style="height:12px"></div>` +
        h1(pp.title) +
        p(esc(pp.lead)) +
        `<div class="code" style="margin:6px 0 10px 0;padding:18px 0;text-align:center;background:#F8FAFC;border:1px solid ${LINE};border-radius:12px;font:800 32px/1 'SF Mono',Menlo,Consolas,monospace;letter-spacing:8px;color:${INK};">${esc(spaced)}</div>` +
        `<p class="muted" style="margin:0 0 20px 0;font-size:12.5px;color:${MUTED};text-align:center;">Expires in <b>${opts.minutes} minutes</b>. It works once.</p>` +
        (opts.requestedFrom.length ? `<p class="muted" style="margin:0 0 4px 0;font-size:12px;font-weight:700;color:${MUTED};text-transform:uppercase;letter-spacing:0.6px;">Requested from</p>` + facts(opts.requestedFrom) : '') +
        p(`<b class="ink" style="color:${INK};">Didn’t ask for this?</b> Someone may be using your signed-in account. Secure it now; it signs out every device.`) +
        (opts.secureUrl ? button('Not me — secure my account', opts.secureUrl, 'danger') : '');
    const text = `${pp.title}\n\n${pp.lead}\n\nCode: ${opts.code}\nExpires in ${opts.minutes} minutes and works once.\n\n` +
        opts.requestedFrom.map((f) => `${f.label}: ${f.value}`).join('\n') +
        `\n\nDidn't ask for this? Someone may be using your signed-in account.` +
        (opts.secureUrl ? `\nNot you? Secure your account: ${opts.secureUrl}` : '') +
        `\n\nOneova will never ask for this code by phone, chat or email.`;
    return {
        subject: `${opts.code} is your Oneova ${pp.subject}`,
        html: shell({ preheader: `${opts.code} · expires in ${opts.minutes} minutes`, body }),
        text,
    };
}
// ── Sign-in / security alert ─────────────────────────────────────────────
function alertEmail(opts) {
    var _a;
    const riskPill = opts.risk === 'high' ? pill('Action needed', PINK) : opts.risk === 'medium' ? pill('Please check', BLUE) : pill('For your records', BLUE);
    const actions = opts.confirmUrl || opts.secureUrl
        ? `<div style="margin:4px 0 6px 0;">` +
            (opts.confirmUrl ? button('Yes, it was me', opts.confirmUrl, 'primary') : '') +
            (opts.secureUrl ? button('Not me — secure my account', opts.secureUrl, 'danger') : '') +
            `</div><p class="muted" style="margin:0 0 18px 0;font-size:12px;color:${FAINT};">These buttons expire in ${opts.linkMinutes} minutes and work once. After that, use Profile → Security in the app.</p>`
        : '';
    const body = `${riskPill}<div style="height:12px"></div>` +
        h1(opts.title) +
        p(esc(opts.lead)) +
        facts(opts.details) +
        actions +
        (opts.lastSignIn && opts.lastSignIn.length
            ? `<p class="muted" style="margin:6px 0 4px 0;font-size:12px;font-weight:700;color:${MUTED};text-transform:uppercase;letter-spacing:0.6px;">Your previous sign-in</p>` + facts(opts.lastSignIn)
            : '') +
        p(`If you secure your account, every device is signed out, fingerprint sign-in is removed, and you sign in again with your password and a code.`);
    const text = `${opts.title}\n\n${opts.lead}\n\n` +
        opts.details.filter((f) => f.value).map((f) => `${f.label}: ${f.value}`).join('\n') +
        (opts.confirmUrl ? `\n\nYes, it was me: ${opts.confirmUrl}` : '') +
        (opts.secureUrl ? `\nNot me, secure my account: ${opts.secureUrl}` : '') +
        (opts.confirmUrl || opts.secureUrl ? `\n(Links expire in ${opts.linkMinutes} minutes.)` : '') +
        (((_a = opts.lastSignIn) === null || _a === void 0 ? void 0 : _a.length) ? `\n\nPrevious sign-in:\n` + opts.lastSignIn.map((f) => `${f.label}: ${f.value}`).join('\n') : '');
    return {
        subject: opts.risk === 'high' ? `Action needed: ${opts.title}` : opts.title,
        html: shell({ preheader: opts.lead, body }),
        text,
    };
}
// ── Pages opened by the expiring links ─────────────────────────────────────
function page(opts) {
    const color = opts.tone === 'warn' ? PINK : BLUE;
    const form = opts.form
        ? `<form method="POST" action="${esc(opts.form.action)}" style="margin:8px 0 0 0;">` +
            Object.entries(opts.form.hidden).map(([k, v]) => `<input type="hidden" name="${esc(k)}" value="${esc(v)}">`).join('') +
            `<button type="submit" style="width:100%;border:0;border-radius:10px;padding:14px;font-weight:700;font-size:15px;color:#fff;background:${opts.form.danger ? PINK : BLUE};cursor:pointer;">${esc(opts.form.button)}</button></form>`
        : '';
    return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex"><title>${esc(opts.title)} · Oneova</title>
<style>
 :root{color-scheme:light dark}
 body{margin:0;background:#F1F5F9;font-family:-apple-system,Segoe UI,Roboto,Inter,Arial,sans-serif;color:${INK}}
 .card{max-width:420px;margin:48px auto;background:#fff;border:1px solid ${LINE};border-radius:16px;padding:28px 24px}
 .brand{font-weight:800;color:${BLUE};margin-bottom:18px} .brand span{color:${PINK}}
 h1{font-size:21px;letter-spacing:-.3px;margin:0 0 8px} p{color:${MUTED};font-size:14px;line-height:1.55;margin:0 0 16px}
 .bar{height:4px;border-radius:4px;background:${color};width:44px;margin:0 0 16px}
 @media (prefers-color-scheme:dark){body{background:#0A0A0A;color:#F3F4F6}.card{background:#141414;border-color:#262626}p{color:#9CA3AF}}
</style></head><body><div class="card"><div class="brand">Oneova<span>.</span></div><div class="bar"></div>
<h1>${esc(opts.title)}</h1><p>${opts.message}</p>${form}</div></body></html>`;
}
//# sourceMappingURL=mailTemplates.js.map