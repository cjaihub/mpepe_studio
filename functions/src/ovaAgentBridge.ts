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
import * as crypto from 'crypto';
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import { FieldValue, Timestamp, getFirestore } from 'firebase-admin/firestore';
import { generateVertexContent } from './vertexAi';
import { limit } from './guard/protect';

const openRouterSecret = defineSecret('OPENROUTER_API_KEY');

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

interface RawTurnInputMessage {
  role?: unknown;
  content?: unknown;
}

interface NormalizedToolCall {
  id: string;
  name: string;
  title: string;
  args: Record<string, any>;
  risk: 'safe' | 'approval_required';
  status?: string;
  output?: string;
  durationMs?: number;
}

function sanitizeJsonText(raw: string): string {
  const trimmed = raw.trim();
  if (trimmed.startsWith('```')) {
    return trimmed
      .replace(/^```(?:json)?\s*/i, '')
      .replace(/\s*```$/i, '')
      .trim();
  }
  return trimmed;
}

function formatTs(raw: any): string {
  if (!raw) return '';
  if (raw instanceof Timestamp) return raw.toDate().toISOString();
  if (raw instanceof Date) return raw.toISOString();
  if (typeof raw?.toDate === 'function') {
    try {
      return raw.toDate().toISOString();
    } catch {
      return '';
    }
  }
  return String(raw);
}

function buildWisprSystemPrompt(params: {
  style: string;
  activeWindow: string;
  commandInstruction?: string;
}): string {
  const { style, activeWindow, commandInstruction } = params;
  const appHint = activeWindow
    ? `The user's currently focused application is "${activeWindow}".`
    : '';
  const styleGuide =
    style === 'code' || /xcode|code|cursor|terminal|iterm|android studio/i.test(activeWindow)
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

function buildSystemInstruction(params: {
  agentMode: string;
  effort: string;
  originDevice: string;
  phase: string;
  fullComputerAccess: boolean;
  loopIteration: number;
  workstationContext: Record<string, unknown>;
  accountSummary: Record<string, unknown>;
  screenContextLabel?: string;
  webSearch?: boolean;
  memories?: Array<{ id: string; key: string; content: string }>;
}): string {
  const wsConnected = Boolean(params.workstationContext.connected);
  const computerName = String(params.workstationContext.computerName ?? 'Unlinked');
  const activeWindow = String(params.workstationContext.activeWindow ?? 'Unknown');
  const os = String(params.workstationContext.os ?? 'macos');
  const workspaceCwd = String(params.workstationContext.workspaceCwd ?? '~');
  const telemetry = JSON.stringify(params.workstationContext.telemetry ?? {});

  const canEmitCloudTools =
    params.phase !== 'post_tool_synthesis' && params.loopIteration < 3;
  const canEmitMacTools = wsConnected && canEmitCloudTools;

  const memoriesBlock =
    params.memories && params.memories.length > 0
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

async function verifyCallerAndQuota(
  callerUid: string,
  deviceId: string,
  actionBucket: string,
  maxCalls: number,
): Promise<string> {
  let quotaUid = callerUid;
  if (callerUid.startsWith('desktop_agent_')) {
    if (deviceId) {
      const compSnap = await getFirestore()
        .collection('registered_computers')
        .doc(deviceId)
        .get()
        .catch(() => null);
      if (compSnap && compSnap.exists && compSnap.get('agent_uid') === callerUid) {
        quotaUid = String(compSnap.get('owner_uid') ?? callerUid);
      }
    }
  }
  await limit(quotaUid, actionBucket, maxCalls, 10 * 60000);
  return quotaUid;
}

async function loadAccountContextSnapshot(uid: string): Promise<Record<string, unknown>> {
  const db = getFirestore();
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

    const u = userSnap?.data() ?? {};
    const nowMs = Date.now();
    const computers = (compSnap?.docs ?? []).map((doc) => {
      const d = doc.data();
      const lastSeenDate = d.last_seen?.toDate?.() ?? (d.last_seen instanceof Date ? d.last_seen : null);
      const fresh = lastSeenDate ? nowMs - lastSeenDate.getTime() < 75000 : Boolean(d.desktop_connected);
      const isOnline = Boolean(d.desktop_connected) && d.status !== 'offline' && fresh;
      return {
        deviceId: doc.id,
        name: String(d.computer_name ?? 'Workstation'),
        isOnline,
        activeWindow: String(d.active_window ?? 'Desktop'),
        os: String(d.os ?? 'macOS'),
      };
    });

    return {
      uid,
      displayName: String(u.fullName ?? u.displayName ?? u.name ?? ''),
      username: String(u.username ?? ''),
      unreadNotificationsCount: unreadNotifSnap?.size ?? 0,
      linkedComputers: computers,
    };
  } catch {
    return { uid };
  }
}

async function executeCloudAppTool(
  uid: string,
  originDevice: string,
  tc: NormalizedToolCall,
): Promise<string> {
  const db = getFirestore();
  const args = tc.args ?? {};

  switch (tc.name) {
    case 'get_my_profile': {
      const snap = await db.collection('users').doc(uid).get();
      const d = snap.data() ?? {};
      return JSON.stringify({
        uid,
        displayName: d.fullName ?? d.displayName ?? d.name ?? '',
        username: d.username ?? '',
        bio: d.bio ?? '',
        accountType: d.accountType ?? 'creator',
        followerCount: d.followerCount ?? d.followersCount ?? 0,
        followingCount: d.followingCount ?? 0,
        niches: d.niches ?? [],
      });
    }

    case 'list_my_posts': {
      const maxItems = Math.min(20, Math.max(1, Number(args.limit ?? 8)));
      const [postsSnap, contentSnap, draftsSnap] = await Promise.all([
        db.collection('posts').where('authorId', '==', uid).limit(maxItems).get().catch(() => null),
        db.collection('content').where('authorId', '==', uid).limit(maxItems).get().catch(() => null),
        db.collection('users').doc(uid).collection('post_drafts').limit(6).get().catch(() => null),
      ]);

      const seen = new Set<string>();
      const posts: Array<Record<string, unknown>> = [];
      for (const snap of [postsSnap, contentSnap]) {
        for (const doc of snap?.docs ?? []) {
          if (seen.has(doc.id)) continue;
          seen.add(doc.id);
          const d = doc.data();
          posts.push({
            postId: doc.id,
            title: String(d.title ?? '').slice(0, 120),
            caption: String(d.caption ?? d.description ?? '').slice(0, 220),
            type: String(d.type ?? 'post'),
            views: Number(d.viewCount ?? d.views ?? 0),
            likes: Number(d.likeCount ?? d.likes ?? 0),
            comments: Number(d.commentCount ?? d.commentsCount ?? 0),
            createdAt: formatTs(d.createdAt),
          });
        }
      }

      const drafts = (draftsSnap?.docs ?? []).map((doc) => {
        const d = doc.data();
        return {
          draftId: doc.id,
          title: String(d.title ?? '').slice(0, 120),
          caption: String(d.caption ?? d.description ?? '').slice(0, 200),
          updatedAt: formatTs(d.updatedAt ?? d.createdAt),
        };
      });

      return JSON.stringify({ posts: posts.slice(0, maxItems), drafts });
    }

    case 'create_app_post': {
      const caption = String(args.caption ?? args.text ?? '').trim().slice(0, 2200);
      const title = String(args.title ?? '').trim().slice(0, 140);
      const hashtags = Array.isArray(args.hashtags)
        ? args.hashtags.map((h: unknown) => String(h).replace(/^#/, '').trim()).filter(Boolean).slice(0, 15)
        : [];
      const publishNow = args.publishNow === true;

      if (!caption && !title) {
        return JSON.stringify({ ok: false, error: 'Provide a caption or title.' });
      }

      const userDoc = await db.collection('users').doc(uid).get();
      const u = userDoc.data() ?? {};
      const authorName = String(u.fullName ?? u.displayName ?? u.username ?? 'Creator');
      const authorAvatar = String(u.profilePhotoUrl ?? u.photoUrl ?? '');

      if (publishNow) {
        const postRef = await db.collection('posts').add({
          authorId: uid,
          authorName,
          authorUsername: String(u.username ?? ''),
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
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
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
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
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
      let postId = String(args.postId ?? '').trim();
      const maxItems = Math.min(25, Math.max(1, Number(args.limit ?? 12)));
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
        .catch(async () =>
          db.collection('content').doc(postId).collection('comments').limit(maxItems).get(),
        );

      const comments = commentsSnap.docs.map((doc) => {
        const d = doc.data();
        return {
          commentId: doc.id,
          authorId: String(d.authorId ?? d.userId ?? ''),
          authorName: String(d.authorName ?? d.username ?? 'User'),
          text: String(d.text ?? d.content ?? '').slice(0, 400),
          createdAt: formatTs(d.createdAt),
        };
      });
      return JSON.stringify({ ok: true, postId, comments });
    }

    case 'reply_to_post_comment': {
      const postId = String(args.postId ?? '').trim();
      const parentCommentId = String(args.commentId ?? '').trim();
      const text = String(args.text ?? '').trim().slice(0, 1000);
      if (!postId || !text) {
        return JSON.stringify({ ok: false, error: 'postId and text are required.' });
      }
      const userDoc = await db.collection('users').doc(uid).get();
      const u = userDoc.data() ?? {};
      const authorName = String(u.fullName ?? u.displayName ?? u.username ?? 'Creator');
      const commentRef = await db
        .collection('posts')
        .doc(postId)
        .collection('comments')
        .add({
          postId,
          authorId: uid,
          userId: uid,
          authorName,
          authorAvatar: String(u.profilePhotoUrl ?? u.photoUrl ?? ''),
          text,
          parentId: parentCommentId || null,
          likeCount: 0,
          createdVia: `ova_agent_${originDevice}`,
          createdAt: FieldValue.serverTimestamp(),
        });
      await db
        .collection('posts')
        .doc(postId)
        .set({ commentCount: FieldValue.increment(1) }, { merge: true })
        .catch(() => {});
      return JSON.stringify({ ok: true, postId, commentId: commentRef.id, text });
    }

    case 'list_my_chats': {
      const maxItems = Math.min(20, Math.max(1, Number(args.limit ?? 10)));
      const unreadOnly = args.unreadOnly === true;
      const chatsSnap = await db
        .collection('chats')
        .where('participants', 'array-contains', uid)
        .limit(30)
        .get();

      const rows: Array<Record<string, unknown>> = [];
      for (const doc of chatsSnap.docs) {
        const d = doc.data();
        const unreadMap = (d.unreadCounts && typeof d.unreadCounts === 'object')
          ? (d.unreadCounts as Record<string, any>)
          : {};
        const unread = Number(unreadMap[uid] ?? 0);
        if (unreadOnly && unread <= 0) continue;

        const participants = Array.isArray(d.participants)
          ? d.participants.map((p: unknown) => String(p))
          : [];
        let title = String(d.title ?? d.groupName ?? '').trim();
        const partnerId = participants.find((p) => p !== uid) ?? '';
        if (!title && partnerId) {
          const pSnap = await db.collection('users').doc(partnerId).get().catch(() => null);
          const pd = pSnap?.data() ?? {};
          title = String(pd.fullName ?? pd.displayName ?? pd.username ?? 'Direct Chat');
        }

        const tsMs = d.lastMessageTime?.toMillis?.() ?? 0;
        rows.push({
          chatId: doc.id,
          title: title || 'Chat',
          partnerId,
          lastMessage: String(d.lastMessage ?? '').slice(0, 200),
          unreadCount: unread,
          lastMessageAt: formatTs(d.lastMessageTime),
          _sortMs: tsMs,
        });
      }

      rows.sort((a, b) => Number(b._sortMs ?? 0) - Number(a._sortMs ?? 0));
      const cleaned = rows.slice(0, maxItems).map(({ _sortMs, ...rest }) => rest);
      return JSON.stringify({ chats: cleaned });
    }

    case 'read_chat_messages': {
      let chatId = String(args.chatId ?? '').trim();
      const participantQuery = String(args.participantQuery ?? '').trim().toLowerCase();
      const maxItems = Math.min(30, Math.max(1, Number(args.limit ?? 15)));

      if (!chatId && participantQuery) {
        const chatsSnap = await db
          .collection('chats')
          .where('participants', 'array-contains', uid)
          .limit(25)
          .get();
        for (const doc of chatsSnap.docs) {
          const d = doc.data();
          const title = String(d.title ?? '').toLowerCase();
          if (title.includes(participantQuery)) {
            chatId = doc.id;
            break;
          }
          const participants = Array.isArray(d.participants) ? d.participants : [];
          const other = participants.find((p: unknown) => String(p) !== uid);
          if (other) {
            const uSnap = await db.collection('users').doc(String(other)).get().catch(() => null);
            const ud = uSnap?.data() ?? {};
            const hay = `${ud.fullName ?? ''} ${ud.displayName ?? ''} ${ud.username ?? ''}`.toLowerCase();
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
      const participants = Array.isArray(chatDoc.data()?.participants)
        ? chatDoc.data()!.participants.map((p: unknown) => String(p))
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
        const d = doc.data();
        const encrypted = d.isEncrypted === true;
        return {
          messageId: doc.id,
          senderId: String(d.senderId ?? ''),
          fromMe: String(d.senderId ?? '') === uid,
          text: encrypted
            ? '[End-to-End Encrypted Message — view directly in Chat screen]'
            : String(d.text ?? '').slice(0, 500),
          mediaType: d.mediaType ?? null,
          timestamp: formatTs(d.timestamp),
        };
      });
      return JSON.stringify({ ok: true, chatId, messages });
    }

    case 'send_app_message': {
      let chatId = String(args.chatId ?? '').trim();
      const recipientQuery = String(args.recipientQuery ?? '').trim().toLowerCase();
      const text = String(args.text ?? '').trim().slice(0, 2000);
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
          const other = participants.find((p: unknown) => String(p) !== uid);
          if (other) {
            const uSnap = await db.collection('users').doc(String(other)).get().catch(() => null);
            const ud = uSnap?.data() ?? {};
            const hay = `${ud.fullName ?? ''} ${ud.displayName ?? ''} ${ud.username ?? ''} ${d.title ?? ''}`.toLowerCase();
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
      const chatData = chatSnap.data() ?? {};
      const participants = Array.isArray(chatData.participants)
        ? chatData.participants.map((p: unknown) => String(p))
        : [];
      if (!participants.includes(uid)) {
        return JSON.stringify({ ok: false, error: 'Not a participant of this chat.' });
      }

      const msgId = crypto.randomUUID();
      const nowTs = Timestamp.now();
      const unreadCounts: Record<string, number> = {
        ...(chatData.unreadCounts ?? {}),
      };
      for (const p of participants) {
        if (p !== uid) {
          unreadCounts[p] = Number(unreadCounts[p] ?? 0) + 1;
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

      await chatRef.set(
        {
          lastMessage: text,
          lastMessageTime: nowTs,
          lastMessageSenderId: uid,
          unreadCounts,
        },
        { merge: true },
      );

      return JSON.stringify({ ok: true, chatId, messageId: msgId, sentText: text });
    }

    case 'list_notifications': {
      const maxItems = Math.min(25, Math.max(1, Number(args.limit ?? 12)));
      const unreadOnly = args.unreadOnly === true;

      const [byRecipient, byUser, userSub] = await Promise.all([
        db.collection('notifications').where('recipientId', '==', uid).limit(25).get().catch(() => null),
        db.collection('notifications').where('userId', '==', uid).limit(25).get().catch(() => null),
        db.collection('users').doc(uid).collection('notifications').limit(20).get().catch(() => null),
      ]);

      const seen = new Set<string>();
      const items: Array<Record<string, unknown>> = [];
      for (const snap of [byRecipient, byUser, userSub]) {
        for (const doc of snap?.docs ?? []) {
          if (seen.has(doc.id)) continue;
          seen.add(doc.id);
          const d = doc.data();
          const isRead = d.isRead === true || d.read === true;
          if (unreadOnly && isRead) continue;
          const tsMs =
            d.createdAt?.toMillis?.() ?? d.timestamp?.toMillis?.() ?? 0;
          items.push({
            id: doc.id,
            title: String(d.title ?? d.type ?? 'Notification').slice(0, 140),
            body: String(d.body ?? d.message ?? '').slice(0, 240),
            category: String(d.category ?? d.type ?? 'general'),
            isRead,
            deepLink: d.deepLink ?? null,
            createdAt: formatTs(d.createdAt ?? d.timestamp),
            _sortMs: tsMs,
          });
        }
      }
      items.sort((a, b) => Number(b._sortMs ?? 0) - Number(a._sortMs ?? 0));
      return JSON.stringify({
        notifications: items.slice(0, maxItems).map(({ _sortMs, ...r }) => r),
      });
    }

    case 'mark_notifications_read': {
      const ids = Array.isArray(args.notificationIds)
        ? args.notificationIds.map((x: unknown) => String(x)).filter(Boolean)
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
          batch.update(doc.ref, { isRead: true, readAt: FieldValue.serverTimestamp() });
          count++;
        }
      } else {
        for (const id of ids.slice(0, 30)) {
          const ref = db.collection('notifications').doc(id);
          const snap = await ref.get();
          if (snap.exists && (snap.get('recipientId') === uid || snap.get('userId') === uid)) {
            batch.update(ref, { isRead: true, readAt: FieldValue.serverTimestamp() });
            count++;
          }
        }
      }
      if (count > 0) await batch.commit();
      return JSON.stringify({ ok: true, markedReadCount: count });
    }

    case 'create_reminder': {
      const title = String(args.title ?? args.text ?? '').trim().slice(0, 240);
      if (!title) {
        return JSON.stringify({ ok: false, error: 'Reminder title is required.' });
      }
      const dueRaw = String(args.dueAtIso ?? '').trim();
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
          dueAt: Timestamp.fromDate(validDate),
          remindAt: Timestamp.fromDate(validDate),
          completed: false,
          done: false,
          originDevice,
          createdAt: FieldValue.serverTimestamp(),
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
        const d = doc.data();
        return {
          id: doc.id,
          title: String(d.title ?? d.text ?? ''),
          completed: Boolean(d.completed ?? d.done ?? false),
          dueAt: formatTs(d.dueAt ?? d.remindAt),
        };
      });
      return JSON.stringify({ reminders });
    }

    case 'list_studio_projects': {
      const [projSnap, globalProjSnap] = await Promise.all([
        db.collection('users').doc(uid).collection('projects').limit(12).get().catch(() => null),
        db.collection('projects').where('ownerId', '==', uid).limit(12).get().catch(() => null),
      ]);
      const seen = new Set<string>();
      const projects: Array<Record<string, unknown>> = [];
      for (const snap of [projSnap, globalProjSnap]) {
        for (const doc of snap?.docs ?? []) {
          if (seen.has(doc.id)) continue;
          seen.add(doc.id);
          const d = doc.data();
          projects.push({
            projectId: doc.id,
            title: String(d.title ?? d.name ?? 'Untitled Project'),
            status: String(d.status ?? 'active'),
            category: String(d.category ?? 'studio'),
            updatedAt: formatTs(d.updatedAt ?? d.createdAt),
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
        const d = doc.data();
        const lastSeenDate = d.last_seen?.toDate?.() ?? null;
        const fresh = lastSeenDate ? nowMs - lastSeenDate.getTime() < 75000 : Boolean(d.desktop_connected);
        return {
          deviceId: doc.id,
          computerName: String(d.computer_name ?? 'Workstation'),
          os: String(d.os ?? 'macOS'),
          isOnline: Boolean(d.desktop_connected) && d.status !== 'offline' && fresh,
          activeWindow: String(d.active_window ?? 'Desktop'),
          lastSeen: formatTs(d.last_seen),
        };
      });
      return JSON.stringify({ computers });
    }

    case 'dispatch_computer_command': {
      let targetDeviceId = String(args.deviceId ?? '').trim();
      const command = String(args.command ?? '').trim();
      const payload =
        args.payload && typeof args.payload === 'object' ? args.payload : {};

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
          targetDeviceId = (onlineDoc ?? snap.docs[0]).id;
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
        timestamp: FieldValue.serverTimestamp(),
        status: 'pending',
        dispatched_by: `ova_agent_${originDevice}`,
      });

      return JSON.stringify({
        ok: true,
        deviceId: targetDeviceId,
        computerName: String(compSnap.get('computer_name') ?? 'Workstation'),
        commandId: cmdRef.id,
        command,
      });
    }

    case 'save_memory': {
      const key = String(args.key ?? 'general').trim().slice(0, 80);
      const content = String(args.content ?? '').trim().slice(0, 1200);
      if (!content) {
        return JSON.stringify({ ok: false, error: 'Memory content cannot be empty.' });
      }
      const memId = key.replace(/[^a-zA-Z0-9_-]/g, '_').toLowerCase() || 'general';
      await db
        .collection('users')
        .doc(uid)
        .collection('agent_memories')
        .doc(memId)
        .set(
          {
            key,
            content,
            updatedAt: new Date(),
            originDevice,
          },
          { merge: true },
        );
      return JSON.stringify({ ok: true, key, content });
    }

    case 'recall_memories': {
      const q = String(args.query ?? '').trim().toLowerCase();
      const memSnap = await db
        .collection('users')
        .doc(uid)
        .collection('agent_memories')
        .orderBy('updatedAt', 'desc')
        .limit(30)
        .get();
      const matched = memSnap.docs
        .map((d) => ({
          key: String(d.get('key') ?? d.id),
          content: String(d.get('content') ?? ''),
        }))
        .filter(
          (m) =>
            !q ||
            m.key.toLowerCase().includes(q) ||
            m.content.toLowerCase().includes(q),
        );
      return JSON.stringify({ memories: matched });
    }

    case 'delete_memory': {
      const key = String(args.key ?? '').trim();
      if (!key) return JSON.stringify({ ok: false, error: 'key is required.' });
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

async function runModelJsonTurn(params: {
  contents: Array<{ role: string; parts: Array<{ text: string }> }>;
  systemInstruction: string;
  effort: string;
}): Promise<Record<string, any>> {
  let rawJsonText = '';
  try {
    const thinkingBudget =
      params.effort === 'deep_think' ? 2048 : params.effort === 'fast' ? 0 : 512;
    const vertexResp = await generateVertexContent({
      contents: params.contents,
      config: {
        systemInstruction: params.systemInstruction,
        temperature: params.effort === 'deep_think' ? 0.3 : 0.38,
        maxOutputTokens: 4096,
        responseMimeType: 'application/json',
        thinkingConfig: { thinkingBudget },
      },
    });
    rawJsonText = String(vertexResp.text ?? '').trim();
  } catch (vertexErr: any) {
    console.warn('[ovaAgentExecuteTurn] Vertex fallback check:', vertexErr?.message ?? vertexErr);
    const orKey = openRouterSecret.value();
    if (!orKey) {
      throw new HttpsError('unavailable', 'Oneova Agent AI engine is temporarily unavailable.');
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
      throw new HttpsError('unavailable', `AI upstream returned HTTP ${orResp.status}.`);
    }
    const orData = (await orResp.json()) as any;
    rawJsonText = String(orData?.choices?.[0]?.message?.content ?? '').trim();
  }

  try {
    return JSON.parse(sanitizeJsonText(rawJsonText));
  } catch {
    return {
      thinking: ['Synthesized direct response from agent output.'],
      reply: rawJsonText || 'Ready for your next instruction.',
    };
  }
}

export const ovaAgentExecuteTurn = onCall(
  {
    secrets: [openRouterSecret],
    enforceAppCheck: false,
    timeoutSeconds: 120,
    memory: '512MiB',
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in to use Oneova Agent.');
    }

    const callerUid = request.auth.uid;
    const data = (request.data ?? {}) as Record<string, unknown>;
    const mode = String(data.mode ?? 'agent_turn').trim();
    const deviceId = String(data.deviceId ?? '').trim().slice(0, 200);

    // -------------------------------------------------------------------------
    // MODE A: Wispr Flow Multimodal Audio Transcription + AI Auto-Polish
    // -------------------------------------------------------------------------
    if (mode === 'wispr_transcribe_and_tidy' || mode === 'wispr_tidy') {
      await verifyCallerAndQuota(callerUid, deviceId, 'ova_wispr_flow', 180);

      const style = String(data.style ?? 'auto').slice(0, 40);
      const activeWindow = String(data.activeWindow ?? '').slice(0, 120);
      const commandInstruction = data.commandInstruction
        ? String(data.commandInstruction).slice(0, 400)
        : undefined;
      const systemInstruction = buildWisprSystemPrompt({
        style,
        activeWindow,
        commandInstruction,
      });

      if (mode === 'wispr_transcribe_and_tidy') {
        const audioBase64 = String(data.audioBase64 ?? '').trim();
        const mimeType = String(data.mimeType ?? 'audio/mp4').trim() || 'audio/mp4';
        if (!audioBase64) {
          return { rawTranscript: '', polishedText: '' };
        }
        if (audioBase64.length > 9_500_000) {
          throw new HttpsError('invalid-argument', 'Voice clip is too large (max ~7 MB).');
        }

        const transcribePrompt = commandInstruction
          ? `Listen to the spoken audio and apply the transformation instruction ("${commandInstruction}"). If there is only silence or background noise, return an empty string.`
          : 'Transcribe this spoken audio accurately in the language spoken, applying the Ova Wispr Flow cleanup rules (remove filler words, apply spoken self-corrections, add crisp punctuation). If there is no intelligible speech or only silence, return an empty string.';

        const vertexResp = await generateVertexContent({
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
        const cleaned = String(vertexResp.text ?? '').trim();
        return {
          rawTranscript: cleaned,
          polishedText: cleaned,
        };
      }

      const rawText = String(data.text ?? '').trim().slice(0, 8000);
      if (!rawText) {
        return { rawTranscript: '', polishedText: '' };
      }
      if (!commandInstruction && rawText.split(/\s+/).length < 2) {
        const cap = rawText.charAt(0).toUpperCase() + rawText.slice(1);
        return { rawTranscript: rawText, polishedText: cap };
      }

      try {
        const vertexResp = await generateVertexContent({
          contents: [{ role: 'user', parts: [{ text: rawText }] }],
          config: {
            systemInstruction,
            temperature: 0.15,
            maxOutputTokens: 2048,
          },
        });
        const out = String(vertexResp.text ?? '').trim();
        return {
          rawTranscript: rawText,
          polishedText: out || rawText,
        };
      } catch (vertexErr: any) {
        console.warn('[ovaAgentExecuteTurn] Wispr Vertex fallback check:', vertexErr?.message ?? vertexErr);
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
              const orData = (await orResp.json()) as any;
              const out = String(orData?.choices?.[0]?.message?.content ?? '').trim();
              if (out) {
                return {
                  rawTranscript: rawText,
                  polishedText: out,
                };
              }
            }
          } catch (orErr) {
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
          const memSnap = await getFirestore()
            .collection('users')
            .doc(quotaUid)
            .collection('agent_memories')
            .orderBy('updatedAt', 'desc')
            .limit(30)
            .get();
          return memSnap.docs.map((doc) => {
            const d = doc.data();
            return {
              id: doc.id,
              key: String(d.key ?? doc.id),
              content: String(d.content ?? ''),
            };
          });
        } catch {
          return [];
        }
      })(),
      loadAccountContextSnapshot(quotaUid),
    ]);

    const rawMessages = Array.isArray(data.messages)
      ? (data.messages as RawTurnInputMessage[]).slice(-28)
      : [];
    const fallbackPrompt = String(data.prompt ?? '').trim().slice(0, 14000);

    const formattedContents = rawMessages
      .map((m) => {
        const role = String(m.role ?? 'user') === 'assistant' ? 'model' : 'user';
        const text = String(m.content ?? '').trim().slice(0, 14000);
        return { role, parts: [{ text }] };
      })
      .filter((m) => m.parts[0].text.length > 0);

    if (formattedContents.length === 0 && fallbackPrompt.length > 0) {
      formattedContents.push({ role: 'user', parts: [{ text: fallbackPrompt }] });
    }

    if (formattedContents.length === 0) {
      throw new HttpsError('invalid-argument', 'Conversation messages are required.');
    }

    const agentMode = String(data.agentMode ?? 'orchestrator').slice(0, 40);
    const effort = String(data.effort ?? 'balanced').slice(0, 30);
    const originDevice = String(data.originDevice ?? 'mobile').slice(0, 30);
    const phase = String(data.phase ?? 'initial').slice(0, 40);
    const fullComputerAccess = data.fullComputerAccess === true;
    const loopIteration =
      typeof data.loopIteration === 'number'
        ? Math.max(0, Math.min(4, Math.floor(data.loopIteration)))
        : 0;
    const screenContextLabel = data.screenContextLabel
      ? String(data.screenContextLabel).slice(0, 200)
      : undefined;
    const webSearch = data.webSearch === true;
    const workstationContext =
      data.workstationContext && typeof data.workstationContext === 'object'
        ? (data.workstationContext as Record<string, unknown>)
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
    const toolCalls: NormalizedToolCall[] = !canEmitCloudTools
      ? []
      : rawToolArray
          .filter((tc: any) => {
            const name = String(tc?.name ?? '');
            if (CLOUD_APP_TOOLS.has(name)) return true;
            if (canEmitMacTools && MAC_LOCAL_TOOLS.has(name)) return true;
            return false;
          })
          .slice(0, 6)
          .map((tc: any, idx: number) => {
            const name = String(tc.name);
            const argsObj =
              tc?.args && typeof tc.args === 'object' && !Array.isArray(tc.args)
                ? tc.args
                : {};
            const cmdStr = String(argsObj.command ?? '');
            const isCatastrophic =
              name === 'run_terminal_command' &&
              CATASTROPHIC_SHELL_PATTERNS.some((rx) => rx.test(cmdStr));

            let risk: 'safe' | 'approval_required' = 'safe';
            if (isCatastrophic) {
              risk = 'approval_required';
            } else if (!fullComputerAccess && MAC_LOCAL_TOOLS.has(name)) {
              const combo = String(argsObj.combo ?? '').toLowerCase();
              const destructiveHotkey =
                (name === 'send_mac_hotkey' || name === 'keyboard_action') &&
                (combo.includes('cmd+q') || combo.includes('cmd+delete'));
              if (
                SUPERVISED_APPROVAL_TOOLS.has(name) ||
                destructiveHotkey ||
                tc?.risk === 'approval_required'
              ) {
                risk = 'approval_required';
              }
            }

            return {
              id: String(tc?.id ?? `tc_${crypto.randomBytes(4).toString('hex')}_${idx}`),
              name,
              title: String(tc?.title ?? name.replace(/_/g, ' ')).slice(0, 140),
              args: argsObj,
              risk,
            };
          });

    // Execute all CLOUD_APP_TOOLS immediately on the server against real Firestore data!
    const executedCloudSummaries: string[] = [];
    let hasPendingMacTools = false;

    for (const tc of toolCalls) {
      if (CLOUD_APP_TOOLS.has(tc.name)) {
        const started = Date.now();
        try {
          const out = await executeCloudAppTool(quotaUid, originDevice, tc);
          tc.status = 'completed';
          tc.output = out.slice(0, 4000);
          tc.durationMs = Date.now() - started;
          executedCloudSummaries.push(
            `Tool "${tc.name}" (${tc.title}) -> ${tc.output}`,
          );
        } catch (err: any) {
          tc.status = 'error';
          tc.output = JSON.stringify({
            ok: false,
            error: String(err?.message ?? err),
          });
          tc.durationMs = Date.now() - started;
          executedCloudSummaries.push(
            `Tool "${tc.name}" failed -> ${tc.output}`,
          );
        }
      } else {
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
              text:
                `Real Oneova backend tool execution results:\n` +
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
        parsed = {
          ...parsed,
          ...synthParsed,
          thinking: [
            ...(Array.isArray(parsed.thinking) ? parsed.thinking : []),
            ...(Array.isArray(synthParsed.thinking) ? synthParsed.thinking : []),
          ].slice(0, 8),
        };
      } catch (synthErr) {
        console.warn('[ovaAgentExecuteTurn] Cloud tool synthesis fallback:', synthErr);
      }
    }

    const thinking = Array.isArray(parsed.thinking)
      ? parsed.thinking.map((s: unknown) => String(s ?? '').trim()).filter(Boolean).slice(0, 8)
      : ['Analyzed request context and active account state.'];

    const rawSub =
      parsed.subagent && typeof parsed.subagent === 'object' ? parsed.subagent : {};
    const subagent = {
      id: String(rawSub.id ?? (agentMode === 'orchestrator' ? 'computer_use' : agentMode)).slice(0, 40),
      label: String(rawSub.label ?? 'Ova Orchestrator').slice(0, 60),
      role: String(rawSub.role ?? 'Shared account & computer-use intelligence').slice(0, 100),
    };

    const plan = Array.isArray(parsed.plan)
      ? parsed.plan.slice(0, 8).map((item: any, idx: number) => {
          const st = String(item?.status ?? 'pending');
          return {
            id: String(item?.id ?? `step_${idx + 1}`).slice(0, 32),
            title: String(item?.title ?? `Step ${idx + 1}`).slice(0, 180),
            status:
              !hasPendingMacTools && executedCloudSummaries.length > 0
                ? 'completed'
                : st === 'completed' || st === 'in_progress'
                  ? st
                  : 'pending',
          };
        })
      : [];

    const artifacts = Array.isArray(parsed.artifacts)
      ? parsed.artifacts
          .filter((a: any) => String(a?.content ?? '').trim().length > 0)
          .slice(0, 4)
          .map((a: any, idx: number) => ({
            id: String(a?.id ?? `art_${idx + 1}`).slice(0, 40),
            title: String(a?.title ?? `Artifact ${idx + 1}`).slice(0, 120),
            kind: ['code', 'markdown', 'plan', 'script', 'command'].includes(String(a?.kind))
              ? String(a.kind)
              : 'markdown',
            language: String(a?.language ?? 'markdown').slice(0, 30),
            content: String(a?.content ?? '').slice(0, 24000),
          }))
      : [];

    const reply =
      String(parsed.reply ?? '').trim().slice(0, 16000) ||
      (hasPendingMacTools
        ? 'Executing autonomous workstation steps...'
        : 'Completed.');

    const followUps = Array.isArray(parsed.followUps)
      ? parsed.followUps
          .map((f: unknown) => String(f ?? '').trim())
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
  },
);
