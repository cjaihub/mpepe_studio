import * as functions from 'firebase-functions/v2';

import { getFirestore, Timestamp, FieldValue } from 'firebase-admin/firestore';
import { WorkflowConfig, WorkflowAction } from './types/workflow';

const db = getFirestore();

/**
 * Sequential execution of workflow actions.
 * Updates the ExecutionLog in Firestore.
 */
export async function executeWorkflowActions(
  workflow: WorkflowConfig,
  executionId: string,
  triggerPayload: Record<string, any>,
  currentDepth: number
) {
  const executionRef = db.collection('workflow_executions').doc(executionId);
  const executedActions: string[] = [];
  
  try {
    await executionRef.update({ status: 'running' });

    for (const action of workflow.actions) {
      // Handle Delay/Schedule natively by checking if delaySeconds exists
      if (action.delaySeconds && action.delaySeconds > 0) {
        // NOTE: In a true production environment, we would dispatch this to Cloud Tasks 
        // to resume execution later. For now, we simulate with a Promise delay.
        // Google Cloud Tasks would invoke a separate function with the remaining actions.
        await new Promise(resolve => setTimeout(resolve, action.delaySeconds! * 1000));
      }

      await executeSingleAction(action, triggerPayload, workflow, currentDepth);
      executedActions.push(action.id);
      
      // Update execution log progressively
      await executionRef.update({ executedActions });
    }

    await executionRef.update({ 
      status: 'success', 
      completedAt: Timestamp.now() 
    });
  } catch (error: any) {
    functions.logger.error(`Workflow ${workflow.id} failed at execution ${executionId}:`, error);
    await executionRef.update({ 
      status: 'failed', 
      error: error.message || 'Unknown error',
      completedAt: Timestamp.now() 
    });
  }
}

async function executeSingleAction(
  action: WorkflowAction, 
  payload: Record<string, any>,
  workflow: WorkflowConfig,
  currentDepth: number
) {
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

async function handleSendMessage(action: WorkflowAction, payload: Record<string, any>) {
  const { content, conversationId } = action.payload;
  if (!content || !conversationId) throw new Error("Missing content or conversationId for send_message");
  
  await db.collection('messages').add({
    content: interpolateString(content, payload),
    conversationId: interpolateString(conversationId, payload),
    senderId: 'system_workflow',
    createdAt: Timestamp.now()
  });
}

async function handleCreateTask(action: WorkflowAction, payload: Record<string, any>) {
  const { title, assigneeId } = action.payload;
  
  await db.collection('tasks').add({
    title: interpolateString(title, payload),
    assigneeId: interpolateString(assigneeId, payload),
    status: 'pending',
    createdAt: Timestamp.now()
  });
}

async function handleAddLabel(action: WorkflowAction, payload: Record<string, any>) {
  const { contactId, label } = action.payload;
  if (!contactId || !label) return;

  await db.collection('user_contacts').doc(contactId).update({
    tags: FieldValue.arrayUnion(label)
  });
}

async function handleCallAi(action: WorkflowAction, payload: Record<string, any>) {
  const { prompt } = action.payload;
  // Integrate with existing AI gateway
  functions.logger.info(`Simulating AI call with prompt: ${interpolateString(prompt, payload)}`);
}

async function handleNotifyTeam(action: WorkflowAction, payload: Record<string, any>) {
  const { message, channelId } = action.payload;
  // Implement team notification logic
  functions.logger.info(`Notifying channel ${channelId}: ${interpolateString(message, payload)}`);
}

/**
 * Very basic string interpolation to inject trigger payload values into action configurations.
 * e.g., "Hello {{sender.name}}" -> "Hello Alice"
 */
function interpolateString(template: string, payload: Record<string, any>): string {
  if (!template) return template;
  return template.replace(/\{\{([\w.]+)\}\}/g, (_, path) => {
    const value = path.split('.').reduce((acc: any, part: string) => acc && acc[part], payload);
    return value !== undefined ? String(value) : '';
  });
}
