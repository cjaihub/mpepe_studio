import * as functions from 'firebase-functions/v2';

import { getFirestore, Timestamp, Transaction, DocumentSnapshot } from 'firebase-admin/firestore';
import { 
  WorkflowConfig, 
  TriggerType, 
  ExecutionLog, 
  WorkflowCondition 
} from './types/workflow';
import { executeWorkflowActions } from './workflowActions';

const db = getFirestore();

// Safeguard constants
const MAX_TRIGGER_DEPTH = 5;
const RATE_LIMIT_WINDOW_MS = 60000; // 1 minute

export async function processTrigger(
  triggerType: TriggerType, 
  payload: Record<string, any>, 
  sourceUserId: string,
  triggerDepth: number = 0
) {
  if (triggerDepth > MAX_TRIGGER_DEPTH) {
    functions.logger.warn(`Max trigger depth exceeded for trigger: ${triggerType}. Aborting to prevent infinite loop.`);
    return;
  }

  // Find all enabled workflows matching this trigger type
  const workflowsSnapshot = await db.collection('workflows')
    .where('enabled', '==', true)
    .where('trigger.type', '==', triggerType)
    .get();

  if (workflowsSnapshot.empty) return;

  const workflows = workflowsSnapshot.docs.map((doc: DocumentSnapshot) => ({ id: doc.id, ...doc.data() } as WorkflowConfig));

  for (const workflow of workflows) {
    // 1. Evaluate conditions
    const conditionsPassed = evaluateConditions(workflow.conditions, payload);
    if (!conditionsPassed) continue;

    // 2. Check rate limits
    const canExecute = await checkRateLimit(workflow);
    if (!canExecute) {
      functions.logger.warn(`Rate limit exceeded for workflow: ${workflow.id}`);
      continue;
    }

    // 3. Create execution log (Pending)
    const executionRef = db.collection('workflow_executions').doc();
    const execution: ExecutionLog = {
      workflowId: workflow.id!,
      triggerPayload: payload,
      status: 'pending',
      startedAt: Timestamp.now(),
      executedActions: []
    };
    
    await executionRef.set(execution);

    // 4. Delegate to action executor
    // In a fully robust system, this could be pushed to Cloud Tasks for guaranteed delivery and delay support.
    // For now, we execute inline asynchronously.
    executeWorkflowActions(workflow, executionRef.id, payload, triggerDepth + 1).catch(err => {
      functions.logger.error(`Error executing workflow ${workflow.id}:`, err);
    });
  }
}

function evaluateConditions(conditions: WorkflowCondition[], payload: Record<string, any>): boolean {
  for (const cond of conditions) {
    const fieldValue = getNestedValue(payload, cond.field);
    
    switch (cond.operator) {
      case 'equals':
        if (fieldValue !== cond.value) return false;
        break;
      case 'not_equals':
        if (fieldValue === cond.value) return false;
        break;
      case 'contains':
        if (!String(fieldValue).includes(String(cond.value))) return false;
        break;
      case 'greater_than':
        if (fieldValue <= cond.value) return false;
        break;
      case 'less_than':
        if (fieldValue >= cond.value) return false;
        break;
      case 'exists':
        if (fieldValue === undefined || fieldValue === null) return false;
        break;
      default:
        return false;
    }
  }
  return true;
}

function getNestedValue(obj: any, path: string): any {
  return path.split('.').reduce((acc, part) => acc && acc[part], obj);
}

/**
 * Ensures the workflow is not executed more than `rateLimitPerMinute` times.
 * Uses Firestore transactions for concurrency locking.
 */
async function checkRateLimit(workflow: WorkflowConfig): Promise<boolean> {
  if (!workflow.rateLimitPerMinute || workflow.rateLimitPerMinute <= 0) return true;

  const rateLimitRef = db.collection('workflow_rate_limits').doc(workflow.id!);
  
  return await db.runTransaction(async (transaction: Transaction) => {
    const doc = await transaction.get(rateLimitRef);
    const now = Date.now();
    
    if (!doc.exists) {
      transaction.set(rateLimitRef, {
        executions: [now]
      });
      return true;
    }

    const data = doc.data()!;
    let executions: number[] = data.executions || [];
    
    // Filter executions within the last minute
    executions = executions.filter(t => now - t < RATE_LIMIT_WINDOW_MS);
    
    if (executions.length >= workflow.rateLimitPerMinute) {
      return false; // Rate limit exceeded
    }
    
    executions.push(now);
    transaction.update(rateLimitRef, { executions });
    return true;
  });
}

// ------------------------------------------------------------------
// Triggers (Cloud Functions)
// ------------------------------------------------------------------

export const onMessageCreatedWorkflowTrigger = functions.firestore
  .onDocumentCreated('messages/{messageId}', async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const data = snapshot.data();
    await processTrigger('new_message', data, data.senderId);
  });

export const webhookWorkflowTrigger = functions.https.onRequest(async (req, res) => {
  const { workflowId, payload } = req.body;
  if (!workflowId || !payload) {
    res.status(400).send('Missing workflowId or payload');
    return;
  }
  // Custom webhook trigger routing
  await processTrigger('webhook', payload, 'system');
  res.status(200).send({ success: true });
});
