import { Timestamp } from 'firebase-admin/firestore';

export type TriggerType = 
  | 'new_message'
  | 'keyword'
  | 'reaction'
  | 'new_follower'
  | 'new_contact'
  | 'form_submission'
  | 'scheduled_time'
  | 'webhook'
  | 'channel_event'
  | 'ai_classification';

export type ActionType = 
  | 'send_message'
  | 'create_draft'
  | 'assign_conversation'
  | 'add_label'
  | 'create_task'
  | 'schedule_message'
  | 'notify_team'
  | 'call_ai'
  | 'escalate'
  | 'update_contact'
  | 'create_calendar_event';

export type Operator = 
  | 'equals'
  | 'not_equals'
  | 'contains'
  | 'greater_than'
  | 'less_than'
  | 'exists';

export interface WorkflowCondition {
  field: string;
  operator: Operator;
  value: any;
}

export interface WorkflowAction {
  id: string; // Unique ID for the action node
  type: ActionType;
  payload: Record<string, any>; // Depends on the action type
  delaySeconds?: number; // Optional delay before execution
}

export interface WorkflowTrigger {
  type: TriggerType;
  config: Record<string, any>; // e.g., keyword to match, channel to listen to
}

export interface RetryPolicy {
  maxRetries: number;
  backoffType: 'linear' | 'exponential';
}

export interface WorkflowConfig {
  id?: string;
  name: string;
  description: string;
  enabled: boolean;
  version: number;
  ownerId: string;
  trigger: WorkflowTrigger;
  conditions: WorkflowCondition[];
  actions: WorkflowAction[];
  retryPolicy: RetryPolicy;
  rateLimitPerMinute: number;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

export type ExecutionStatus = 'pending' | 'running' | 'success' | 'failed' | 'aborted';

export interface ExecutionLog {
  id?: string;
  workflowId: string;
  triggerPayload: Record<string, any>;
  status: ExecutionStatus;
  startedAt: Timestamp;
  completedAt?: Timestamp;
  error?: string;
  executedActions: string[]; // List of action IDs successfully executed
}
