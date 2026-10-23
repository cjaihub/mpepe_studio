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
exports.webhookWorkflowTrigger = exports.onMessageCreatedWorkflowTrigger = void 0;
exports.processTrigger = processTrigger;
const functions = __importStar(require("firebase-functions/v2"));
const firestore_1 = require("firebase-admin/firestore");
const workflowActions_1 = require("./workflowActions");
const db = (0, firestore_1.getFirestore)();
// Safeguard constants
const MAX_TRIGGER_DEPTH = 5;
const RATE_LIMIT_WINDOW_MS = 60000; // 1 minute
async function processTrigger(triggerType, payload, sourceUserId, triggerDepth = 0) {
    if (triggerDepth > MAX_TRIGGER_DEPTH) {
        functions.logger.warn(`Max trigger depth exceeded for trigger: ${triggerType}. Aborting to prevent infinite loop.`);
        return;
    }
    // Find all enabled workflows matching this trigger type
    const workflowsSnapshot = await db.collection('workflows')
        .where('enabled', '==', true)
        .where('trigger.type', '==', triggerType)
        .get();
    if (workflowsSnapshot.empty)
        return;
    const workflows = workflowsSnapshot.docs.map((doc) => Object.assign({ id: doc.id }, doc.data()));
    for (const workflow of workflows) {
        // 1. Evaluate conditions
        const conditionsPassed = evaluateConditions(workflow.conditions, payload);
        if (!conditionsPassed)
            continue;
        // 2. Check rate limits
        const canExecute = await checkRateLimit(workflow);
        if (!canExecute) {
            functions.logger.warn(`Rate limit exceeded for workflow: ${workflow.id}`);
            continue;
        }
        // 3. Create execution log (Pending)
        const executionRef = db.collection('workflow_executions').doc();
        const execution = {
            workflowId: workflow.id,
            triggerPayload: payload,
            status: 'pending',
            startedAt: firestore_1.Timestamp.now(),
            executedActions: []
        };
        await executionRef.set(execution);
        // 4. Delegate to action executor
        // In a fully robust system, this could be pushed to Cloud Tasks for guaranteed delivery and delay support.
        // For now, we execute inline asynchronously.
        (0, workflowActions_1.executeWorkflowActions)(workflow, executionRef.id, payload, triggerDepth + 1).catch(err => {
            functions.logger.error(`Error executing workflow ${workflow.id}:`, err);
        });
    }
}
function evaluateConditions(conditions, payload) {
    for (const cond of conditions) {
        const fieldValue = getNestedValue(payload, cond.field);
        switch (cond.operator) {
            case 'equals':
                if (fieldValue !== cond.value)
                    return false;
                break;
            case 'not_equals':
                if (fieldValue === cond.value)
                    return false;
                break;
            case 'contains':
                if (!String(fieldValue).includes(String(cond.value)))
                    return false;
                break;
            case 'greater_than':
                if (fieldValue <= cond.value)
                    return false;
                break;
            case 'less_than':
                if (fieldValue >= cond.value)
                    return false;
                break;
            case 'exists':
                if (fieldValue === undefined || fieldValue === null)
                    return false;
                break;
            default:
                return false;
        }
    }
    return true;
}
function getNestedValue(obj, path) {
    return path.split('.').reduce((acc, part) => acc && acc[part], obj);
}
/**
 * Ensures the workflow is not executed more than `rateLimitPerMinute` times.
 * Uses Firestore transactions for concurrency locking.
 */
async function checkRateLimit(workflow) {
    if (!workflow.rateLimitPerMinute || workflow.rateLimitPerMinute <= 0)
        return true;
    const rateLimitRef = db.collection('workflow_rate_limits').doc(workflow.id);
    return await db.runTransaction(async (transaction) => {
        const doc = await transaction.get(rateLimitRef);
        const now = Date.now();
        if (!doc.exists) {
            transaction.set(rateLimitRef, {
                executions: [now]
            });
            return true;
        }
        const data = doc.data();
        let executions = data.executions || [];
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
exports.onMessageCreatedWorkflowTrigger = functions.firestore
    .onDocumentCreated('messages/{messageId}', async (event) => {
    const snapshot = event.data;
    if (!snapshot)
        return;
    const data = snapshot.data();
    await processTrigger('new_message', data, data.senderId);
});
exports.webhookWorkflowTrigger = functions.https.onRequest(async (req, res) => {
    const { workflowId, payload } = req.body;
    if (!workflowId || !payload) {
        res.status(400).send('Missing workflowId or payload');
        return;
    }
    // Custom webhook trigger routing
    await processTrigger('webhook', payload, 'system');
    res.status(200).send({ success: true });
});
//# sourceMappingURL=workflows.js.map