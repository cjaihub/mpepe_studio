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
var __rest = (this && this.__rest) || function (s, e) {
    var t = {};
    for (var p in s) if (Object.prototype.hasOwnProperty.call(s, p) && e.indexOf(p) < 0)
        t[p] = s[p];
    if (s != null && typeof Object.getOwnPropertySymbols === "function")
        for (var i = 0, p = Object.getOwnPropertySymbols(s); i < p.length; i++) {
            if (e.indexOf(p[i]) < 0 && Object.prototype.propertyIsEnumerable.call(s, p[i]))
                t[p[i]] = s[p[i]];
        }
    return t;
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.ovaAgentExecuteTurn = void 0;
/**
 * Oneova Advanced Multi-Agent Orchestrator, Full Computer-Use Engine, Shared
 * Account Backend Bridge & Wispr Voice Dictation Engine (`ovaAgentExecuteTurn`).
 *
 * Powers the executive Agent Studio across Oneova Mobile and Oneova Desktop
 * (`OneOva.app`) with:
 * 1. Shared user account data tools (posts/drafts, comments, chats/messages,
 *    notifications, reminders, studio projects, memories & connected computers)
 *    that execute live whether a workstation is online or offline.
 * 2. Multi-step autonomous computer-use (`fullComputerAccess` or supervised HITL)
 *    for macOS mouse, keyboard, AppleScript, window, clipboard, shell & NLE tools.
 * 3. Wispr-Flow-style multimodal audio transcription + context-aware AI voice tidy.
 * 4. Real-time thinking traces, dynamic checklists, specialist sub-agents & artifacts.
 */
const crypto = __importStar(require("crypto"));
const https_1 = require("firebase-functions/v2/https");
const params_1 = require("firebase-functions/params");
const firestore_1 = require("firebase-admin/firestore");
const vertexAi_1 = require("./vertexAi");
const protect_1 = require("./guard/protect");
const openRouterSecret = (0, params_1.defineSecret)('OPENROUTER_API_KEY');
const MAC_LOCAL_TOOLS = new Set([
    'inspect_workstation',
    'capture_screen_context',
    'list_open_windows',
    'open_mac_app',
    'manage_app',
    'navigate_app_menu',
    'click_ui_element',
    'press_hotkey',
    'mouse_action',
    'keyboard_action',
    'clipboard_action',
    'run_applescript',
    'system_control',
    'manage_computer_system',
    'list_workspace_files',
    'read_file_snippet',
    'write_workspace_file',
    'run_terminal_command',
    'nle_bridge_action',
    'send_mac_hotkey',
    'type_on_workstation',
    'power_workstation',
    'search_web',
    'search_workspace',
]);
const CLOUD_APP_TOOLS = new Set([
    'get_my_profile',
    'list_my_posts',
    'create_app_post',
    'get_post_comments',
    'reply_to_post_comment',
    'list_my_chats',
    'read_chat_messages',
    'send_app_message',
    'list_notifications',
    'mark_notifications_read',
    'create_reminder',
    'list_reminders',
    'list_studio_projects',
    'list_connected_computers',
    'dispatch_computer_command',
    'save_memory',
    'recall_memories',
    'delete_memory',
]);
const SUPERVISED_APPROVAL_TOOLS = new Set([
    'run_terminal_command',
    'write_workspace_file',
    'run_applescript',
    'mouse_action',
    'keyboard_action',
    'type_on_workstation',
    'power_workstation',
    'manage_app',
    'navigate_app_menu',
    'click_ui_element',
]);
const CATASTROPHIC_SHELL_PATTERNS = [
    /\brm\s+-rf\s+\/(\s|$)/i,
    /\bmkfs\b/i,
    /\bdd\s+if=/i,
    /\bshutdown\s+-h\b/i,
    /\breboot\b/i,
];
function sanitizeJsonText(raw) {
    const trimmed = raw.trim();
    if (trimmed.startsWith('```')) {
        return trimmed
            .replace(/^```(?:json)?\s*/i, '')
            .replace(/\s*```$/i, '')
            .trim();
    }
    return trimmed;
}
function formatTs(raw) {
    if (!raw)
        return '';
    if (raw instanceof firestore_1.Timestamp)
        return raw.toDate().toISOString();
    if (raw instanceof Date)
        return raw.toISOString();
    if (typeof (raw === null || raw === void 0 ? void 0 : raw.toDate) === 'function') {
        try {
            return raw.toDate().toISOString();
        }
        catch (_a) {
            return '';
        }
    }
    return String(raw);
}
function buildWisprSystemPrompt(params) {
    const { style, activeWindow, commandInstruction } = params;
    const appHint = activeWindow
        ? `The user's currently focused application is "${activeWindow}".`
        : '';
    const styleGuide = style === 'code' || /xcode|code|cursor|terminal|iterm|android studio/i.test(activeWindow)
        ? 'Format technical terms, symbols, CLI flags, camelCase/snake_case identifiers, and file paths cleanly while keeping prose concise.'
        : style === 'email' || /mail|outlook|gmail/i.test(activeWindow)
            ? 'Format with crisp executive paragraphing, proper greeting/sign-off spacing if spoken, and polished punctuation.'
            : style === 'chat' || /messages|whatsapp|slack|discord|telegram/i.test(activeWindow)
                ? 'Keep a natural, direct, conversational flow with clean punctuation and no unnecessary stiffness.'
                : 'Produce crisp, publication-grade prose with clean punctuation, capitalization, and smart list formatting when items are enumerated.';
    if (commandInstruction && commandInstruction.trim().length > 0) {
        return `You are Ova Wispr Flow, an instant voice-to-text transformation engine.
${appHint}
Apply this voice command to the provided text/speech: "${commandInstruction.trim()}".
Output ONLY the resulting text ready to paste at the user's cursor—no commentary, no quotes, no markdown wrapper unless requested.`;
    }
    return `You are Ova Wispr Flow, an executive AI dictation & speech-polishing engine.
${appHint}
${styleGuide}

STRICT DICTATION RULES:
1. Preserve the speaker's exact intent, meaning, tone, and spoken language. NEVER answer questions or invent extra ideas—even if the speaker dictates a question or prompt!
2. Remove filler words ("um", "uh", "like", "you know", "basically"), stutters, and false starts.
3. Honor spoken self-corrections naturally (e.g., "let's meet Tuesday—actually make that Wednesday at 3" -> "Let's meet Wednesday at 3:00.").
4. Add accurate punctuation, capitalization, and line breaks when multiple distinct points or steps are dictated.
5. Output ONLY the final cleaned text, nothing else.`;
}
function buildSystemInstruction(params) {
    var _a, _b, _c, _d, _e;
    const wsConnected = Boolean(params.workstationContext.connected);
    const computerName = String((_a = params.workstationContext.computerName) !== null && _a !== void 0 ? _a : 'Unlinked');
    const activeWindow = String((_b = params.workstationContext.activeWindow) !== null && _b !== void 0 ? _b : 'Unknown');
    const os = String((_c = params.workstationContext.os) !== null && _c !== void 0 ? _c : 'macos');
    const workspaceCwd = String((_d = params.workstationContext.workspaceCwd) !== null && _d !== void 0 ? _d : '~');
    const telemetry = JSON.stringify((_e = params.workstationContext.telemetry) !== null && _e !== void 0 ? _e : {});
    const canEmitCloudTools = params.phase !== 'post_tool_synthesis' && params.loopIteration < 3;
    const canEmitMacTools = wsConnected && canEmitCloudTools;
    const memoriesBlock = params.memories && params.memories.length > 0
        ? params.memories.map((m) => `- [${m.key}]: ${m.content}`).join('\n')
        : '- No persistent memories yet. Use "save_memory" to remember user preferences, tools, paths, and habits.';
    return `You are Ova Agent, Oneova's autonomous cross-device AI intelligence, app-data operator & real-time computer controller.

SHARED ONEOVA ACCOUNT SNAPSHOT (Live across Mobile & Computer):
${JSON.stringify(params.accountSummary)}

PERSISTENT ACCOUNT MEMORIES (Synced live across Mobile and Computer):
${memoriesBlock}

ACTIVE SURFACE & WORKSTATION ENVIRONMENT:
- User surface: ${params.originDevice} (Conversations, memories, documents, app data & connected computers sync live across Mobile and Desktop)
- Requested Specialist Mode: ${params.agentMode}
- Reasoning Effort: ${params.effort}
- Turn Phase: ${params.phase} (Autonomous Loop Step: ${params.loopIteration + 1}/3)
- Computer Access Level: ${params.fullComputerAccess ? 'FULL COMPUTER ACCESS (Autonomous Auto-Run granted by user)' : 'SUPERVISED (Human-in-the-Loop approval for mutating Mac tools)'}
- Web Search Grounding: ${params.webSearch ? 'ENABLED' : 'DISABLED'}
- Local Workstation Connected Directly: ${wsConnected}
- Workstation Host: ${computerName} (${os}) — Active Window: ${activeWindow} — CWD: ${workspaceCwd}
- Live Telemetry Snapshot: ${telemetry}
${params.screenContextLabel ? `- Attached Screen Context: ${params.screenContextLabel}` : ''}

SHARED ONEOVA APP & ACCOUNT TOOLS (${canEmitCloudTools ? 'ENABLED — ALWAYS use these real tools when the user asks to read/act on their profile, posts, drafts, comments, messages/chats, notifications, reminders, projects, memories, or remote computers!' : 'DISABLED FOR THIS SYNTHESIS PASS — return "toolCalls": []'}):
- get_my_profile: {} -> Reads the user's Oneova profile, bio, handle, follower/following counts, and linked computers summary.
- list_my_posts: { "limit": 8 } -> Lists the user's published Oneova posts/reels & recent post drafts with views, likes, and comment counts.
- create_app_post: { "caption": "...", "title": "...", "hashtags": ["oneova"], "publishNow": false } -> Saves a rich post draft to the user's Oneova account (or publishes a text/community post if publishNow is true).
- get_post_comments: { "postId": "...", "limit": 15 } -> Reads real comments on a Oneova post (defaults to the user's latest post if postId is omitted).
- reply_to_post_comment: { "postId": "...", "commentId": "optional", "text": "..." } -> Posts a real comment or reply on a post as the signed-in user.
- list_my_chats: { "limit": 10, "unreadOnly": false } -> Lists the user's real Oneova chat threads, participants, last message preview, and unread counts.
- read_chat_messages: { "chatId": "...", "participantQuery": "optional name/username if chatId unknown", "limit": 15 } -> Reads recent messages in a chat thread.
- send_app_message: { "chatId": "optional", "recipientQuery": "optional username/displayName", "text": "..." } -> Sends a real message in an existing Oneova chat thread on behalf of the user.
- list_notifications: { "limit": 12, "unreadOnly": false } -> Reads the user's real Oneova notifications.
- mark_notifications_read: { "notificationIds": [], "markAll": true } -> Marks notifications as read.
- create_reminder: { "title": "...", "dueAtIso": "2026-11-06T09:00:00Z" } -> Saves a real reminder synced to the user's Oneova account.
- list_reminders: { "limit": 10 } -> Lists upcoming reminders on the user's account.
- list_studio_projects: { "limit": 10 } -> Lists the user's Oneova Studio projects & shared documents.
- list_connected_computers: {} -> Lists all computers paired/signed in to the user's Oneova account with live online/heartbeat/window status.
- dispatch_computer_command: { "deviceId": "optional (auto-picks online computer)", "command": "open_mac_app" | "paste_text" | "key_combination" | "capture_live_frame" | "sleep_workstation" | "unlock_workstation" | "execute_ai_task", "payload": {} } -> Dispatches a live remote command through Firestore to any online paired computer even when the user is chatting from Mobile!
- save_memory: { "key": "preference_key", "content": "..." } -> Saves a persistent cross-device memory.
- recall_memories: { "query": "..." } -> Searches saved user memories.
- delete_memory: { "key": "..." } -> Deletes a memory by key.

LOCAL MAC WORKSTATION TOOLS (${canEmitMacTools ? 'ENABLED — emit when direct local macOS execution is needed' : 'UNAVAILABLE ON THIS SURFACE — if a computer is listed online in list_connected_computers, use "dispatch_computer_command" instead!'}):
- manage_app: { "action": "launch" | "focus" | "quit" | "hide" | "restart", "appName": "Safari", "url": "https://..." }
- navigate_app_menu: { "appName": "Safari", "menuBar": "File", "menuItem": "New Window" }
- click_ui_element: { "text": "Save", "role": "button", "appName": "optional" }
- press_hotkey: { "keys": "cmd+s" }
- manage_computer_system: { "action": "set_volume" | "mute_toggle" | "media_play_pause" | "dark_mode_toggle" | "show_notification" | "list_apps" | "kill_app", "value": 50, "title": "...", "message": "..." }
- inspect_workstation: {}
- capture_screen_context: { "includeScreenshot": true }
- list_open_windows: {}
- open_mac_app: { "appName": "Finder" }
- mouse_action: { "action": "move_to" | "move_by" | "click" | "double_click" | "right_click" | "drag_to" | "scroll", "x": 640, "y": 400 }
- keyboard_action: { "action": "paste_text" | "type_keys" | "hotkey" | "key_tap", "text": "...", "combo": "cmd+s" }
- clipboard_action: { "action": "read" | "write", "text": "..." }
- run_applescript: { "script": "tell application \\"Finder\\" to ..." }
- system_control: { "action": "set_volume" | "mute_toggle" | "media_play_pause" | "sleep_display" | "wake_display" | "screenshot_to_desktop" | "spotlight_search" }
- list_workspace_files: { "path": "~/Desktop" }
- read_file_snippet: { "path": "~/file.txt", "maxLines": 150 }
- write_workspace_file: { "path": "~/notes.md", "content": "..." }
- run_terminal_command: { "command": "ls -la", "cwd": "~" }
- nle_bridge_action: { "action": "play_pause" | "save_project" | "export_timeline" }
- send_mac_hotkey: { "combo": "cmd+space" }
- type_on_workstation: { "text": "..." }
- power_workstation: { "action": "sleep_display" | "wake_display" }
- search_web: { "query": "..." }
- search_workspace: { "query": "..." }

CHOOSING SKILLS (do this yourself — never ask the user which tool to use):
- Work out the goal behind the request, then pick and chain the tools that get it done, step by step.
- Unsure of a fact, a name, a price, news, or how to do something? Use search_web first, then act on what you found.
- Need to know what is on the computer? Look first (capture_screen_context, list_open_windows, list_workspace_files) instead of guessing.
- Prefer the most direct route: open an app with manage_app/open_mac_app, run_terminal_command for files and system info, keyboard_action or press_hotkey for typing and shortcuts, mouse_action only when nothing else works.
- After acting, check the result (read the output or look at the screen) before saying it is done. If something failed, try another way once before giving up.

HOW YOU TALK (the "reply" field):
- Talk like a friendly, capable person helping a friend — warm, calm and natural. Short sentences, everyday words.
- Say what you did and what you found in plain language ("I opened Safari and searched for flights to Kigali — the cheapest is $240 on Friday."). No tool names, JSON, file paths, error codes or technical jargon unless the user asks for them.
- Keep it brief: usually one to three sentences. Use a short list only when there are several results.
- If you need something from the user, ask one simple question. If something didn't work, say so honestly and suggest the next step.
- Reply in the same language the user wrote or spoke in.

STRICT OUTPUT RULES:
1. Return ONLY a valid JSON object matching this exact schema (no markdown code fences):
{
  "thinking": ["concise reasoning step 1", "step 2"],
  "subagent": {
    "id": "computer_use" | "code_terminal" | "studio_nle" | "creator_ops" | "research",
    "label": "Human-readable specialist name",
    "role": "Short 3-6 word specialty description"
  },
  "plan": [
    { "id": "p1", "title": "Short actionable task step", "status": "completed" | "in_progress" | "pending" }
  ],
  "toolCalls": [
    {
      "id": "tc_1",
      "name": "tool_name_from_list",
      "title": "Crisp human-readable action title",
      "args": {},
      "risk": "safe" | "approval_required"
    }
  ],
  "artifacts": [
    {
      "id": "art_1",
      "title": "Artifact title",
      "kind": "code" | "markdown" | "plan" | "script" | "command",
      "language": "markdown",
      "content": "Full artifact content"
    }
  ],
  "reply": "A warm, natural reply in plain everyday words (see HOW YOU TALK). Light Markdown only when a list truly helps.",
  "followUps": ["Smart next action 1", "Smart next action 2", "Smart next action 3"]
}
2. Never invent fake messages, notifications, posts, or comments—invoke the real Shared Oneova App tools first so you cite authentic Firestore data!
3. If phase === "post_tool_synthesis", ALWAYS return "toolCalls": [] and synthesize a complete, helpful answer from the tool outputs.
4. Never mention Mpepe or Oneover, and never refer to yourself as Claude; you are strictly Ova Agent on Oneova.`;
}
async function verifyCallerAndQuota(callerUid, deviceId, actionBucket, maxCalls) {
    var _a;
    let quotaUid = callerUid;
    if (callerUid.startsWith('desktop_agent_')) {
        if (deviceId) {
            const compSnap = await (0, firestore_1.getFirestore)()
                .collection('registered_computers')
                .doc(deviceId)
                .get()
                .catch(() => null);
            if (compSnap && compSnap.exists && compSnap.get('agent_uid') === callerUid) {
                quotaUid = String((_a = compSnap.get('owner_uid')) !== null && _a !== void 0 ? _a : callerUid);
            }
        }
    }
    await (0, protect_1.limit)(quotaUid, actionBucket, maxCalls, 10 * 60000);
    return quotaUid;
}
async function loadAccountContextSnapshot(uid) {
    var _a, _b, _c, _d, _e, _f, _g;
    const db = (0, firestore_1.getFirestore)();
    try {
        const [userSnap, compSnap, unreadNotifSnap] = await Promise.all([
            db.collection('users').doc(uid).get().catch(() => null),
            db.collection('registered_computers').where('owner_uid', '==', uid).limit(6).get().catch(() => null),
            db
                .collection('notifications')
                .where('recipientId', '==', uid)
                .where('isRead', '==', false)
                .limit(20)
                .get()
                .catch(() => null),
        ]);
        const u = (_a = userSnap === null || userSnap === void 0 ? void 0 : userSnap.data()) !== null && _a !== void 0 ? _a : {};
        const nowMs = Date.now();
        const computers = ((_b = compSnap === null || compSnap === void 0 ? void 0 : compSnap.docs) !== null && _b !== void 0 ? _b : []).map((doc) => {
            var _a, _b;
            var _c, _d, _e, _f;
            const d = doc.data();
            const lastSeenDate = (_c = (_b = (_a = d.last_seen) === null || _a === void 0 ? void 0 : _a.toDate) === null || _b === void 0 ? void 0 : _b.call(_a)) !== null && _c !== void 0 ? _c : (d.last_seen instanceof Date ? d.last_seen : null);
            const fresh = lastSeenDate ? nowMs - lastSeenDate.getTime() < 75000 : Boolean(d.desktop_connected);
            const isOnline = Boolean(d.desktop_connected) && d.status !== 'offline' && fresh;
            return {
                deviceId: doc.id,
                name: String((_d = d.computer_name) !== null && _d !== void 0 ? _d : 'Workstation'),
                isOnline,
                activeWindow: String((_e = d.active_window) !== null && _e !== void 0 ? _e : 'Desktop'),
                os: String((_f = d.os) !== null && _f !== void 0 ? _f : 'macOS'),
            };
        });
        return {
            uid,
            displayName: String((_e = (_d = (_c = u.fullName) !== null && _c !== void 0 ? _c : u.displayName) !== null && _d !== void 0 ? _d : u.name) !== null && _e !== void 0 ? _e : ''),
            username: String((_f = u.username) !== null && _f !== void 0 ? _f : ''),
            unreadNotificationsCount: (_g = unreadNotifSnap === null || unreadNotifSnap === void 0 ? void 0 : unreadNotifSnap.size) !== null && _g !== void 0 ? _g : 0,
            linkedComputers: computers,
        };
    }
    catch (_h) {
        return { uid };
    }
}
async function executeCloudAppTool(uid, originDevice, tc) {
    var _a, _b, _c, _d, _e, _f, _g;
    var _h, _j, _k, _l, _m, _o, _p, _q, _r, _s, _t, _u, _v, _w, _x, _y, _z, _0, _1, _2, _3, _4, _5, _6, _7, _8, _9, _10, _11, _12, _13, _14, _15, _16, _17, _18, _19, _20, _21, _22, _23, _24, _25, _26, _27, _28, _29, _30, _31, _32, _33, _34, _35, _36, _37, _38, _39, _40, _41, _42, _43, _44, _45, _46, _47, _48, _49, _50, _51, _52, _53, _54, _55, _56, _57, _58, _59, _60, _61, _62, _63, _64, _65, _66, _67, _68, _69, _70, _71, _72, _73, _74, _75, _76, _77, _78, _79, _80, _81, _82, _83, _84, _85, _86;
    const db = (0, firestore_1.getFirestore)();
    const args = (_h = tc.args) !== null && _h !== void 0 ? _h : {};
    switch (tc.name) {
        case 'get_my_profile': {
            const snap = await db.collection('users').doc(uid).get();
            const d = (_j = snap.data()) !== null && _j !== void 0 ? _j : {};
            return JSON.stringify({
                uid,
                displayName: (_m = (_l = (_k = d.fullName) !== null && _k !== void 0 ? _k : d.displayName) !== null && _l !== void 0 ? _l : d.name) !== null && _m !== void 0 ? _m : '',
                username: (_o = d.username) !== null && _o !== void 0 ? _o : '',
                bio: (_p = d.bio) !== null && _p !== void 0 ? _p : '',
                accountType: (_q = d.accountType) !== null && _q !== void 0 ? _q : 'creator',
                followerCount: (_s = (_r = d.followerCount) !== null && _r !== void 0 ? _r : d.followersCount) !== null && _s !== void 0 ? _s : 0,
                followingCount: (_t = d.followingCount) !== null && _t !== void 0 ? _t : 0,
                niches: (_u = d.niches) !== null && _u !== void 0 ? _u : [],
            });
        }
        case 'list_my_posts': {
            const maxItems = Math.min(20, Math.max(1, Number((_v = args.limit) !== null && _v !== void 0 ? _v : 8)));
            const [postsSnap, contentSnap, draftsSnap] = await Promise.all([
                db.collection('posts').where('authorId', '==', uid).limit(maxItems).get().catch(() => null),
                db.collection('content').where('authorId', '==', uid).limit(maxItems).get().catch(() => null),
                db.collection('users').doc(uid).collection('post_drafts').limit(6).get().catch(() => null),
            ]);
            const seen = new Set();
            const posts = [];
            for (const snap of [postsSnap, contentSnap]) {
                for (const doc of (_w = snap === null || snap === void 0 ? void 0 : snap.docs) !== null && _w !== void 0 ? _w : []) {
                    if (seen.has(doc.id))
                        continue;
                    seen.add(doc.id);
                    const d = doc.data();
                    posts.push({
                        postId: doc.id,
                        title: String((_x = d.title) !== null && _x !== void 0 ? _x : '').slice(0, 120),
                        caption: String((_z = (_y = d.caption) !== null && _y !== void 0 ? _y : d.description) !== null && _z !== void 0 ? _z : '').slice(0, 220),
                        type: String((_0 = d.type) !== null && _0 !== void 0 ? _0 : 'post'),
                        views: Number((_2 = (_1 = d.viewCount) !== null && _1 !== void 0 ? _1 : d.views) !== null && _2 !== void 0 ? _2 : 0),
                        likes: Number((_4 = (_3 = d.likeCount) !== null && _3 !== void 0 ? _3 : d.likes) !== null && _4 !== void 0 ? _4 : 0),
                        comments: Number((_6 = (_5 = d.commentCount) !== null && _5 !== void 0 ? _5 : d.commentsCount) !== null && _6 !== void 0 ? _6 : 0),
                        createdAt: formatTs(d.createdAt),
                    });
                }
            }
            const drafts = ((_7 = draftsSnap === null || draftsSnap === void 0 ? void 0 : draftsSnap.docs) !== null && _7 !== void 0 ? _7 : []).map((doc) => {
                var _a, _b, _c, _d;
                const d = doc.data();
                return {
                    draftId: doc.id,
                    title: String((_a = d.title) !== null && _a !== void 0 ? _a : '').slice(0, 120),
                    caption: String((_c = (_b = d.caption) !== null && _b !== void 0 ? _b : d.description) !== null && _c !== void 0 ? _c : '').slice(0, 200),
                    updatedAt: formatTs((_d = d.updatedAt) !== null && _d !== void 0 ? _d : d.createdAt),
                };
            });
            return JSON.stringify({ posts: posts.slice(0, maxItems), drafts });
        }
        case 'create_app_post': {
            const caption = String((_9 = (_8 = args.caption) !== null && _8 !== void 0 ? _8 : args.text) !== null && _9 !== void 0 ? _9 : '').trim().slice(0, 2200);
            const title = String((_10 = args.title) !== null && _10 !== void 0 ? _10 : '').trim().slice(0, 140);
            const hashtags = Array.isArray(args.hashtags)
                ? args.hashtags.map((h) => String(h).replace(/^#/, '').trim()).filter(Boolean).slice(0, 15)
                : [];
            const publishNow = args.publishNow === true;
            if (!caption && !title) {
                return JSON.stringify({ ok: false, error: 'Provide a caption or title.' });
            }
            const userDoc = await db.collection('users').doc(uid).get();
            const u = (_11 = userDoc.data()) !== null && _11 !== void 0 ? _11 : {};
            const authorName = String((_14 = (_13 = (_12 = u.fullName) !== null && _12 !== void 0 ? _12 : u.displayName) !== null && _13 !== void 0 ? _13 : u.username) !== null && _14 !== void 0 ? _14 : 'Creator');
            const authorAvatar = String((_16 = (_15 = u.profilePhotoUrl) !== null && _15 !== void 0 ? _15 : u.photoUrl) !== null && _16 !== void 0 ? _16 : '');
            if (publishNow) {
                const postRef = await db.collection('posts').add({
                    authorId: uid,
                    authorName,
                    authorUsername: String((_17 = u.username) !== null && _17 !== void 0 ? _17 : ''),
                    authorAvatar,
                    title,
                    caption,
                    description: caption,
                    hashtags,
                    type: 'text_post',
                    visibility: 'public',
                    likeCount: 0,
                    commentCount: 0,
                    viewCount: 0,
                    createdVia: `ova_agent_${originDevice}`,
                    createdAt: firestore_1.FieldValue.serverTimestamp(),
                    updatedAt: firestore_1.FieldValue.serverTimestamp(),
                });
                return JSON.stringify({
                    ok: true,
                    mode: 'published',
                    postId: postRef.id,
                    caption,
                });
            }
            const draftRef = await db
                .collection('users')
                .doc(uid)
                .collection('post_drafts')
                .add({
                authorId: uid,
                title: title || caption.slice(0, 48),
                caption,
                hashtags,
                status: 'draft',
                createdVia: `ova_agent_${originDevice}`,
                createdAt: firestore_1.FieldValue.serverTimestamp(),
                updatedAt: firestore_1.FieldValue.serverTimestamp(),
            });
            return JSON.stringify({
                ok: true,
                mode: 'saved_draft',
                draftId: draftRef.id,
                title: title || caption.slice(0, 48),
                caption,
            });
        }
        case 'get_post_comments': {
            let postId = String((_18 = args.postId) !== null && _18 !== void 0 ? _18 : '').trim();
            const maxItems = Math.min(25, Math.max(1, Number((_19 = args.limit) !== null && _19 !== void 0 ? _19 : 12)));
            if (!postId) {
                const latest = await db
                    .collection('posts')
                    .where('authorId', '==', uid)
                    .limit(1)
                    .get();
                if (!latest.empty) {
                    postId = latest.docs[0].id;
                }
            }
            if (!postId) {
                return JSON.stringify({ ok: false, error: 'No post found to inspect comments.' });
            }
            const commentsSnap = await db
                .collection('posts')
                .doc(postId)
                .collection('comments')
                .orderBy('createdAt', 'desc')
                .limit(maxItems)
                .get()
                .catch(async () => db.collection('content').doc(postId).collection('comments').limit(maxItems).get());
            const comments = commentsSnap.docs.map((doc) => {
                var _a, _b, _c, _d, _e, _f;
                const d = doc.data();
                return {
                    commentId: doc.id,
                    authorId: String((_b = (_a = d.authorId) !== null && _a !== void 0 ? _a : d.userId) !== null && _b !== void 0 ? _b : ''),
                    authorName: String((_d = (_c = d.authorName) !== null && _c !== void 0 ? _c : d.username) !== null && _d !== void 0 ? _d : 'User'),
                    text: String((_f = (_e = d.text) !== null && _e !== void 0 ? _e : d.content) !== null && _f !== void 0 ? _f : '').slice(0, 400),
                    createdAt: formatTs(d.createdAt),
                };
            });
            return JSON.stringify({ ok: true, postId, comments });
        }
        case 'reply_to_post_comment': {
            const postId = String((_20 = args.postId) !== null && _20 !== void 0 ? _20 : '').trim();
            const parentCommentId = String((_21 = args.commentId) !== null && _21 !== void 0 ? _21 : '').trim();
            const text = String((_22 = args.text) !== null && _22 !== void 0 ? _22 : '').trim().slice(0, 1000);
            if (!postId || !text) {
                return JSON.stringify({ ok: false, error: 'postId and text are required.' });
            }
            const userDoc = await db.collection('users').doc(uid).get();
            const u = (_23 = userDoc.data()) !== null && _23 !== void 0 ? _23 : {};
            const authorName = String((_26 = (_25 = (_24 = u.fullName) !== null && _24 !== void 0 ? _24 : u.displayName) !== null && _25 !== void 0 ? _25 : u.username) !== null && _26 !== void 0 ? _26 : 'Creator');
            const commentRef = await db
                .collection('posts')
                .doc(postId)
                .collection('comments')
                .add({
                postId,
                authorId: uid,
                userId: uid,
                authorName,
                authorAvatar: String((_28 = (_27 = u.profilePhotoUrl) !== null && _27 !== void 0 ? _27 : u.photoUrl) !== null && _28 !== void 0 ? _28 : ''),
                text,
                parentId: parentCommentId || null,
                likeCount: 0,
                createdVia: `ova_agent_${originDevice}`,
                createdAt: firestore_1.FieldValue.serverTimestamp(),
            });
            await db
                .collection('posts')
                .doc(postId)
                .set({ commentCount: firestore_1.FieldValue.increment(1) }, { merge: true })
                .catch(() => { });
            return JSON.stringify({ ok: true, postId, commentId: commentRef.id, text });
        }
        case 'list_my_chats': {
            const maxItems = Math.min(20, Math.max(1, Number((_29 = args.limit) !== null && _29 !== void 0 ? _29 : 10)));
            const unreadOnly = args.unreadOnly === true;
            const chatsSnap = await db
                .collection('chats')
                .where('participants', 'array-contains', uid)
                .limit(30)
                .get();
            const rows = [];
            for (const doc of chatsSnap.docs) {
                const d = doc.data();
                const unreadMap = (d.unreadCounts && typeof d.unreadCounts === 'object')
                    ? d.unreadCounts
                    : {};
                const unread = Number((_30 = unreadMap[uid]) !== null && _30 !== void 0 ? _30 : 0);
                if (unreadOnly && unread <= 0)
                    continue;
                const participants = Array.isArray(d.participants)
                    ? d.participants.map((p) => String(p))
                    : [];
                let title = String((_32 = (_31 = d.title) !== null && _31 !== void 0 ? _31 : d.groupName) !== null && _32 !== void 0 ? _32 : '').trim();
                const partnerId = (_33 = participants.find((p) => p !== uid)) !== null && _33 !== void 0 ? _33 : '';
                if (!title && partnerId) {
                    const pSnap = await db.collection('users').doc(partnerId).get().catch(() => null);
                    const pd = (_34 = pSnap === null || pSnap === void 0 ? void 0 : pSnap.data()) !== null && _34 !== void 0 ? _34 : {};
                    title = String((_37 = (_36 = (_35 = pd.fullName) !== null && _35 !== void 0 ? _35 : pd.displayName) !== null && _36 !== void 0 ? _36 : pd.username) !== null && _37 !== void 0 ? _37 : 'Direct Chat');
                }
                const tsMs = (_38 = (_b = (_a = d.lastMessageTime) === null || _a === void 0 ? void 0 : _a.toMillis) === null || _b === void 0 ? void 0 : _b.call(_a)) !== null && _38 !== void 0 ? _38 : 0;
                rows.push({
                    chatId: doc.id,
                    title: title || 'Chat',
                    partnerId,
                    lastMessage: String((_39 = d.lastMessage) !== null && _39 !== void 0 ? _39 : '').slice(0, 200),
                    unreadCount: unread,
                    lastMessageAt: formatTs(d.lastMessageTime),
                    _sortMs: tsMs,
                });
            }
            rows.sort((a, b) => { var _a, _b; return Number((_a = b._sortMs) !== null && _a !== void 0 ? _a : 0) - Number((_b = a._sortMs) !== null && _b !== void 0 ? _b : 0); });
            const cleaned = rows.slice(0, maxItems).map((_a) => {
                var { _sortMs } = _a, rest = __rest(_a, ["_sortMs"]);
                return rest;
            });
            return JSON.stringify({ chats: cleaned });
        }
        case 'read_chat_messages': {
            let chatId = String((_40 = args.chatId) !== null && _40 !== void 0 ? _40 : '').trim();
            const participantQuery = String((_41 = args.participantQuery) !== null && _41 !== void 0 ? _41 : '').trim().toLowerCase();
            const maxItems = Math.min(30, Math.max(1, Number((_42 = args.limit) !== null && _42 !== void 0 ? _42 : 15)));
            if (!chatId && participantQuery) {
                const chatsSnap = await db
                    .collection('chats')
                    .where('participants', 'array-contains', uid)
                    .limit(25)
                    .get();
                for (const doc of chatsSnap.docs) {
                    const d = doc.data();
                    const title = String((_43 = d.title) !== null && _43 !== void 0 ? _43 : '').toLowerCase();
                    if (title.includes(participantQuery)) {
                        chatId = doc.id;
                        break;
                    }
                    const participants = Array.isArray(d.participants) ? d.participants : [];
                    const other = participants.find((p) => String(p) !== uid);
                    if (other) {
                        const uSnap = await db.collection('users').doc(String(other)).get().catch(() => null);
                        const ud = (_44 = uSnap === null || uSnap === void 0 ? void 0 : uSnap.data()) !== null && _44 !== void 0 ? _44 : {};
                        const hay = `${(_45 = ud.fullName) !== null && _45 !== void 0 ? _45 : ''} ${(_46 = ud.displayName) !== null && _46 !== void 0 ? _46 : ''} ${(_47 = ud.username) !== null && _47 !== void 0 ? _47 : ''}`.toLowerCase();
                        if (hay.includes(participantQuery)) {
                            chatId = doc.id;
                            break;
                        }
                    }
                }
            }
            if (!chatId) {
                return JSON.stringify({ ok: false, error: 'Provide a valid chatId or participantQuery.' });
            }
            const chatDoc = await db.collection('chats').doc(chatId).get();
            if (!chatDoc.exists) {
                return JSON.stringify({ ok: false, error: 'Chat not found.' });
            }
            const participants = Array.isArray((_c = chatDoc.data()) === null || _c === void 0 ? void 0 : _c.participants)
                ? chatDoc.data().participants.map((p) => String(p))
                : [];
            if (!participants.includes(uid)) {
                return JSON.stringify({ ok: false, error: 'Access denied for this chat.' });
            }
            const msgSnap = await db
                .collection('chats')
                .doc(chatId)
                .collection('messages')
                .orderBy('timestamp', 'desc')
                .limit(maxItems)
                .get();
            const messages = msgSnap.docs.reverse().map((doc) => {
                var _a, _b, _c, _d;
                const d = doc.data();
                const encrypted = d.isEncrypted === true;
                return {
                    messageId: doc.id,
                    senderId: String((_a = d.senderId) !== null && _a !== void 0 ? _a : ''),
                    fromMe: String((_b = d.senderId) !== null && _b !== void 0 ? _b : '') === uid,
                    text: encrypted
                        ? '[End-to-End Encrypted Message — view directly in Chat screen]'
                        : String((_c = d.text) !== null && _c !== void 0 ? _c : '').slice(0, 500),
                    mediaType: (_d = d.mediaType) !== null && _d !== void 0 ? _d : null,
                    timestamp: formatTs(d.timestamp),
                };
            });
            return JSON.stringify({ ok: true, chatId, messages });
        }
        case 'send_app_message': {
            let chatId = String((_48 = args.chatId) !== null && _48 !== void 0 ? _48 : '').trim();
            const recipientQuery = String((_49 = args.recipientQuery) !== null && _49 !== void 0 ? _49 : '').trim().toLowerCase();
            const text = String((_50 = args.text) !== null && _50 !== void 0 ? _50 : '').trim().slice(0, 2000);
            if (!text) {
                return JSON.stringify({ ok: false, error: 'Message text is required.' });
            }
            if (!chatId && recipientQuery) {
                const chatsSnap = await db
                    .collection('chats')
                    .where('participants', 'array-contains', uid)
                    .limit(25)
                    .get();
                for (const doc of chatsSnap.docs) {
                    const d = doc.data();
                    const participants = Array.isArray(d.participants) ? d.participants : [];
                    const other = participants.find((p) => String(p) !== uid);
                    if (other) {
                        const uSnap = await db.collection('users').doc(String(other)).get().catch(() => null);
                        const ud = (_51 = uSnap === null || uSnap === void 0 ? void 0 : uSnap.data()) !== null && _51 !== void 0 ? _51 : {};
                        const hay = `${(_52 = ud.fullName) !== null && _52 !== void 0 ? _52 : ''} ${(_53 = ud.displayName) !== null && _53 !== void 0 ? _53 : ''} ${(_54 = ud.username) !== null && _54 !== void 0 ? _54 : ''} ${(_55 = d.title) !== null && _55 !== void 0 ? _55 : ''}`.toLowerCase();
                        if (hay.includes(recipientQuery)) {
                            chatId = doc.id;
                            break;
                        }
                    }
                }
            }
            if (!chatId) {
                return JSON.stringify({
                    ok: false,
                    error: 'Could not resolve target chat. Call list_my_chats first to get chatId.',
                });
            }
            const chatRef = db.collection('chats').doc(chatId);
            const chatSnap = await chatRef.get();
            if (!chatSnap.exists) {
                return JSON.stringify({ ok: false, error: 'Chat thread does not exist.' });
            }
            const chatData = (_56 = chatSnap.data()) !== null && _56 !== void 0 ? _56 : {};
            const participants = Array.isArray(chatData.participants)
                ? chatData.participants.map((p) => String(p))
                : [];
            if (!participants.includes(uid)) {
                return JSON.stringify({ ok: false, error: 'Not a participant of this chat.' });
            }
            const msgId = crypto.randomUUID();
            const nowTs = firestore_1.Timestamp.now();
            const unreadCounts = Object.assign({}, ((_57 = chatData.unreadCounts) !== null && _57 !== void 0 ? _57 : {}));
            for (const p of participants) {
                if (p !== uid) {
                    unreadCounts[p] = Number((_58 = unreadCounts[p]) !== null && _58 !== void 0 ? _58 : 0) + 1;
                }
            }
            await chatRef.collection('messages').doc(msgId).set({
                id: msgId,
                senderId: uid,
                text,
                timestamp: nowTs,
                readBy: [uid],
                isEncrypted: false,
                mediaEncrypted: false,
                forwarded: false,
            });
            await chatRef.set({
                lastMessage: text,
                lastMessageTime: nowTs,
                lastMessageSenderId: uid,
                unreadCounts,
            }, { merge: true });
            return JSON.stringify({ ok: true, chatId, messageId: msgId, sentText: text });
        }
        case 'list_notifications': {
            const maxItems = Math.min(25, Math.max(1, Number((_59 = args.limit) !== null && _59 !== void 0 ? _59 : 12)));
            const unreadOnly = args.unreadOnly === true;
            const [byRecipient, byUser, userSub] = await Promise.all([
                db.collection('notifications').where('recipientId', '==', uid).limit(25).get().catch(() => null),
                db.collection('notifications').where('userId', '==', uid).limit(25).get().catch(() => null),
                db.collection('users').doc(uid).collection('notifications').limit(20).get().catch(() => null),
            ]);
            const seen = new Set();
            const items = [];
            for (const snap of [byRecipient, byUser, userSub]) {
                for (const doc of (_60 = snap === null || snap === void 0 ? void 0 : snap.docs) !== null && _60 !== void 0 ? _60 : []) {
                    if (seen.has(doc.id))
                        continue;
                    seen.add(doc.id);
                    const d = doc.data();
                    const isRead = d.isRead === true || d.read === true;
                    if (unreadOnly && isRead)
                        continue;
                    const tsMs = (_62 = (_61 = (_e = (_d = d.createdAt) === null || _d === void 0 ? void 0 : _d.toMillis) === null || _e === void 0 ? void 0 : _e.call(_d)) !== null && _61 !== void 0 ? _61 : (_g = (_f = d.timestamp) === null || _f === void 0 ? void 0 : _f.toMillis) === null || _g === void 0 ? void 0 : _g.call(_f)) !== null && _62 !== void 0 ? _62 : 0;
                    items.push({
                        id: doc.id,
                        title: String((_64 = (_63 = d.title) !== null && _63 !== void 0 ? _63 : d.type) !== null && _64 !== void 0 ? _64 : 'Notification').slice(0, 140),
                        body: String((_66 = (_65 = d.body) !== null && _65 !== void 0 ? _65 : d.message) !== null && _66 !== void 0 ? _66 : '').slice(0, 240),
                        category: String((_68 = (_67 = d.category) !== null && _67 !== void 0 ? _67 : d.type) !== null && _68 !== void 0 ? _68 : 'general'),
                        isRead,
                        deepLink: (_69 = d.deepLink) !== null && _69 !== void 0 ? _69 : null,
                        createdAt: formatTs((_70 = d.createdAt) !== null && _70 !== void 0 ? _70 : d.timestamp),
                        _sortMs: tsMs,
                    });
                }
            }
            items.sort((a, b) => { var _a, _b; return Number((_a = b._sortMs) !== null && _a !== void 0 ? _a : 0) - Number((_b = a._sortMs) !== null && _b !== void 0 ? _b : 0); });
            return JSON.stringify({
                notifications: items.slice(0, maxItems).map((_a) => {
                    var { _sortMs } = _a, r = __rest(_a, ["_sortMs"]);
                    return r;
                }),
            });
        }
        case 'mark_notifications_read': {
            const ids = Array.isArray(args.notificationIds)
                ? args.notificationIds.map((x) => String(x)).filter(Boolean)
                : [];
            const markAll = args.markAll === true || ids.length === 0;
            const batch = db.batch();
            let count = 0;
            if (markAll) {
                const unreadSnap = await db
                    .collection('notifications')
                    .where('recipientId', '==', uid)
                    .where('isRead', '==', false)
                    .limit(40)
                    .get();
                for (const doc of unreadSnap.docs) {
                    batch.update(doc.ref, { isRead: true, readAt: firestore_1.FieldValue.serverTimestamp() });
                    count++;
                }
            }
            else {
                for (const id of ids.slice(0, 30)) {
                    const ref = db.collection('notifications').doc(id);
                    const snap = await ref.get();
                    if (snap.exists && (snap.get('recipientId') === uid || snap.get('userId') === uid)) {
                        batch.update(ref, { isRead: true, readAt: firestore_1.FieldValue.serverTimestamp() });
                        count++;
                    }
                }
            }
            if (count > 0)
                await batch.commit();
            return JSON.stringify({ ok: true, markedReadCount: count });
        }
        case 'create_reminder': {
            const title = String((_72 = (_71 = args.title) !== null && _71 !== void 0 ? _71 : args.text) !== null && _72 !== void 0 ? _72 : '').trim().slice(0, 240);
            if (!title) {
                return JSON.stringify({ ok: false, error: 'Reminder title is required.' });
            }
            const dueRaw = String((_73 = args.dueAtIso) !== null && _73 !== void 0 ? _73 : '').trim();
            const parsedDate = dueRaw ? new Date(dueRaw) : new Date(Date.now() + 3600 * 1000);
            const validDate = isNaN(parsedDate.getTime())
                ? new Date(Date.now() + 3600 * 1000)
                : parsedDate;
            const remRef = await db
                .collection('users')
                .doc(uid)
                .collection('reminders')
                .add({
                title,
                text: title,
                dueAt: firestore_1.Timestamp.fromDate(validDate),
                remindAt: firestore_1.Timestamp.fromDate(validDate),
                completed: false,
                done: false,
                originDevice,
                createdAt: firestore_1.FieldValue.serverTimestamp(),
            });
            return JSON.stringify({
                ok: true,
                reminderId: remRef.id,
                title,
                dueAt: validDate.toISOString(),
            });
        }
        case 'list_reminders': {
            const snap = await db
                .collection('users')
                .doc(uid)
                .collection('reminders')
                .limit(15)
                .get();
            const reminders = snap.docs.map((doc) => {
                var _a, _b, _c, _d, _e;
                const d = doc.data();
                return {
                    id: doc.id,
                    title: String((_b = (_a = d.title) !== null && _a !== void 0 ? _a : d.text) !== null && _b !== void 0 ? _b : ''),
                    completed: Boolean((_d = (_c = d.completed) !== null && _c !== void 0 ? _c : d.done) !== null && _d !== void 0 ? _d : false),
                    dueAt: formatTs((_e = d.dueAt) !== null && _e !== void 0 ? _e : d.remindAt),
                };
            });
            return JSON.stringify({ reminders });
        }
        case 'list_studio_projects': {
            const [projSnap, globalProjSnap] = await Promise.all([
                db.collection('users').doc(uid).collection('projects').limit(12).get().catch(() => null),
                db.collection('projects').where('ownerId', '==', uid).limit(12).get().catch(() => null),
            ]);
            const seen = new Set();
            const projects = [];
            for (const snap of [projSnap, globalProjSnap]) {
                for (const doc of (_74 = snap === null || snap === void 0 ? void 0 : snap.docs) !== null && _74 !== void 0 ? _74 : []) {
                    if (seen.has(doc.id))
                        continue;
                    seen.add(doc.id);
                    const d = doc.data();
                    projects.push({
                        projectId: doc.id,
                        title: String((_76 = (_75 = d.title) !== null && _75 !== void 0 ? _75 : d.name) !== null && _76 !== void 0 ? _76 : 'Untitled Project'),
                        status: String((_77 = d.status) !== null && _77 !== void 0 ? _77 : 'active'),
                        category: String((_78 = d.category) !== null && _78 !== void 0 ? _78 : 'studio'),
                        updatedAt: formatTs((_79 = d.updatedAt) !== null && _79 !== void 0 ? _79 : d.createdAt),
                    });
                }
            }
            return JSON.stringify({ projects });
        }
        case 'list_connected_computers': {
            const snap = await db
                .collection('registered_computers')
                .where('owner_uid', '==', uid)
                .limit(10)
                .get();
            const nowMs = Date.now();
            const computers = snap.docs.map((doc) => {
                var _a, _b;
                var _c, _d, _e, _f;
                const d = doc.data();
                const lastSeenDate = (_c = (_b = (_a = d.last_seen) === null || _a === void 0 ? void 0 : _a.toDate) === null || _b === void 0 ? void 0 : _b.call(_a)) !== null && _c !== void 0 ? _c : null;
                const fresh = lastSeenDate ? nowMs - lastSeenDate.getTime() < 75000 : Boolean(d.desktop_connected);
                return {
                    deviceId: doc.id,
                    computerName: String((_d = d.computer_name) !== null && _d !== void 0 ? _d : 'Workstation'),
                    os: String((_e = d.os) !== null && _e !== void 0 ? _e : 'macOS'),
                    isOnline: Boolean(d.desktop_connected) && d.status !== 'offline' && fresh,
                    activeWindow: String((_f = d.active_window) !== null && _f !== void 0 ? _f : 'Desktop'),
                    lastSeen: formatTs(d.last_seen),
                };
            });
            return JSON.stringify({ computers });
        }
        case 'dispatch_computer_command': {
            let targetDeviceId = String((_80 = args.deviceId) !== null && _80 !== void 0 ? _80 : '').trim();
            const command = String((_81 = args.command) !== null && _81 !== void 0 ? _81 : '').trim();
            const payload = args.payload && typeof args.payload === 'object' ? args.payload : {};
            if (!command) {
                return JSON.stringify({ ok: false, error: 'command is required.' });
            }
            if (!targetDeviceId) {
                const snap = await db
                    .collection('registered_computers')
                    .where('owner_uid', '==', uid)
                    .limit(6)
                    .get();
                if (!snap.empty) {
                    const onlineDoc = snap.docs.find((d) => d.get('desktop_connected') === true);
                    targetDeviceId = (onlineDoc !== null && onlineDoc !== void 0 ? onlineDoc : snap.docs[0]).id;
                }
            }
            if (!targetDeviceId) {
                return JSON.stringify({
                    ok: false,
                    error: 'No linked computer found on this Oneova account.',
                });
            }
            const compRef = db.collection('registered_computers').doc(targetDeviceId);
            const compSnap = await compRef.get();
            if (!compSnap.exists || compSnap.get('owner_uid') !== uid) {
                return JSON.stringify({
                    ok: false,
                    error: 'Unauthorized or unknown target computer.',
                });
            }
            const cmdRef = await compRef.collection('commands').add({
                software_id: 'system',
                command,
                payload_encrypted: '',
                payload,
                timestamp: firestore_1.FieldValue.serverTimestamp(),
                status: 'pending',
                dispatched_by: `ova_agent_${originDevice}`,
            });
            return JSON.stringify({
                ok: true,
                deviceId: targetDeviceId,
                computerName: String((_82 = compSnap.get('computer_name')) !== null && _82 !== void 0 ? _82 : 'Workstation'),
                commandId: cmdRef.id,
                command,
            });
        }
        case 'save_memory': {
            const key = String((_83 = args.key) !== null && _83 !== void 0 ? _83 : 'general').trim().slice(0, 80);
            const content = String((_84 = args.content) !== null && _84 !== void 0 ? _84 : '').trim().slice(0, 1200);
            if (!content) {
                return JSON.stringify({ ok: false, error: 'Memory content cannot be empty.' });
            }
            const memId = key.replace(/[^a-zA-Z0-9_-]/g, '_').toLowerCase() || 'general';
            await db
                .collection('users')
                .doc(uid)
                .collection('agent_memories')
                .doc(memId)
                .set({
                key,
                content,
                updatedAt: new Date(),
                originDevice,
            }, { merge: true });
            return JSON.stringify({ ok: true, key, content });
        }
        case 'recall_memories': {
            const q = String((_85 = args.query) !== null && _85 !== void 0 ? _85 : '').trim().toLowerCase();
            const memSnap = await db
                .collection('users')
                .doc(uid)
                .collection('agent_memories')
                .orderBy('updatedAt', 'desc')
                .limit(30)
                .get();
            const matched = memSnap.docs
                .map((d) => { var _a, _b; return ({
                key: String((_a = d.get('key')) !== null && _a !== void 0 ? _a : d.id),
                content: String((_b = d.get('content')) !== null && _b !== void 0 ? _b : ''),
            }); })
                .filter((m) => !q ||
                m.key.toLowerCase().includes(q) ||
                m.content.toLowerCase().includes(q));
            return JSON.stringify({ memories: matched });
        }
        case 'delete_memory': {
            const key = String((_86 = args.key) !== null && _86 !== void 0 ? _86 : '').trim();
            if (!key)
                return JSON.stringify({ ok: false, error: 'key is required.' });
            const memId = key.replace(/[^a-zA-Z0-9_-]/g, '_').toLowerCase();
            await db
                .collection('users')
                .doc(uid)
                .collection('agent_memories')
                .doc(memId)
                .delete();
            return JSON.stringify({ ok: true, deletedKey: key });
        }
        default:
            return JSON.stringify({ ok: false, error: `Unsupported cloud tool: ${tc.name}` });
    }
}
async function runModelJsonTurn(params) {
    var _a, _b, _c;
    var _d, _e, _f;
    let rawJsonText = '';
    try {
        const thinkingBudget = params.effort === 'deep_think' ? 2048 : params.effort === 'fast' ? 0 : 512;
        const vertexResp = await (0, vertexAi_1.generateVertexContent)({
            contents: params.contents,
            config: {
                systemInstruction: params.systemInstruction,
                temperature: params.effort === 'deep_think' ? 0.3 : 0.38,
                maxOutputTokens: 4096,
                responseMimeType: 'application/json',
                thinkingConfig: { thinkingBudget },
            },
        });
        rawJsonText = String((_d = vertexResp.text) !== null && _d !== void 0 ? _d : '').trim();
    }
    catch (vertexErr) {
        console.warn('[ovaAgentExecuteTurn] Vertex fallback check:', (_e = vertexErr === null || vertexErr === void 0 ? void 0 : vertexErr.message) !== null && _e !== void 0 ? _e : vertexErr);
        const orKey = openRouterSecret.value();
        if (!orKey) {
            throw new https_1.HttpsError('unavailable', 'Oneova Agent AI engine is temporarily unavailable.');
        }
        const orResp = await fetch('https://openrouter.ai/api/v1/chat/completions', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                Authorization: `Bearer ${orKey}`,
                'HTTP-Referer': 'https://mpepe-2b4bd.web.app',
                'X-Title': 'Oneova Agent',
            },
            body: JSON.stringify({
                model: 'google/gemini-2.5-flash',
                response_format: { type: 'json_object' },
                messages: [
                    { role: 'system', content: params.systemInstruction },
                    ...params.contents.map((c) => ({
                        role: c.role === 'model' ? 'assistant' : 'user',
                        content: c.parts[0].text,
                    })),
                ],
            }),
        });
        if (!orResp.ok) {
            throw new https_1.HttpsError('unavailable', `AI upstream returned HTTP ${orResp.status}.`);
        }
        const orData = (await orResp.json());
        rawJsonText = String((_f = (_c = (_b = (_a = orData === null || orData === void 0 ? void 0 : orData.choices) === null || _a === void 0 ? void 0 : _a[0]) === null || _b === void 0 ? void 0 : _b.message) === null || _c === void 0 ? void 0 : _c.content) !== null && _f !== void 0 ? _f : '').trim();
    }
    try {
        return JSON.parse(sanitizeJsonText(rawJsonText));
    }
    catch (_g) {
        return {
            thinking: ['Synthesized direct response from agent output.'],
            reply: rawJsonText || 'Ready for your next instruction.',
        };
    }
}
exports.ovaAgentExecuteTurn = (0, https_1.onCall)({
    secrets: [openRouterSecret],
    enforceAppCheck: false,
    timeoutSeconds: 120,
    memory: '512MiB',
}, async (request) => {
    var _a, _b, _c;
    var _d, _e, _f, _g, _h, _j, _k, _l, _m, _o, _p, _q, _r, _s, _t, _u, _v, _w, _x, _y, _z, _0;
    if (!request.auth) {
        throw new https_1.HttpsError('unauthenticated', 'Sign in to use Oneova Agent.');
    }
    const callerUid = request.auth.uid;
    const data = ((_d = request.data) !== null && _d !== void 0 ? _d : {});
    const mode = String((_e = data.mode) !== null && _e !== void 0 ? _e : 'agent_turn').trim();
    const deviceId = String((_f = data.deviceId) !== null && _f !== void 0 ? _f : '').trim().slice(0, 200);
    // -------------------------------------------------------------------------
    // MODE A: Wispr Flow Multimodal Audio Transcription + AI Auto-Polish
    // -------------------------------------------------------------------------
    if (mode === 'wispr_transcribe_and_tidy' || mode === 'wispr_tidy') {
        await verifyCallerAndQuota(callerUid, deviceId, 'ova_wispr_flow', 180);
        const style = String((_g = data.style) !== null && _g !== void 0 ? _g : 'auto').slice(0, 40);
        const activeWindow = String((_h = data.activeWindow) !== null && _h !== void 0 ? _h : '').slice(0, 120);
        const commandInstruction = data.commandInstruction
            ? String(data.commandInstruction).slice(0, 400)
            : undefined;
        const systemInstruction = buildWisprSystemPrompt({
            style,
            activeWindow,
            commandInstruction,
        });
        if (mode === 'wispr_transcribe_and_tidy') {
            const audioBase64 = String((_j = data.audioBase64) !== null && _j !== void 0 ? _j : '').trim();
            const mimeType = String((_k = data.mimeType) !== null && _k !== void 0 ? _k : 'audio/mp4').trim() || 'audio/mp4';
            if (!audioBase64) {
                return { rawTranscript: '', polishedText: '' };
            }
            if (audioBase64.length > 9500000) {
                throw new https_1.HttpsError('invalid-argument', 'Voice clip is too large (max ~7 MB).');
            }
            const transcribePrompt = commandInstruction
                ? `Listen to the spoken audio and apply the transformation instruction ("${commandInstruction}"). If there is only silence or background noise, return an empty string.`
                : 'Transcribe this spoken audio accurately in the language spoken, applying the Ova Wispr Flow cleanup rules (remove filler words, apply spoken self-corrections, add crisp punctuation). If there is no intelligible speech or only silence, return an empty string.';
            const vertexResp = await (0, vertexAi_1.generateVertexContent)({
                contents: [
                    {
                        role: 'user',
                        parts: [
                            { text: transcribePrompt },
                            { inlineData: { mimeType, data: audioBase64 } },
                        ],
                    },
                ],
                config: {
                    systemInstruction,
                    temperature: 0.15,
                    maxOutputTokens: 2048,
                },
            });
            const cleaned = String((_l = vertexResp.text) !== null && _l !== void 0 ? _l : '').trim();
            return {
                rawTranscript: cleaned,
                polishedText: cleaned,
            };
        }
        const rawText = String((_m = data.text) !== null && _m !== void 0 ? _m : '').trim().slice(0, 8000);
        if (!rawText) {
            return { rawTranscript: '', polishedText: '' };
        }
        if (!commandInstruction && rawText.split(/\s+/).length < 2) {
            const cap = rawText.charAt(0).toUpperCase() + rawText.slice(1);
            return { rawTranscript: rawText, polishedText: cap };
        }
        try {
            const vertexResp = await (0, vertexAi_1.generateVertexContent)({
                contents: [{ role: 'user', parts: [{ text: rawText }] }],
                config: {
                    systemInstruction,
                    temperature: 0.15,
                    maxOutputTokens: 2048,
                },
            });
            const out = String((_o = vertexResp.text) !== null && _o !== void 0 ? _o : '').trim();
            return {
                rawTranscript: rawText,
                polishedText: out || rawText,
            };
        }
        catch (vertexErr) {
            console.warn('[ovaAgentExecuteTurn] Wispr Vertex fallback check:', (_p = vertexErr === null || vertexErr === void 0 ? void 0 : vertexErr.message) !== null && _p !== void 0 ? _p : vertexErr);
            const orKey = openRouterSecret.value();
            if (orKey) {
                try {
                    const orResp = await fetch('https://openrouter.ai/api/v1/chat/completions', {
                        method: 'POST',
                        headers: {
                            'Content-Type': 'application/json',
                            Authorization: `Bearer ${orKey}`,
                            'HTTP-Referer': 'https://mpepe-2b4bd.web.app',
                            'X-Title': 'Oneova Wispr Flow',
                        },
                        body: JSON.stringify({
                            model: 'google/gemini-2.5-flash',
                            messages: [
                                { role: 'system', content: systemInstruction },
                                { role: 'user', content: rawText },
                            ],
                            temperature: 0.15,
                            max_tokens: 2048,
                        }),
                    });
                    if (orResp.ok) {
                        const orData = (await orResp.json());
                        const out = String((_q = (_c = (_b = (_a = orData === null || orData === void 0 ? void 0 : orData.choices) === null || _a === void 0 ? void 0 : _a[0]) === null || _b === void 0 ? void 0 : _b.message) === null || _c === void 0 ? void 0 : _c.content) !== null && _q !== void 0 ? _q : '').trim();
                        if (out) {
                            return {
                                rawTranscript: rawText,
                                polishedText: out,
                            };
                        }
                    }
                }
                catch (orErr) {
                    console.warn('[ovaAgentExecuteTurn] Wispr OpenRouter fallback error:', orErr);
                }
            }
            return {
                rawTranscript: rawText,
                polishedText: rawText,
            };
        }
    }
    // -------------------------------------------------------------------------
    // MODE B: Full Agentic Turn (Shared Cloud App Data + Autonomous Computer-Use)
    // -------------------------------------------------------------------------
    const quotaUid = await verifyCallerAndQuota(callerUid, deviceId, 'ova_agent_turn', 140);
    const [memories, accountSummary] = await Promise.all([
        (async () => {
            try {
                const memSnap = await (0, firestore_1.getFirestore)()
                    .collection('users')
                    .doc(quotaUid)
                    .collection('agent_memories')
                    .orderBy('updatedAt', 'desc')
                    .limit(30)
                    .get();
                return memSnap.docs.map((doc) => {
                    var _a, _b;
                    const d = doc.data();
                    return {
                        id: doc.id,
                        key: String((_a = d.key) !== null && _a !== void 0 ? _a : doc.id),
                        content: String((_b = d.content) !== null && _b !== void 0 ? _b : ''),
                    };
                });
            }
            catch (_a) {
                return [];
            }
        })(),
        loadAccountContextSnapshot(quotaUid),
    ]);
    const rawMessages = Array.isArray(data.messages)
        ? data.messages.slice(-28)
        : [];
    const fallbackPrompt = String((_r = data.prompt) !== null && _r !== void 0 ? _r : '').trim().slice(0, 14000);
    const formattedContents = rawMessages
        .map((m) => {
        var _a, _b;
        const role = String((_a = m.role) !== null && _a !== void 0 ? _a : 'user') === 'assistant' ? 'model' : 'user';
        const text = String((_b = m.content) !== null && _b !== void 0 ? _b : '').trim().slice(0, 14000);
        return { role, parts: [{ text }] };
    })
        .filter((m) => m.parts[0].text.length > 0);
    if (formattedContents.length === 0 && fallbackPrompt.length > 0) {
        formattedContents.push({ role: 'user', parts: [{ text: fallbackPrompt }] });
    }
    if (formattedContents.length === 0) {
        throw new https_1.HttpsError('invalid-argument', 'Conversation messages are required.');
    }
    const agentMode = String((_s = data.agentMode) !== null && _s !== void 0 ? _s : 'orchestrator').slice(0, 40);
    const effort = String((_t = data.effort) !== null && _t !== void 0 ? _t : 'balanced').slice(0, 30);
    const originDevice = String((_u = data.originDevice) !== null && _u !== void 0 ? _u : 'mobile').slice(0, 30);
    const phase = String((_v = data.phase) !== null && _v !== void 0 ? _v : 'initial').slice(0, 40);
    const fullComputerAccess = data.fullComputerAccess === true;
    const loopIteration = typeof data.loopIteration === 'number'
        ? Math.max(0, Math.min(4, Math.floor(data.loopIteration)))
        : 0;
    const screenContextLabel = data.screenContextLabel
        ? String(data.screenContextLabel).slice(0, 200)
        : undefined;
    const webSearch = data.webSearch === true;
    const workstationContext = data.workstationContext && typeof data.workstationContext === 'object'
        ? data.workstationContext
        : { connected: false };
    const wsConnected = Boolean(workstationContext.connected);
    const canEmitCloudTools = phase !== 'post_tool_synthesis' && loopIteration < 3;
    const canEmitMacTools = wsConnected && canEmitCloudTools;
    const systemInstruction = buildSystemInstruction({
        agentMode,
        effort,
        originDevice,
        phase,
        fullComputerAccess,
        loopIteration,
        workstationContext,
        accountSummary,
        screenContextLabel,
        webSearch,
        memories,
    });
    let parsed = await runModelJsonTurn({
        contents: formattedContents,
        systemInstruction,
        effort,
    });
    const rawToolArray = Array.isArray(parsed.toolCalls) ? parsed.toolCalls : [];
    const toolCalls = !canEmitCloudTools
        ? []
        : rawToolArray
            .filter((tc) => {
            var _a;
            const name = String((_a = tc === null || tc === void 0 ? void 0 : tc.name) !== null && _a !== void 0 ? _a : '');
            if (CLOUD_APP_TOOLS.has(name))
                return true;
            if (canEmitMacTools && MAC_LOCAL_TOOLS.has(name))
                return true;
            return false;
        })
            .slice(0, 6)
            .map((tc, idx) => {
            var _a, _b, _c, _d;
            const name = String(tc.name);
            const argsObj = (tc === null || tc === void 0 ? void 0 : tc.args) && typeof tc.args === 'object' && !Array.isArray(tc.args)
                ? tc.args
                : {};
            const cmdStr = String((_a = argsObj.command) !== null && _a !== void 0 ? _a : '');
            const isCatastrophic = name === 'run_terminal_command' &&
                CATASTROPHIC_SHELL_PATTERNS.some((rx) => rx.test(cmdStr));
            let risk = 'safe';
            if (isCatastrophic) {
                risk = 'approval_required';
            }
            else if (!fullComputerAccess && MAC_LOCAL_TOOLS.has(name)) {
                const combo = String((_b = argsObj.combo) !== null && _b !== void 0 ? _b : '').toLowerCase();
                const destructiveHotkey = (name === 'send_mac_hotkey' || name === 'keyboard_action') &&
                    (combo.includes('cmd+q') || combo.includes('cmd+delete'));
                if (SUPERVISED_APPROVAL_TOOLS.has(name) ||
                    destructiveHotkey ||
                    (tc === null || tc === void 0 ? void 0 : tc.risk) === 'approval_required') {
                    risk = 'approval_required';
                }
            }
            return {
                id: String((_c = tc === null || tc === void 0 ? void 0 : tc.id) !== null && _c !== void 0 ? _c : `tc_${crypto.randomBytes(4).toString('hex')}_${idx}`),
                name,
                title: String((_d = tc === null || tc === void 0 ? void 0 : tc.title) !== null && _d !== void 0 ? _d : name.replace(/_/g, ' ')).slice(0, 140),
                args: argsObj,
                risk,
            };
        });
    // Execute all CLOUD_APP_TOOLS immediately on the server against real Firestore data!
    const executedCloudSummaries = [];
    let hasPendingMacTools = false;
    for (const tc of toolCalls) {
        if (CLOUD_APP_TOOLS.has(tc.name)) {
            const started = Date.now();
            try {
                const out = await executeCloudAppTool(quotaUid, originDevice, tc);
                tc.status = 'completed';
                tc.output = out.slice(0, 4000);
                tc.durationMs = Date.now() - started;
                executedCloudSummaries.push(`Tool "${tc.name}" (${tc.title}) -> ${tc.output}`);
            }
            catch (err) {
                tc.status = 'error';
                tc.output = JSON.stringify({
                    ok: false,
                    error: String((_w = err === null || err === void 0 ? void 0 : err.message) !== null && _w !== void 0 ? _w : err),
                });
                tc.durationMs = Date.now() - started;
                executedCloudSummaries.push(`Tool "${tc.name}" failed -> ${tc.output}`);
            }
        }
        else {
            hasPendingMacTools = true;
        }
    }
    // If cloud/app tools ran and there are no pending Mac-local tools waiting on
    // the desktop client, perform an immediate server-side synthesis pass so the
    // user gets both the completed tool cards AND the final data-grounded answer!
    if (executedCloudSummaries.length > 0 && !hasPendingMacTools) {
        const synthSystem = buildSystemInstruction({
            agentMode,
            effort: 'fast',
            originDevice,
            phase: 'post_tool_synthesis',
            fullComputerAccess,
            loopIteration: loopIteration + 1,
            workstationContext,
            accountSummary,
            screenContextLabel,
            webSearch,
            memories,
        });
        const synthContents = [
            ...formattedContents,
            {
                role: 'user',
                parts: [
                    {
                        text: `Real Oneova backend tool execution results:\n` +
                            executedCloudSummaries.join('\n\n') +
                            `\n\nNow write the complete, accurate final response for the user grounded in these real results, with "toolCalls": [].`,
                    },
                ],
            },
        ];
        try {
            const synthParsed = await runModelJsonTurn({
                contents: synthContents,
                systemInstruction: synthSystem,
                effort: 'fast',
            });
            parsed = Object.assign(Object.assign(Object.assign({}, parsed), synthParsed), { thinking: [
                    ...(Array.isArray(parsed.thinking) ? parsed.thinking : []),
                    ...(Array.isArray(synthParsed.thinking) ? synthParsed.thinking : []),
                ].slice(0, 8) });
        }
        catch (synthErr) {
            console.warn('[ovaAgentExecuteTurn] Cloud tool synthesis fallback:', synthErr);
        }
    }
    const thinking = Array.isArray(parsed.thinking)
        ? parsed.thinking.map((s) => String(s !== null && s !== void 0 ? s : '').trim()).filter(Boolean).slice(0, 8)
        : ['Analyzed request context and active account state.'];
    const rawSub = parsed.subagent && typeof parsed.subagent === 'object' ? parsed.subagent : {};
    const subagent = {
        id: String((_x = rawSub.id) !== null && _x !== void 0 ? _x : (agentMode === 'orchestrator' ? 'computer_use' : agentMode)).slice(0, 40),
        label: String((_y = rawSub.label) !== null && _y !== void 0 ? _y : 'Ova Orchestrator').slice(0, 60),
        role: String((_z = rawSub.role) !== null && _z !== void 0 ? _z : 'Shared account & computer-use intelligence').slice(0, 100),
    };
    const plan = Array.isArray(parsed.plan)
        ? parsed.plan.slice(0, 8).map((item, idx) => {
            var _a, _b, _c;
            const st = String((_a = item === null || item === void 0 ? void 0 : item.status) !== null && _a !== void 0 ? _a : 'pending');
            return {
                id: String((_b = item === null || item === void 0 ? void 0 : item.id) !== null && _b !== void 0 ? _b : `step_${idx + 1}`).slice(0, 32),
                title: String((_c = item === null || item === void 0 ? void 0 : item.title) !== null && _c !== void 0 ? _c : `Step ${idx + 1}`).slice(0, 180),
                status: !hasPendingMacTools && executedCloudSummaries.length > 0
                    ? 'completed'
                    : st === 'completed' || st === 'in_progress'
                        ? st
                        : 'pending',
            };
        })
        : [];
    const artifacts = Array.isArray(parsed.artifacts)
        ? parsed.artifacts
            .filter((a) => { var _a; return String((_a = a === null || a === void 0 ? void 0 : a.content) !== null && _a !== void 0 ? _a : '').trim().length > 0; })
            .slice(0, 4)
            .map((a, idx) => { var _a, _b, _c, _d; return ({
            id: String((_a = a === null || a === void 0 ? void 0 : a.id) !== null && _a !== void 0 ? _a : `art_${idx + 1}`).slice(0, 40),
            title: String((_b = a === null || a === void 0 ? void 0 : a.title) !== null && _b !== void 0 ? _b : `Artifact ${idx + 1}`).slice(0, 120),
            kind: ['code', 'markdown', 'plan', 'script', 'command'].includes(String(a === null || a === void 0 ? void 0 : a.kind))
                ? String(a.kind)
                : 'markdown',
            language: String((_c = a === null || a === void 0 ? void 0 : a.language) !== null && _c !== void 0 ? _c : 'markdown').slice(0, 30),
            content: String((_d = a === null || a === void 0 ? void 0 : a.content) !== null && _d !== void 0 ? _d : '').slice(0, 24000),
        }); })
        : [];
    const reply = String((_0 = parsed.reply) !== null && _0 !== void 0 ? _0 : '').trim().slice(0, 16000) ||
        (hasPendingMacTools
            ? 'Executing autonomous workstation steps...'
            : 'Completed.');
    const followUps = Array.isArray(parsed.followUps)
        ? parsed.followUps
            .map((f) => String(f !== null && f !== void 0 ? f : '').trim())
            .filter(Boolean)
            .slice(0, 4)
        : [];
    return {
        thinking,
        subagent,
        plan,
        toolCalls,
        artifacts,
        reply,
        followUps,
    };
});
//# sourceMappingURL=ovaAgentBridge.js.map