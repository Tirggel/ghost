/**
 * JSON-RPC 2.0 & Ghost Protocol Definitions
 */

export interface RpcRequest<T = Record<string, unknown>> {
  jsonrpc: "2.0";
  method: string;
  params?: T;
  id?: string | number;
}

export interface RpcResponse<T = unknown> {
  jsonrpc: "2.0";
  id: string | number | null;
  result?: T;
  error?: RpcError;
}

export interface RpcError {
  code: number;
  message: string;
  data?: unknown;
}

export interface MessageAttachment {
  type: string;
  name: string;
  data: string;
  mimeType?: string;
}

export interface Message {
  id?: string;
  role: "user" | "assistant" | "system";
  content: string;
  timestamp?: string;
  attachments?: MessageAttachment[];
  metadata?: Record<string, unknown>;
}

export interface SessionInfo {
  id: string;
  title?: string;
  channelType?: string;
  model?: string;
  provider?: string;
  agentId?: string;
  agentName?: string;
  messageCount?: number;
  lastActiveAt?: string;
}

export interface AgentStreamPayload {
  sessionId: string;
  chunk: string;
}

export interface AgentActivityPayload {
  sessionId: string;
  activity: string;
}

export interface AgentResponsePayload {
  sessionId: string;
  message: Message;
}

export interface AgentErrorPayload {
  sessionId: string;
  error: string;
}

export interface SessionUpdatedPayload {
  sessionId: string;
  title?: string;
}
