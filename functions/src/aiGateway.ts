import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { Type } from '@google/genai';
import { ToolExecutionLayer } from './services/ToolExecutionLayer';
import { getFirestore } from 'firebase-admin/firestore';
import { readAccountSettings } from './accountSettings';
import { generateVertexContent } from './vertexAi';
import { limit } from './guard/protect';

/**
 * Retired: voice mode now talks to the Gemini Live model on Vertex AI
 * directly through Firebase AI Logic (App Check + Auth, no API key), see
 * lib/ai_messaging/services/gemini_live_service.dart. Kept so older app
 * builds get a clear error instead of a missing-function failure.
 */
export const generateLiveApiToken = onCall(async () => {
  throw new HttpsError(
    'failed-precondition',
    'Voice mode moved to Vertex AI. Update Oneova to the latest version.',
  );
});

// Define tools using Gemini SDK Schema
const applicationTools: any = [{
  functionDeclarations: [
    {
      name: 'get_user_profile',
      description: 'Fetch a user profile by their ID.',
      parameters: {
        type: Type.OBJECT,
        properties: { userId: { type: Type.STRING } },
        required: ['userId']
      }
    },
    {
      name: 'get_conversation',
      description: 'Fetch the metadata and details of a specific conversation.',
      parameters: {
        type: Type.OBJECT,
        properties: { conversationId: { type: Type.STRING } },
        required: ['conversationId']
      }
    },
    {
      name: 'search_messages',
      description: 'Search messages globally for the user.',
      parameters: {
        type: Type.OBJECT,
        properties: { query: { type: Type.STRING }, limit: { type: Type.NUMBER } },
        required: ['query']
      }
    },
    {
      name: 'get_recent_messages',
      description: 'Get recent messages in a conversation.',
      parameters: {
        type: Type.OBJECT,
        properties: { conversationId: { type: Type.STRING }, limit: { type: Type.NUMBER } },
        required: ['conversationId']
      }
    },
    {
      name: 'get_contact',
      description: 'Get a specific contact of the user.',
      parameters: {
        type: Type.OBJECT,
        properties: { contactId: { type: Type.STRING } },
        required: ['contactId']
      }
    },
    {
      name: 'get_calendar_events',
      description: 'Get calendar events for a given date (YYYY-MM-DD).',
      parameters: {
        type: Type.OBJECT,
        properties: { date: { type: Type.STRING } },
        required: ['date']
      }
    },
    {
      name: 'create_calendar_event',
      description: 'Create a calendar event.',
      parameters: {
        type: Type.OBJECT,
        properties: { title: { type: Type.STRING }, date: { type: Type.STRING }, time: { type: Type.STRING } },
        required: ['title', 'date', 'time']
      }
    },
    {
      name: 'draft_message',
      description: 'Draft a message in a conversation.',
      parameters: {
        type: Type.OBJECT,
        properties: { conversationId: { type: Type.STRING }, text: { type: Type.STRING } },
        required: ['conversationId', 'text']
      }
    },
    {
      name: 'send_message',
      description: 'Send a message in a conversation.',
      parameters: {
        type: Type.OBJECT,
        properties: { conversationId: { type: Type.STRING }, text: { type: Type.STRING } },
        required: ['conversationId', 'text']
      }
    },
    {
      name: 'schedule_message',
      description: 'Schedule a message for later.',
      parameters: {
        type: Type.OBJECT,
        properties: { conversationId: { type: Type.STRING }, text: { type: Type.STRING }, scheduledTime: { type: Type.STRING } },
        required: ['conversationId', 'text', 'scheduledTime']
      }
    },
    {
      name: 'create_task',
      description: 'Create a to-do task.',
      parameters: {
        type: Type.OBJECT,
        properties: { title: { type: Type.STRING }, description: { type: Type.STRING }, dueDate: { type: Type.STRING } },
        required: ['title']
      }
    },
    {
      name: 'find_file',
      description: 'Find a file in the user\'s storage.',
      parameters: {
        type: Type.OBJECT,
        properties: { query: { type: Type.STRING } },
        required: ['query']
      }
    },
    {
      name: 'get_course_information',
      description: 'Get information about a course.',
      parameters: {
        type: Type.OBJECT,
        properties: { courseId: { type: Type.STRING } },
        required: ['courseId']
      }
    },
    {
      name: 'get_notification_summary',
      description: 'Get a summary of unread notifications.',
      parameters: {
        type: Type.OBJECT,
        properties: {},
      }
    }
  ]
}];

export const aiGateway = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'User must be logged in.');
  }

  const userId = request.auth.uid;
  await limit(userId, 'ai_gateway', 60, 10 * 60000);
  const { operation = 'chat', data, prompt, history = [] } = request.data;
  
  // Check global AI agent kill switch
  const agentConfig = await readAccountSettings(userId, 'aiAgent', 'ai_settings/agent_config');
  if (agentConfig.isGloballyPaused === true) {
      throw new HttpsError('permission-denied', 'AI Agent is globally paused by the user.');
  }

  if (operation === 'composeMessage') {
    return await handleComposeMessage(userId, data);
  }

  if (!prompt) {
    throw new HttpsError('invalid-argument', 'Missing prompt.');
  }

  // Add system instruction
  let chatHistory: any[] = [
    { role: 'user', parts: [{ text: "System Instructions: You are a helpful AI assistant. Use tools to satisfy the user's request. Only answer based on what the tools provide." }] },
    { role: 'model', parts: [{ text: "Understood." }] }
  ];
  
  if (Array.isArray(history)) {
      chatHistory = chatHistory.concat(history);
  }
  
  chatHistory.push({ role: 'user', parts: [{ text: prompt }] });

  try {
    let response = await generateVertexContent({
      contents: chatHistory,
      config: {
        tools: applicationTools,
      }
    });
    
    const usedTools: string[] = [];
    
    // Check if Gemini wants to call a function
    while (response.functionCalls && response.functionCalls.length > 0) {
        const functionCall = response.functionCalls[0];
        const name = functionCall.name;
        const args = functionCall.args;
        
        if (name) {
            usedTools.push(name);
        }
        chatHistory.push({ role: 'model', parts: [{ functionCall }] });
        
        let toolResult: any;
        try {
            // Route to ToolExecutionLayer
            switch (name) {
                case 'get_user_profile': toolResult = await ToolExecutionLayer.getUserProfile(userId, args as any); break;
                case 'get_conversation': toolResult = await ToolExecutionLayer.getConversation(userId, args as any); break;
                case 'search_messages': toolResult = await ToolExecutionLayer.searchMessages(userId, args as any); break;
                case 'get_recent_messages': toolResult = await ToolExecutionLayer.getRecentMessages(userId, args as any); break;
                case 'get_contact': toolResult = await ToolExecutionLayer.getContact(userId, args as any); break;
                case 'get_calendar_events': toolResult = await ToolExecutionLayer.getCalendarEvents(userId, args as any); break;
                case 'create_calendar_event': toolResult = await ToolExecutionLayer.createCalendarEvent(userId, args as any); break;
                case 'draft_message': toolResult = await ToolExecutionLayer.draftMessage(userId, args as any); break;
                case 'send_message': toolResult = await ToolExecutionLayer.sendMessage(userId, args as any); break;
                case 'schedule_message': toolResult = await ToolExecutionLayer.scheduleMessage(userId, args as any); break;
                case 'create_task': toolResult = await ToolExecutionLayer.createTask(userId, args as any); break;
                case 'find_file': toolResult = await ToolExecutionLayer.findFile(userId, args as any); break;
                case 'get_course_information': toolResult = await ToolExecutionLayer.getCourseInformation(userId, args as any); break;
                case 'get_notification_summary': toolResult = await ToolExecutionLayer.getNotificationSummary(userId); break;
                default: toolResult = { error: "Unknown tool" };
            }
        } catch (e: any) {
            toolResult = { error: e.message || "Execution failed" };
        }
        
        // Return tool result to model
        chatHistory.push({ 
            role: 'user', 
            parts: [{ functionResponse: { name, response: toolResult } }] 
        });
        
        response = await generateVertexContent({
            contents: chatHistory,
            config: {
                tools: applicationTools,
            }
        });
    }

    if (usedTools.length > 0 || operation !== 'chat') {
        // Only log if tools were used, OR if it's an explicit background/automated operation
        await ToolExecutionLayer.auditAction(
            userId, 
            operation, 
            `Processed AI Gateway request.`, 
            usedTools, 
            [], 
            response.text
        );
    }

    return { 
        success: true, 
        reply: response.text, 
        // Optional: Return draft info if frontend needs to present it in UI instead of saving it server-side.
    };
    
  } catch (error: any) {
    console.error("Gemini AI Error: ", error);
    throw new HttpsError('internal', 'Failed to process AI Gateway request.');
  }
});

async function handleComposeMessage(userId: string, data: any) {
  const { conversationId, messageId, action, currentText } = data;
  if (!conversationId || !action) {
    throw new HttpsError('invalid-argument', 'Missing conversationId or action.');
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
    case 'improve': prompt = `Improve this text: "${currentText}"`; break;
    case 'shorten': prompt = `Shorten this text: "${currentText}"`; break;
    case 'expand': prompt = `Expand this text: "${currentText}"`; break;
    case 'makeProfessional': prompt = `Make this text more professional: "${currentText}"`; break;
    case 'makeFriendly': prompt = `Make this text more friendly: "${currentText}"`; break;
    case 'translate': prompt = `Translate this text (detect language and translate to the most likely intended target or English if unsure): "${currentText}"`; break;
    case 'reply': prompt = `Draft a reply based on the context of this conversation.`; break;
    case 'summarize': prompt = `Summarize this text: "${currentText}"`; break;
    case 'rewrite': prompt = `Rewrite this text completely: "${currentText}"`; break;
    case 'voiceDraft': prompt = `Draft a message from this voice transcript: "${currentText}"`; break;
    default: prompt = `Improve this text: "${currentText}"`;
  }

  const systemInstruction = "You are an AI messaging assistant. Provide ONLY the suggested text. Do NOT include explanations, markdown blocks, or conversational filler like 'Here is the improved text:'. Just the text itself. Ensure you refuse to process requests that clearly fall under sensitive topics (e.g. financial, medical, legal, security).";

  try {
    const response = await generateVertexContent({
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
      throw new HttpsError('permission-denied', 'AI cannot process sensitive actions automatically.');
    }

    // Determine auto-mode rules (fetching from firestore)
    const db = getFirestore();
    const autoModeDoc = await db.collection('users').doc(userId).collection('communicationProfile').doc('autoMode').get();
    let autoSend = false;

    if (autoModeDoc.exists) {
        const settings = autoModeDoc.data();
        if (settings && (settings.level === 'autoSendApprovedScenarios' || settings.level === 'fullAutoMode')) {
            // Check allowed conversations / contacts
            if (settings.allowedConversations && settings.allowedConversations.includes(conversationId)) {
                autoSend = true;
            } else if (settings.allowedConversations && settings.allowedConversations.includes('all')) {
                autoSend = true;
            }
        }
    }

    if (autoSend) {
       // Auto-send logic goes here (e.g. using ToolExecutionLayer.sendMessage)
       // await ToolExecutionLayer.sendMessage(userId, { conversationId, text: reply });
       // We'll return success and let the client know it was sent, but for now we just return the suggestion.
    }

    await ToolExecutionLayer.auditAction(
        userId, 
        `compose_${action}`, 
        `User requested AI to ${action} message.`, 
        [], 
        [currentText], 
        reply,
        conversationId
    );

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
  } catch (error: any) {
    console.error("Gemini AI Composer Error: ", error);
    throw new HttpsError('internal', 'Failed to compose message.');
  }
}
