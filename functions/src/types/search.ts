import { Timestamp } from 'firebase-admin/firestore';

export type SearchEntityType = 'message' | 'person' | 'channel' | 'file' | 'post' | 'notification' | 'ai_history';

export interface SearchIndexDocument {
  id: string; // The original document ID (e.g., messageId or userId)
  type: SearchEntityType;
  title: string;
  subtitle?: string;
  content: string; // Full text for vector embedding if enabled
  keywords: string[]; // n-grams or tokens for exact match 'array-contains'
  metadata: {
    channelId?: string;
    senderId?: string;
    hasAttachment?: boolean;
    attachmentType?: string;
    [key: string]: any;
  };
  createdAt: Timestamp;
  updatedAt: Timestamp;
  
  // Permissions (ACLs)
  acl_users: string[]; // List of user IDs who can see this. Empty implies relies on acl_public.
  acl_public: boolean; // If true, anyone can see this.

  // Optional Semantic Search
  // Note: For Firestore vector search, this will be stored as a VectorValue. We type it as number[] for now.
  embedding?: number[]; 
}
