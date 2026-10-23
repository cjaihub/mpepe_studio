"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.aiGateway = exports.generateLiveApiToken = void 0;
const https_1 = require("firebase-functions/v2/https");
const params_1 = require("firebase-functions/params");
const genai_1 = require("@google/genai");
const ToolExecutionLayer_1 = require("./services/ToolExecutionLayer");
const firestore_1 = require("firebase-admin/firestore");
const geminiSecret = (0, params_1.defineSecret)('GEMINI_API_KEY');
/**
 * Short-lived Gemini Live token for the app's voice mode. It can only open
 * one Live session for 30 minutes; it is NOT a Google Cloud credential.
 * (The previous version returned the server's own cloud-platform access
 * token to any signed-in user, which would have exposed the whole project.)
 */
exports.generateLiveApiToken = (0, https_1.onCall)({ secrets: [geminiSecret] }, async (request) => {
    var _a;
    var _b;
    if (!request.auth || ((_a = request.auth.token.firebase) === null || _a === void 0 ? void 0 : _a.sign_in_provider) === 'anonymous') {
        throw new https_1.HttpsError('unauthenticated', 'User must be logged in.');
    }
    try {
        const ai = new genai_1.GoogleGenAI({ apiKey: geminiSecret.value(), httpOptions: { apiVersion: 'v1alpha' } });
        const expireTime = new Date(Date.now() + 30 * 60 * 1000).toISOString();
        const newSessionExpireTime = new Date(Date.now() + 60 * 1000).toISOString();
        const token = await ai.authTokens.create({
            config: { uses: 1, expireTime, newSessionExpireTime },
        });
        return { token: token.name, expiresAt: Date.parse(expireTime) };
    }
    catch (error) {
        console.error('Live token error:', (_b = error === null || error === void 0 ? void 0 : error.message) !== null && _b !== void 0 ? _b : error);
        throw new https_1.HttpsError('internal', 'Failed to generate Live API token.');
    }
});
// Define tools using Gemini SDK Schema
const applicationTools = [{
        functionDeclarations: [
            {
                name: 'get_user_profile',
                description: 'Fetch a user profile by their ID.',
                parameters: {
                    type: genai_1.Type.OBJECT,
                    properties: { userId: { type: genai_1.Type.STRING } },
                    required: ['userId']
                }
            },
            {
                name: 'get_conversation',
                description: 'Fetch the metadata and details of a specific conversation.',
                parameters: {
                    type: genai_1.Type.OBJECT,
                    properties: { conversationId: { type: genai_1.Type.STRING } },
                    required: ['conversationId']
                }
            },
            {
                name: 'search_messages',
                description: 'Search messages globally for the user.',
                parameters: {
                    type: genai_1.Type.OBJECT,
                    properties: { query: { type: genai_1.Type.STRING }, limit: { type: genai_1.Type.NUMBER } },
                    required: ['query']
                }
            },
            {
                name: 'get_recent_messages',
                description: 'Get recent messages in a conversation.',
                parameters: {
                    type: genai_1.Type.OBJECT,
                    properties: { conversationId: { type: genai_1.Type.STRING }, limit: { type: genai_1.Type.NUMBER } },
                    required: ['conversationId']
                }
            },
            {
                name: 'get_contact',
                description: 'Get a specific contact of the user.',
                parameters: {
                    type: genai_1.Type.OBJECT,
                    properties: { contactId: { type: genai_1.Type.STRING } },
                    required: ['contactId']
                }
            },
            {
                name: 'get_calendar_events',
                description: 'Get calendar events for a given date (YYYY-MM-DD).',
                parameters: {
                    type: genai_1.Type.OBJECT,
                    properties: { date: { type: genai_1.Type.STRING } },
                    required: ['date']
                }
            },
            {
                name: 'create_calendar_event',
                description: 'Create a calendar event.',
                parameters: {
                    type: genai_1.Type.OBJECT,
                    properties: { title: { type: genai_1.Type.STRING }, date: { type: genai_1.Type.STRING }, time: { type: genai_1.Type.STRING } },
                    required: ['title', 'date', 'time']
                }
            },
            {
                name: 'draft_message',
                description: 'Draft a message in a conversation.',
                parameters: {
                    type: genai_1.Type.OBJECT,
                    properties: { conversationId: { type: genai_1.Type.STRING }, text: { type: genai_1.Type.STRING } },
                    required: ['conversationId', 'text']
                }
            },
            {
                name: 'send_message',
                description: 'Send a message in a conversation.',
                parameters: {
                    type: genai_1.Type.OBJECT,
                    properties: { conversationId: { type: genai_1.Type.STRING }, text: { type: genai_1.Type.STRING } },
                    required: ['conversationId', 'text']
                }
            },
            {
                name: 'schedule_message',
                description: 'Schedule a message for later.',
                parameters: {
                    type: genai_1.Type.OBJECT,
                    properties: { conversationId: { type: genai_1.Type.STRING }, text: { type: genai_1.Type.STRING }, scheduledTime: { type: genai_1.Type.STRING } },
                    required: ['conversationId', 'text', 'scheduledTime']
                }
            },
            {
                name: 'create_task',
                description: 'Create a to-do task.',
                parameters: {
                    type: genai_1.Type.OBJECT,
                    properties: { title: { type: genai_1.Type.STRING }, description: { type: genai_1.Type.STRING }, dueDate: { type: genai_1.Type.STRING } },
                    required: ['title']
                }
            },
            {
                name: 'find_file',
                description: 'Find a file in the user\'s storage.',
                parameters: {
                    type: genai_1.Type.OBJECT,
                    properties: { query: { type: genai_1.Type.STRING } },
                    required: ['query']
                }
            },
            {
                name: 'get_course_information',
                description: 'Get information about a course.',
                parameters: {
                    type: genai_1.Type.OBJECT,
                    properties: { courseId: { type: genai_1.Type.STRING } },
                    required: ['courseId']
                }
            },
            {
                name: 'get_notification_summary',
                description: 'Get a summary of unread notifications.',
                parameters: {
                    type: genai_1.Type.OBJECT,
                    properties: {},
                }
            }
        ]
    }];
exports.aiGateway = (0, https_1.onCall)({ secrets: [geminiSecret] }, async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError('unauthenticated', 'User must be logged in.');
    }
    const userId = request.auth.uid;
    const { operation = 'chat', data, prompt, history = [] } = request.data;
    const apiKey = geminiSecret.value();
    if (!apiKey) {
        throw new https_1.HttpsError('internal', 'AI is not configured.');
    }
    // Check global AI agent kill switch
    const db = (0, firestore_1.getFirestore)();
    const configDoc = await db.collection('users').doc(userId).collection('ai_settings').doc('agent_config').get();
    if (configDoc.exists) {
        const configData = configDoc.data();
        if (configData === null || configData === void 0 ? void 0 : configData.isGloballyPaused) {
            throw new https_1.HttpsError('permission-denied', 'AI Agent is globally paused by the user.');
        }
    }
    if (operation === 'composeMessage') {
        return await handleComposeMessage(userId, data, apiKey);
    }
    if (!prompt) {
        throw new https_1.HttpsError('invalid-argument', 'Missing prompt.');
    }
    const ai = new genai_1.GoogleGenAI({ apiKey });
    // Add system instruction
    let chatHistory = [
        { role: 'user', parts: [{ text: "System Instructions: You are a helpful AI assistant. Use tools to satisfy the user's request. Only answer based on what the tools provide." }] },
        { role: 'model', parts: [{ text: "Understood." }] }
    ];
    if (Array.isArray(history)) {
        chatHistory = chatHistory.concat(history);
    }
    chatHistory.push({ role: 'user', parts: [{ text: prompt }] });
    try {
        let response = await ai.models.generateContent({
            model: 'gemini-2.5-flash',
            contents: chatHistory,
            config: {
                tools: applicationTools,
            }
        });
        const usedTools = [];
        // Check if Gemini wants to call a function
        while (response.functionCalls && response.functionCalls.length > 0) {
            const functionCall = response.functionCalls[0];
            const name = functionCall.name;
            const args = functionCall.args;
            if (name) {
                usedTools.push(name);
            }
            chatHistory.push({ role: 'model', parts: [{ functionCall }] });
            let toolResult;
            try {
                // Route to ToolExecutionLayer
                switch (name) {
                    case 'get_user_profile':
                        toolResult = await ToolExecutionLayer_1.ToolExecutionLayer.getUserProfile(userId, args);
                        break;
                    case 'get_conversation':
                        toolResult = await ToolExecutionLayer_1.ToolExecutionLayer.getConversation(userId, args);
                        break;
                    case 'search_messages':
                        toolResult = await ToolExecutionLayer_1.ToolExecutionLayer.searchMessages(userId, args);
                        break;
                    case 'get_recent_messages':
                        toolResult = await ToolExecutionLayer_1.ToolExecutionLayer.getRecentMessages(userId, args);
                        break;
                    case 'get_contact':
                        toolResult = await ToolExecutionLayer_1.ToolExecutionLayer.getContact(userId, args);
                        break;
                    case 'get_calendar_events':
                        toolResult = await ToolExecutionLayer_1.ToolExecutionLayer.getCalendarEvents(userId, args);
                        break;
                    case 'create_calendar_event':
                        toolResult = await ToolExecutionLayer_1.ToolExecutionLayer.createCalendarEvent(userId, args);
                        break;
                    case 'draft_message':
                        toolResult = await ToolExecutionLayer_1.ToolExecutionLayer.draftMessage(userId, args);
                        break;
                    case 'send_message':
                        toolResult = await ToolExecutionLayer_1.ToolExecutionLayer.sendMessage(userId, args);
                        break;
                    case 'schedule_message':
                        toolResult = await ToolExecutionLayer_1.ToolExecutionLayer.scheduleMessage(userId, args);
                        break;
                    case 'create_task':
                        toolResult = await ToolExecutionLayer_1.ToolExecutionLayer.createTask(userId, args);
                        break;
                    case 'find_file':
                        toolResult = await ToolExecutionLayer_1.ToolExecutionLayer.findFile(userId, args);
                        break;
                    case 'get_course_information':
                        toolResult = await ToolExecutionLayer_1.ToolExecutionLayer.getCourseInformation(userId, args);
                        break;
                    case 'get_notification_summary':
                        toolResult = await ToolExecutionLayer_1.ToolExecutionLayer.getNotificationSummary(userId);
                        break;
                    default: toolResult = { error: "Unknown tool" };
                }
            }
            catch (e) {
                toolResult = { error: e.message || "Execution failed" };
            }
            // Return tool result to model
            chatHistory.push({
                role: 'user',
                parts: [{ functionResponse: { name, response: toolResult } }]
            });
            response = await ai.models.generateContent({
                model: 'gemini-2.5-flash',
                contents: chatHistory,
                config: {
                    tools: applicationTools,
                }
            });
        }
        if (usedTools.length > 0 || operation !== 'chat') {
            // Only log if tools were used, OR if it's an explicit background/automated operation
            await ToolExecutionLayer_1.ToolExecutionLayer.auditAction(userId, operation, `Processed AI Gateway request.`, usedTools, [], response.text);
        }
        return {
            success: true,
            reply: response.text,
            // Optional: Return draft info if frontend needs to present it in UI instead of saving it server-side.
        };
    }
    catch (error) {
        console.error("Gemini AI Error: ", error);
        throw new https_1.HttpsError('internal', 'Failed to process AI Gateway request.');
    }
});
async function handleComposeMessage(userId, data, apiKey) {
    const { conversationId, messageId, action, currentText } = data;
    if (!conversationId || !action) {
        throw new https_1.HttpsError('invalid-argument', 'Missing conversationId or action.');
    }
    // Define sensitive topics that should block auto-send or automated processing
    const SENSITIVE_TOPICS = [
        'financial commitments', 'money transfer', 'bank', 'password', 'security changes',
        'account deletion', 'legal agreements', 'lawsuit', 'identity verification',
        'medical decisions', 'health', 'high-impact personal decisions', 'divorce'
    ];
    // Create prompt based on action
    let prompt = '';
    switch (action) {
        case 'improve':
            prompt = `Improve this text: "${currentText}"`;
            break;
        case 'shorten':
            prompt = `Shorten this text: "${currentText}"`;
            break;
        case 'expand':
            prompt = `Expand this text: "${currentText}"`;
            break;
        case 'makeProfessional':
            prompt = `Make this text more professional: "${currentText}"`;
            break;
        case 'makeFriendly':
            prompt = `Make this text more friendly: "${currentText}"`;
            break;
        case 'translate':
            prompt = `Translate this text (detect language and translate to the most likely intended target or English if unsure): "${currentText}"`;
            break;
        case 'reply':
            prompt = `Draft a reply based on the context of this conversation.`;
            break;
        case 'summarize':
            prompt = `Summarize this text: "${currentText}"`;
            break;
        case 'rewrite':
            prompt = `Rewrite this text completely: "${currentText}"`;
            break;
        case 'voiceDraft':
            prompt = `Draft a message from this voice transcript: "${currentText}"`;
            break;
        default: prompt = `Improve this text: "${currentText}"`;
    }
    const ai = new genai_1.GoogleGenAI({ apiKey });
    const systemInstruction = "You are an AI messaging assistant. Provide ONLY the suggested text. Do NOT include explanations, markdown blocks, or conversational filler like 'Here is the improved text:'. Just the text itself. Ensure you refuse to process requests that clearly fall under sensitive topics (e.g. financial, medical, legal, security).";
    try {
        const response = await ai.models.generateContent({
            model: 'gemini-2.5-flash',
            contents: [
                { role: 'user', parts: [{ text: `System: ${systemInstruction}\n\nTask: ${prompt}` }] }
            ],
        });
        const reply = response.text || '';
        const replyLower = reply.toLowerCase();
        // Check if the output touches sensitive topics
        let isSensitive = false;
        for (const topic of SENSITIVE_TOPICS) {
            if (replyLower.includes(topic)) {
                isSensitive = true;
                break;
            }
        }
        if (isSensitive) {
            throw new https_1.HttpsError('permission-denied', 'AI cannot process sensitive actions automatically.');
        }
        // Determine auto-mode rules (fetching from firestore)
        const db = (0, firestore_1.getFirestore)();
        const autoModeDoc = await db.collection('users').doc(userId).collection('communicationProfile').doc('autoMode').get();
        let autoSend = false;
        if (autoModeDoc.exists) {
            const settings = autoModeDoc.data();
            if (settings && (settings.level === 'autoSendApprovedScenarios' || settings.level === 'fullAutoMode')) {
                // Check allowed conversations / contacts
                if (settings.allowedConversations && settings.allowedConversations.includes(conversationId)) {
                    autoSend = true;
                }
                else if (settings.allowedConversations && settings.allowedConversations.includes('all')) {
                    autoSend = true;
                }
            }
        }
        if (autoSend) {
            // Auto-send logic goes here (e.g. using ToolExecutionLayer.sendMessage)
            // await ToolExecutionLayer.sendMessage(userId, { conversationId, text: reply });
            // We'll return success and let the client know it was sent, but for now we just return the suggestion.
        }
        await ToolExecutionLayer_1.ToolExecutionLayer.auditAction(userId, `compose_${action}`, `User requested AI to ${action} message.`, [], [currentText], reply, conversationId);
        const suggestionId = 'sugg_' + Date.now();
        return {
            success: true,
            suggestion: {
                id: suggestionId,
                originalText: currentText || '',
                suggestedText: reply,
                action: action,
                status: autoSend ? 'accepted' : 'pending',
                createdAt: new Date().toISOString(),
                conversationId: conversationId,
                messageId: messageId || '',
            }
        };
    }
    catch (error) {
        console.error("Gemini AI Composer Error: ", error);
        throw new https_1.HttpsError('internal', 'Failed to compose message.');
    }
}
//# sourceMappingURL=aiGateway.js.map