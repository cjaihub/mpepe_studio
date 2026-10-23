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
exports.executeWorkflowActions = executeWorkflowActions;
const functions = __importStar(require("firebase-functions/v2"));
const firestore_1 = require("firebase-admin/firestore");
const db = (0, firestore_1.getFirestore)();
/**
 * Sequential execution of workflow actions.
 * Updates the ExecutionLog in Firestore.
 */
async function executeWorkflowActions(workflow, executionId, triggerPayload, currentDepth) {
    const executionRef = db.collection('workflow_executions').doc(executionId);
    const executedActions = [];
    try {
        await executionRef.update({ status: 'running' });
        for (const action of workflow.actions) {
            // Handle Delay/Schedule natively by checking if delaySeconds exists
            if (action.delaySeconds && action.delaySeconds > 0) {
                // NOTE: In a true production environment, we would dispatch this to Cloud Tasks 
                // to resume execution later. For now, we simulate with a Promise delay.
                // Google Cloud Tasks would invoke a separate function with the remaining actions.
                await new Promise(resolve => setTimeout(resolve, action.delaySeconds * 1000));
            }
            await executeSingleAction(action, triggerPayload, workflow, currentDepth);
            executedActions.push(action.id);
            // Update execution log progressively
            await executionRef.update({ executedActions });
        }
        await executionRef.update({
            status: 'success',
            completedAt: firestore_1.Timestamp.now()
        });
    }
    catch (error) {
        functions.logger.error(`Workflow ${workflow.id} failed at execution ${executionId}:`, error);
        await executionRef.update({
            status: 'failed',
            error: error.message || 'Unknown error',
            completedAt: firestore_1.Timestamp.now()
        });
    }
}
async function executeSingleAction(action, payload, workflow, currentDepth) {
    switch (action.type) {
        case 'send_message':
            await handleSendMessage(action, payload);
            break;
        case 'create_task':
            await handleCreateTask(action, payload);
            break;
        case 'add_label':
            await handleAddLabel(action, payload);
            break;
        case 'call_ai':
            await handleCallAi(action, payload);
            break;
        case 'notify_team':
            await handleNotifyTeam(action, payload);
            break;
        // ... Implement other actions ...
        default:
            functions.logger.warn(`Unknown action type: ${action.type}`);
    }
    // To allow actions to trigger OTHER workflows, we can optionally dispatch events here.
    // CAUTION: This increases trigger depth.
    // Example: if (action.type === 'send_message') await processTrigger('new_message', newMessagePayload, 'system', currentDepth + 1);
}
// ---- Action Handlers ---- //
async function handleSendMessage(action, payload) {
    const { content, conversationId } = action.payload;
    if (!content || !conversationId)
        throw new Error("Missing content or conversationId for send_message");
    await db.collection('messages').add({
        content: interpolateString(content, payload),
        conversationId: interpolateString(conversationId, payload),
        senderId: 'system_workflow',
        createdAt: firestore_1.Timestamp.now()
    });
}
async function handleCreateTask(action, payload) {
    const { title, assigneeId } = action.payload;
    await db.collection('tasks').add({
        title: interpolateString(title, payload),
        assigneeId: interpolateString(assigneeId, payload),
        status: 'pending',
        createdAt: firestore_1.Timestamp.now()
    });
}
async function handleAddLabel(action, payload) {
    const { contactId, label } = action.payload;
    if (!contactId || !label)
        return;
    await db.collection('user_contacts').doc(contactId).update({
        tags: firestore_1.FieldValue.arrayUnion(label)
    });
}
async function handleCallAi(action, payload) {
    const { prompt } = action.payload;
    // Integrate with existing AI gateway
    functions.logger.info(`Simulating AI call with prompt: ${interpolateString(prompt, payload)}`);
}
async function handleNotifyTeam(action, payload) {
    const { message, channelId } = action.payload;
    // Implement team notification logic
    functions.logger.info(`Notifying channel ${channelId}: ${interpolateString(message, payload)}`);
}
/**
 * Very basic string interpolation to inject trigger payload values into action configurations.
 * e.g., "Hello {{sender.name}}" -> "Hello Alice"
 */
function interpolateString(template, payload) {
    if (!template)
        return template;
    return template.replace(/\{\{([\w.]+)\}\}/g, (_, path) => {
        const value = path.split('.').reduce((acc, part) => acc && acc[part], payload);
        return value !== undefined ? String(value) : '';
    });
}
//# sourceMappingURL=workflowActions.js.map