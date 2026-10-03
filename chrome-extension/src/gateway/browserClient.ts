/**
 * Ghost Gateway Client for Browser environments (Chrome Extension)
 * Communicates with Ghost Gateway over WebSocket JSON-RPC 2.0.
 */

import {
  RpcRequest,
  Message,
  SessionInfo,
  AgentStreamPayload,
  AgentActivityPayload,
  AgentResponsePayload,
  AgentErrorPayload,
  SessionUpdatedPayload,
} from "./protocol";

export type ConnectionState = "disconnected" | "connecting" | "connected" | "error";

type EventCallback = (...args: any[]) => void;

export class GhostBrowserClient {
  private ws: WebSocket | null = null;
  private state: ConnectionState = "disconnected";
  private listeners: Map<string, Set<EventCallback>> = new Map();
  private pendingRequests: Map<
    string | number,
    {
      resolve: (value: any) => void;
      reject: (reason: any) => void;
      timer: number;
    }
  > = new Map();
  private nextId = 1;
  private reconnectTimer: number | null = null;
  private pingTimer: number | null = null;
  private currentUrl = "ws://localhost:3000";
  private currentToken = "";
  private autoReconnect = true;

  constructor() {}

  public on(event: string, callback: EventCallback): void {
    if (!this.listeners.has(event)) {
      this.listeners.set(event, new Set());
    }
    this.listeners.get(event)!.add(callback);
  }

  public off(event: string, callback: EventCallback): void {
    const set = this.listeners.get(event);
    if (set) {
      set.delete(callback);
    }
  }

  private emit(event: string, ...args: any[]): void {
    const set = this.listeners.get(event);
    if (set) {
      for (const cb of set) {
        try {
          cb(...args);
        } catch (e) {
          console.error(`[GhostBrowserClient] Error in listener for ${event}:`, e);
        }
      }
    }
  }

  public getState(): ConnectionState {
    return this.state;
  }

  public getUrl(): string {
    return this.currentUrl;
  }

  private setState(newState: ConnectionState, message?: string) {
    if (this.state !== newState) {
      this.state = newState;
      this.emit("stateChange", newState, message);
    }
  }

  /**
   * Attempt to fetch the client token from the local Ghost HTTP endpoint.
   */
  public async autoDiscoverToken(httpBaseUrl: string): Promise<string | null> {
    try {
      const url = new URL("/client-token", httpBaseUrl);
      const res = await fetch(url.toString(), {
        signal: AbortSignal.timeout(1500),
        headers: { Accept: "application/json" },
      });
      if (!res.ok) return null;
      const data = await res.json();
      return data?.token || null;
    } catch {
      return null;
    }
  }

  /**
   * Connect to the Ghost WebSocket Gateway.
   */
  public async connect(url = "ws://localhost:3000", token = ""): Promise<boolean> {
    this.currentUrl = url;
    this.currentToken = token;
    this.autoReconnect = true;

    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }

    if (this.ws && (this.ws.readyState === WebSocket.OPEN || this.ws.readyState === WebSocket.CONNECTING)) {
      this.disconnect();
    }

    this.setState("connecting");

    // Try auto-discovery if connecting to localhost and no token provided
    if (!this.currentToken && (url.includes("localhost") || url.includes("127.0.0.1"))) {
      const httpBase = url.replace("ws://", "http://").replace("wss://", "https://");
      const discovered = await this.autoDiscoverToken(httpBase);
      if (discovered) {
        this.currentToken = discovered;
      }
    }

    return new Promise<boolean>((resolve) => {
      let resolved = false;

      try {
        this.ws = new WebSocket(this.currentUrl);

        this.ws.onopen = async () => {
          this.startHeartbeat();

          try {
            if (this.currentToken) {
              await this.sendRpc<{ authenticated: boolean }>("auth.login", {
                token: this.currentToken,
              });
            }
            this.setState("connected");
            if (!resolved) {
              resolved = true;
              resolve(true);
            }
          } catch (authErr: any) {
            // Some configurations might run in AuthMode.none
            if (authErr?.message?.includes("none")) {
              this.setState("connected");
              if (!resolved) {
                resolved = true;
                resolve(true);
              }
            } else {
              this.setState("error", `Auth failed: ${authErr?.message || authErr}`);
              if (!resolved) {
                resolved = true;
                resolve(false);
              }
            }
          }
        };

        this.ws.onmessage = (event: MessageEvent) => {
          this.handleMessage(String(event.data));
        };

        this.ws.onclose = (event: CloseEvent) => {
          this.stopHeartbeat();
          this.rejectAllPending("Connection closed");
          this.setState("disconnected", `Closed (${event.code}): ${event.reason}`);
          if (!resolved) {
            resolved = true;
            resolve(false);
          }
          if (this.autoReconnect) {
            this.scheduleReconnect();
          }
        };

        this.ws.onerror = () => {
          this.setState("error", "WebSocket-Verbindungsfehler");
          if (!resolved) {
            resolved = true;
            resolve(false);
          }
        };
      } catch (err: any) {
        this.setState("error", err.message);
        if (!resolved) {
          resolved = true;
          resolve(false);
        }
      }
    });
  }

  public disconnect(): void {
    this.autoReconnect = false;
    this.stopHeartbeat();
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    if (this.ws) {
      try {
        this.ws.close();
      } catch {}
      this.ws = null;
    }
    this.rejectAllPending("Disconnected by user");
    this.setState("disconnected");
  }

  private scheduleReconnect(): void {
    if (this.reconnectTimer || !this.autoReconnect) return;
    this.reconnectTimer = window.setTimeout(() => {
      this.reconnectTimer = null;
      if (this.state === "disconnected" || this.state === "error") {
        this.connect(this.currentUrl, this.currentToken);
      }
    }, 4000);
  }

  private startHeartbeat(): void {
    this.stopHeartbeat();
    this.pingTimer = window.setInterval(() => {
      if (this.ws && this.ws.readyState === WebSocket.OPEN) {
        this.sendRpc("gateway.health", {}).catch(() => {});
      }
    }, 25000);
  }

  private stopHeartbeat(): void {
    if (this.pingTimer) {
      clearInterval(this.pingTimer);
      this.pingTimer = null;
    }
  }

  private rejectAllPending(reason: string): void {
    for (const [, req] of this.pendingRequests.entries()) {
      clearTimeout(req.timer);
      req.reject(new Error(reason));
    }
    this.pendingRequests.clear();
  }

  private handleMessage(raw: string): void {
    try {
      const msg = JSON.parse(raw);

      // Check if it's an RPC response (has id)
      if (msg.id !== undefined && msg.id !== null) {
        const pending = this.pendingRequests.get(msg.id);
        if (pending) {
          clearTimeout(pending.timer);
          this.pendingRequests.delete(msg.id);
          if (msg.error) {
            pending.reject(msg.error);
          } else {
            pending.resolve(msg.result);
          }
        }
        return;
      }

      // Notification / Server event (no id, but method)
      if (msg.method) {
        this.handleNotification(msg.method, msg.params);
      }
    } catch (e) {
      console.error("[GhostBrowserClient] Failed to parse message:", e, raw);
    }
  }

  private handleNotification(method: string, params: any): void {
    switch (method) {
      case "agent.stream":
        this.emit("stream", params as AgentStreamPayload);
        break;
      case "agent.activity":
        this.emit("activity", params as AgentActivityPayload);
        break;
      case "agent.response":
        this.emit("response", params as AgentResponsePayload);
        break;
      case "agent.error":
        this.emit("error", params as AgentErrorPayload);
        break;
      case "agent.session_updated":
        this.emit("sessionUpdated", params as SessionUpdatedPayload);
        break;
      case "agent.session_deleted":
        this.emit("sessionDeleted", params);
        break;
      case "agent.sessions_cleared":
        this.emit("sessionsCleared", params);
        break;
      case "config.changed":
        this.emit("configChanged");
        break;
      case "skills.changed":
        this.emit("skillsChanged");
        break;
      case "kanban.changed":
        this.emit("kanbanChanged");
        break;
      case "gateway.log":
        this.emit("log", params);
        break;
    }
  }

  /**
   * Send a JSON-RPC 2.0 Request and await the response.
   */
  public sendRpc<T = any>(method: string, params?: Record<string, unknown>, timeoutMs = 30000): Promise<T> {
    if (!this.ws || this.ws.readyState !== WebSocket.OPEN) {
      return Promise.reject(new Error("Gateway nicht verbunden."));
    }

    const id = this.nextId++;
    const request: RpcRequest = {
      jsonrpc: "2.0",
      method,
      params,
      id,
    };

    return new Promise<T>((resolve, reject) => {
      const timer = window.setTimeout(() => {
        this.pendingRequests.delete(id);
        reject(new Error(`Timeout bei RPC-Aufruf '${method}' nach ${timeoutMs}ms.`));
      }, timeoutMs);

      this.pendingRequests.set(id, { resolve, reject, timer });

      try {
        this.ws!.send(JSON.stringify(request));
      } catch (err) {
        clearTimeout(timer);
        this.pendingRequests.delete(id);
        reject(err);
      }
    });
  }

  // --- High-Level Methods ---

  public async chat(
    content: string,
    options: {
      sessionId?: string;
      model?: string;
      provider?: string;
      agentId?: string;
      workspaceDir?: string;
      attachments?: any[];
    } = {}
  ): Promise<{ sessionId: string; status: string }> {
    return this.sendRpc<{ sessionId: string; status: string }>("agent.chat", {
      content,
      channelType: "chrome",
      sessionId: options.sessionId,
      model: options.model,
      provider: options.provider,
      agentId: options.agentId,
      workspaceDir: options.workspaceDir,
      attachments: options.attachments,
    });
  }

  public async getHistory(sessionId: string, maxMessages = 50): Promise<Message[]> {
    const res = await this.sendRpc<{ sessionId: string; messages: Message[] }>("agent.history", {
      sessionId,
      maxMessages,
    });
    return res.messages || [];
  }

  public async getSessions(): Promise<SessionInfo[]> {
    const res = await this.sendRpc<{ sessions: SessionInfo[] }>("agent.sessions");
    return res.sessions || [];
  }

  public async deleteSession(sessionId: string): Promise<void> {
    await this.sendRpc("agent.deleteSession", { sessionId });
  }

  public async deleteAllSessions(): Promise<void> {
    await this.sendRpc("agent.deleteSession", { all: true });
  }

  public async getConfig(): Promise<any> {
    return this.sendRpc("config.get");
  }

  public async setModel(model: string, provider?: string): Promise<any> {
    return this.sendRpc("config.setModel", { model, provider });
  }

  public async getKey(service: string): Promise<string> {
    try {
      const res = await this.sendRpc<{ key: string }>("config.getKey", { service });
      return res?.key || "";
    } catch {
      return "";
    }
  }

  public async setKey(service: string, key: string): Promise<any> {
    return this.sendRpc("config.setKey", { service, key });
  }

  public async setSessionModel(sessionId: string, model: string, provider?: string): Promise<void> {
    await this.sendRpc("agent.setSessionModel", { sessionId, model, provider });
  }

  public async setSessionTitle(sessionId: string, title: string): Promise<void> {
    await this.sendRpc("agent.setSessionTitle", { sessionId, title });
  }

  public async stop(sessionId: string): Promise<void> {
    await this.sendRpc("agent.stop", { sessionId });
  }

  public async listModels(provider?: string): Promise<string[]> {
    try {
      const res = await this.sendRpc<{ models: string[] }>("config.listModels", { provider });
      return res.models || [];
    } catch {
      return [];
    }
  }

  public async getStatus(): Promise<any> {
    return this.sendRpc("gateway.status");
  }
}
