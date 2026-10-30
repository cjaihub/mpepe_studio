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
exports.onNotificationCreated = void 0;
/**
 * Activity push fan-out.
 *
 * Every in-app alert is a `notifications/{id}` doc (likes, comments, follows,
 * "X posted", "X is LIVE", ...). This trigger mirrors each new doc to the
 * recipient's devices as a ringing push so it arrives while Oneova is in the
 * background or closed. While the app is open the in-app banner rings instead
 * (the foreground handler skips pushes that carry `notificationId`).
 *
 * Honours the recipient's notification settings (`user_settings/{uid}.notifications`,
 * falling back to `users/{uid}/settings/notifications`): push on/off,
 * per-category switches, quiet hours (urgent bypasses), sound and preview.
 */
const firestore_1 = require("firebase-functions/v2/firestore");
const logger = __importStar(require("firebase-functions/logger"));
const firestore_2 = require("firebase-admin/firestore");
const messaging_1 = require("firebase-admin/messaging");
const accountSettings_1 = require("./accountSettings");
const db = () => (0, firestore_2.getFirestore)();
// Calls ring through calls.ts; chat pushes are sent by the messaging pipeline.
const SKIP = new Set(['call', 'missedCall', 'newMessage']);
function inQuietHours(p) {
    var _a, _b, _c;
    if (!p.dndEnabled)
        return false;
    const start = (_a = p.quietHoursStart) !== null && _a !== void 0 ? _a : 22;
    const end = (_b = p.quietHoursEnd) !== null && _b !== void 0 ? _b : 8;
    if (start === end)
        return false;
    const local = new Date(Date.now() + ((_c = p.timezoneOffsetMinutes) !== null && _c !== void 0 ? _c : 0) * 60000);
    const hour = local.getUTCHours();
    return start < end ? hour >= start && hour < end : hour >= start || hour < end;
}
exports.onNotificationCreated = (0, firestore_1.onDocumentCreated)('notifications/{id}', async (event) => {
    var _a, _b, _c;
    const n = (_a = event.data) === null || _a === void 0 ? void 0 : _a.data();
    if (!n)
        return;
    const uid = n.userId || n.recipientId;
    const category = n.category || 'system';
    if (!uid || SKIP.has(category) || n.isRead === true)
        return;
    const prefs = (await (0, accountSettings_1.readAccountSettings)(uid, 'notifications', 'settings/notifications'));
    const urgent = n.priority === 'urgent';
    if (prefs.pushEnabled === false && !urgent)
        return;
    if (((_b = prefs.categoryOverrides) === null || _b === void 0 ? void 0 : _b[category]) === false && !urgent)
        return;
    if (inQuietHours(prefs) && !urgent)
        return;
    const tokens = await db().collection('users').doc(uid).collection('device_tokens').get();
    if (tokens.empty)
        return;
    const sound = prefs.soundEnabled !== false;
    const title = String(n.title || 'Oneova');
    const body = prefs.previewMessageContent === false ? 'Open Oneova to see it.' : String(n.body || n.message || '');
    const route = String(n.deepLink || ((_c = n.payload) === null || _c === void 0 ? void 0 : _c.route) || '/notifications');
    const live = category === 'live';
    const res = await (0, messaging_1.getMessaging)().sendEachForMulticast({
        tokens: tokens.docs.map((d) => d.id),
        notification: { title, body },
        data: { notificationId: event.params.id, category, route, priority: String(n.priority || 'normal') },
        android: {
            priority: 'high',
            collapseKey: n.groupId || undefined,
            notification: {
                channelId: live ? 'oneova_live_channel' : 'oneova_high_importance_channel',
                sound: sound ? 'oneova_notification' : undefined,
                color: live ? '#FF2D87' : '#0C4FA8',
                tag: n.groupId || undefined,
                defaultVibrateTimings: true,
            },
        },
        apns: {
            headers: { 'apns-priority': '10' },
            payload: {
                aps: {
                    sound: sound ? 'oneova_notification.wav' : undefined,
                    'thread-id': n.groupId || category,
                    'interruption-level': live || urgent ? 'time-sensitive' : 'active',
                },
            },
        },
    });
    // Drop tokens FCM reports as gone so the next fan-out is cheaper.
    const stale = [];
    res.responses.forEach((r, i) => {
        var _a;
        var _b;
        const code = (_b = (_a = r.error) === null || _a === void 0 ? void 0 : _a.code) !== null && _b !== void 0 ? _b : '';
        if (code.includes('registration-token-not-registered') || code.includes('invalid-argument')) {
            stale.push(tokens.docs[i].ref.delete());
        }
    });
    await Promise.all(stale);
    if (res.failureCount > 0)
        logger.info('notification push partial failure', { id: event.params.id, failed: res.failureCount });
});
//# sourceMappingURL=notifications.js.map