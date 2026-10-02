import WebSocket from "ws";
import { EventEmitter } from "events";
import * as http from "http";
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

export class GhostGatewayClient extends EventEmitter {
  private ws: WebSocket | null = null;
  private state: ConnectionState = "disconnected";
  private pendingRequests: Map<
    string | number,
    {
      resolve: (value: any) => void;
      reject: (reason: any) => void;
      timer: NodeJS.Timeout;
    }
  > = new Map();
  private nextId = 1;
  private reconnectTimer: NodeJS.Timeout | null = null;
  private currentUrl = "ws://localhost:3000";
  private currentToken = "";
  private autoReconnect = true;
  private pingTimer: NodeJS.Timeout | null = null;

  constructor() {
    super();
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
  public async autoDiscoverToken(httpUrl: string): Promise<string | null> {
    return new Promise((resolve) => {
      try {
        const url = new URL("/client-token", httpUrl);
        const req = http.get(url, { timeout: 1500 }, (res) => {
          if (res.statusCode !== 200) {
            return resolve(null);
          }
          let data = "";
          res.on("data", (chunk) => (data += chunk));
          res.on("end", () => {
            try {
              const json = JSON.parse(data);
              if (json && json.token) {
                resolve(json.token);
              } else {
                resolve(null);
              }
            } catch {
              resolve(null);
            }
          });
        });
        req.on("error", () => resolve(null));
        req.on("timeout", () => {
          req.destroy();
          resolve(null);
        });
      } catch {
        resolve(null);
      }
    });
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

    // If no token was provided, try auto-discovery via HTTP if connecting to localhost
    if (!this.currentToken && (url.includes("localhost") || url.includes("127.0.0.1"))) {
      const httpBase = url.replace("ws://", "http://").replace("wss://", "https://");
      const discoveredToken = await this.autoDiscoverToken(httpBase);
      if (discoveredToken) {
        this.currentToken = discoveredToken;
      }
    }

    return new Promise<boolean>((resolve) => {
      let resolved = false;

      try {
        this.ws = new WebSocket(this.currentUrl);

        this.ws.on("open", async () => {
          this.startHeartbeat();
          // Authenticate if token is available
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
        });

        this.ws.on("message", (data: WebSocket.Data) => {
          this.handleMessage(data.toString());
        });

        this.ws.on("close", (code, reason) => {
          this.stopHeartbeat();
          this.rejectAllPending("Connection closed");
          this.setState("disconnected", `Closed (${code}): ${reason}`);
          if (!resolved) {
            resolved = true;
            resolve(false);
          }
          if (this.autoReconnect) {
            this.scheduleReconnect();
          }
        });

        this.ws.on("error", (err) => {
          this.setState("error", err.message);
          if (!resolved) {
            resolved = true;
            resolve(false);
          }
        });
      } catch (err: any) {
        this.setState("error", err.message);
        if (!resolved) {
          resolved = true;
          resolve(false);
        }
      }
    });
  }

  public disconnect() {
    this.autoReconnect = false;
    this.stopHeartbeat();
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    if (this.ws) {
      try {
        this.ws.terminate();
      } catch {}
      this.ws = null;
    }
    this.rejectAllPending("Disconnected by user");
    this.setState("disconnected");
  }

  private scheduleReconnect() {
    if (this.reconnectTimer || !this.autoReconnect) return;
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      if (this.state === "disconnected" || this.state === "error") {
        this.connect(this.currentUrl, this.currentToken);
      }
    }, 4000);
  }

  private startHeartbeat() {
    this.stopHeartbeat();
    this.pingTimer = setInterval(() => {
      if (this.ws && this.ws.readyState === WebSocket.OPEN) {
        this.sendRpc("gateway.health", {}).catch(() => {});
      }
    }, 25000);
  }

  private stopHeartbeat() {
    if (this.pingTimer) {
      clearInterval(this.pingTimer);
      this.pingTimer = null;
    }
  }

  private rejectAllPending(reason: string) {
    for (const [, req] of this.pendingRequests.entries()) {
      clearTimeout(req.timer);
      req.reject(new Error(reason));
    }
    this.pendingRequests.clear();
  }

  private handleMessage(raw: string) {
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

      // Check if it's a notification / event (no id, but method)
      if (msg.method) {
        this.handleNotification(msg.method, msg.params);
      }
    } catch (e) {
      console.error("[GhostGatewayClient] Failed to parse message:", e, raw);
    }
  }

  private handleNotification(method: string, params: any) {
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
      const timer = setTimeout(() => {
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
      channelType: "vscode",
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
