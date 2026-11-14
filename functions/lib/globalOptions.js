"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
/**
 * Imported first by index.ts so it applies to every function defined after it.
 *
 * App Check: callables verify the app's App Check token whenever one is sent
 * (the app activates Play Integrity / DeviceCheck in main.dart). Enforcing it
 * rejects calls without a valid token, so it is switched on per project with
 * APP_CHECK_ENFORCE=true in functions/.env.<project> once the App Check
 * console shows (almost) all requests verified. Webhooks (onRequest) are not
 * affected; they check their own signatures.
 */
const v2_1 = require("firebase-functions/v2");
(0, v2_1.setGlobalOptions)({
    enforceAppCheck: process.env.APP_CHECK_ENFORCE === 'true',
    memory: '512MiB',
    secrets: ['OPENROUTER_API_KEY'],
});
//# sourceMappingURL=globalOptions.js.map