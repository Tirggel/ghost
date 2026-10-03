/**
 * Ghost Side Panel Application Logic
 */

import { GhostBrowserClient, ConnectionState } from "../gateway/browserClient";
import { Message, SessionInfo } from "../gateway/protocol";
import { extractPageContext, PageContext } from "../utils/domExtractor";

class GhostSidePanel {
  private client: GhostBrowserClient;
  private currentSessionId: string | null = null;
  private isStreaming = false;
  private attachedContext: PageContext | null = null;
  private autoSyncTab = true;

  // DOM Elements
  private statusBadge!: HTMLElement;
  private statusDot!: HTMLElement;
  private statusText!: HTMLElement;
  private sessionSelect!: HTMLSelectElement;
  private newSessionBtn!: HTMLButtonElement;
  private deleteSessionBtn!: HTMLButtonElement;
  private optionsBtn!: HTMLButtonElement;
  private attachTabBtn!: HTMLButtonElement;
  private providerSelect!: HTMLSelectElement;
  private modelSelect!: HTMLSelectElement;
  private manageKeysBtn!: HTMLButtonElement;
  private deleteModal!: HTMLElement;
  private confirmDeleteCurrentBtn!: HTMLButtonElement;
  private confirmDeleteAllBtn!: HTMLButtonElement;
  private cancelDeleteBtn!: HTMLButtonElement;
  private messagesContainer!: HTMLElement;
  private emptyState!: HTMLElement;
  private toolActivity!: HTMLElement;
  private activityText!: HTMLElement;
  private promptInput!: HTMLTextAreaElement;
  private sendBtn!: HTMLButtonElement;

  private currentProvider = "google";
  private currentModel = "";

  private currentStreamingBubble: HTMLElement | null = null;
  private currentStreamingText = "";

  constructor() {
    this.client = new GhostBrowserClient();
  }

  public async init(): Promise<void> {
    this.bindDom();
    this.attachEvents();
    this.setupClientListeners();
    this.setupTabListeners();

    // Auto-detect and sync the current active tab
    await this.syncActiveTabContext();

    // Load settings and connect to Ghost Gateway
    await this.connectFromSettings();

    // Check for pending context-menu action
    await this.checkPendingAction();
  }

  private bindDom(): void {
    this.statusBadge = document.getElementById("statusBadge")!;
    this.statusDot = document.getElementById("statusDot")!;
    this.statusText = document.getElementById("statusText")!;
    this.sessionSelect = document.getElementById("sessionSelect") as HTMLSelectElement;
    this.newSessionBtn = document.getElementById("newSessionBtn") as HTMLButtonElement;
    this.deleteSessionBtn = document.getElementById("deleteSessionBtn") as HTMLButtonElement;
    this.optionsBtn = document.getElementById("optionsBtn") as HTMLButtonElement;
    this.attachTabBtn = document.getElementById("attachTabBtn") as HTMLButtonElement;
    this.providerSelect = document.getElementById("providerSelect") as HTMLSelectElement;
    this.modelSelect = document.getElementById("modelSelect") as HTMLSelectElement;
    this.manageKeysBtn = document.getElementById("manageKeysBtn") as HTMLButtonElement;
    this.deleteModal = document.getElementById("deleteModal")!;
    this.confirmDeleteCurrentBtn = document.getElementById("confirmDeleteCurrentBtn") as HTMLButtonElement;
    this.confirmDeleteAllBtn = document.getElementById("confirmDeleteAllBtn") as HTMLButtonElement;
    this.cancelDeleteBtn = document.getElementById("cancelDeleteBtn") as HTMLButtonElement;
    this.messagesContainer = document.getElementById("messagesContainer")!;
    this.emptyState = document.getElementById("emptyState")!;
    this.toolActivity = document.getElementById("toolActivity")!;
    this.activityText = document.getElementById("activityText")!;
    this.promptInput = document.getElementById("promptInput") as HTMLTextAreaElement;
    this.sendBtn = document.getElementById("sendBtn") as HTMLButtonElement;
  }

  private attachEvents(): void {
    // Reconnect on badge click
    this.statusBadge.addEventListener("click", () => {
      this.connectFromSettings();
    });

    // Session switch
    this.sessionSelect.addEventListener("change", async () => {
      const selected = this.sessionSelect.value;
      if (selected) {
        await this.loadSession(selected);
      } else {
        this.startNewSession();
      }
    });

    // New Session
    this.newSessionBtn.addEventListener("click", () => {
      this.startNewSession();
    });

    // Delete session modal
    this.deleteSessionBtn.addEventListener("click", () => {
      this.openDeleteModal();
    });

    this.confirmDeleteCurrentBtn.addEventListener("click", async () => {
      if (this.currentSessionId) {
        await this.client.deleteSession(this.currentSessionId);
        this.startNewSession();
        await this.refreshSessions();
      }
      this.closeDeleteModal();
    });

    this.confirmDeleteAllBtn.addEventListener("click", async () => {
      this.closeDeleteModal();
      if (confirm("Möchtest du wirklich ALLE gespeicherten Sitzungen unwiderruflich löschen?")) {
        await this.client.deleteAllSessions();
        this.startNewSession();
        await this.refreshSessions();
      }
    });

    this.cancelDeleteBtn.addEventListener("click", () => {
      this.closeDeleteModal();
    });

    // Provider / Model change
    this.providerSelect.addEventListener("change", async () => {
      this.currentProvider = this.providerSelect.value;
      await this.loadModelsForProvider(this.currentProvider);
      if (this.currentSessionId && this.currentModel) {
        await this.client.setSessionModel(this.currentSessionId, this.currentModel, this.currentProvider);
      }
    });

    this.modelSelect.addEventListener("change", async () => {
      this.currentModel = this.modelSelect.value;
      if (this.currentSessionId && this.currentModel) {
        await this.client.setSessionModel(this.currentSessionId, this.currentModel, this.currentProvider);
      }
    });

    this.manageKeysBtn.addEventListener("click", () => {
      chrome.runtime.openOptionsPage?.() || window.open(chrome.runtime.getURL("options/options.html"));
    });

    // Options
    this.optionsBtn.addEventListener("click", () => {
      chrome.runtime.openOptionsPage?.() || window.open(chrome.runtime.getURL("options/options.html"));
    });

    // Toggle active tab context button
    this.attachTabBtn.addEventListener("click", async () => {
      await this.toggleActiveTabContext();
    });

    // Prompt input auto-resize & key bindings
    this.promptInput.addEventListener("input", () => {
      this.promptInput.style.height = "auto";
      this.promptInput.style.height = `${Math.min(this.promptInput.scrollHeight, 120)}px`;
    });

    this.promptInput.addEventListener("keydown", (e: KeyboardEvent) => {
      if (e.key === "Enter" && !e.shiftKey) {
        e.preventDefault();
        this.handleSendOrStop();
      }
    });

    this.sendBtn.addEventListener("click", () => {
      this.handleSendOrStop();
    });

    // Quick suggestion buttons in empty state
    const suggestions = document.querySelectorAll(".suggestion-btn");
    suggestions.forEach((btn) => {
      btn.addEventListener("click", async () => {
        const prompt = btn.getAttribute("data-prompt") || "";
        this.promptInput.value = prompt;
        // Automatically sync active tab context for page analysis
        this.autoSyncTab = true;
        await this.syncActiveTabContext();
        this.promptInput.focus();
        this.promptInput.dispatchEvent(new Event("input"));
      });
    });

    // Listen to background runtime messages
    chrome.runtime.onMessage.addListener((message) => {
      if (message.type === "GHOST_PENDING_ACTION" && message.payload) {
        this.handleActionPayload(message.payload);
      }
    });
  }

  private setupTabListeners(): void {
    try {
      chrome.tabs.onActivated?.addListener?.(async () => {
        if (this.autoSyncTab) {
          await this.syncActiveTabContext();
        }
      });

      chrome.tabs.onUpdated?.addListener?.(async (_tabId, changeInfo) => {
        if (changeInfo.status === "complete" && this.autoSyncTab) {
          await this.syncActiveTabContext();
        }
      });
    } catch (e) {
      console.warn("[Ghost] Could not attach tabs listeners:", e);
    }
  }

  private setupClientListeners(): void {
    this.client.on("stateChange", (state: ConnectionState, message?: string) => {
      this.updateStatusUI(state, message);
    });

    this.client.on("stream", ({ chunk }: { chunk: string }) => {
      this.appendStreamChunk(chunk);
    });

    this.client.on("activity", ({ activity }: { activity: string }) => {
      this.showActivity(activity);
    });

    this.client.on("response", (payload?: any) => {
      const msg = payload?.message;
      if (msg && msg.role === "assistant" && msg.content) {
        if (!this.currentStreamingText.trim()) {
          if (this.currentStreamingBubble) {
            this.renderMarkdown(this.currentStreamingBubble, msg.content);
          } else {
            this.appendMessage(msg);
          }
        }
      }
      this.finalizeStreaming();
      this.refreshSessions();
    });

    this.client.on("error", ({ error }: { error: string }) => {
      this.finalizeStreaming();
      this.appendMessage({
        role: "assistant",
        content: `❌ **Fehler**: ${error}`,
      });
    });

    this.client.on("sessionDeleted", (payload: any) => {
      if (payload?.sessionId === this.currentSessionId) {
        this.startNewSession();
      }
      this.refreshSessions();
    });

    this.client.on("sessionsCleared", () => {
      this.startNewSession();
      this.refreshSessions();
    });
  }

  private async connectFromSettings(): Promise<void> {
    const config = await chrome.storage.local.get({
      gatewayUrl: "ws://localhost:3000",
      authToken: "",
    });

    this.updateStatusUI("connecting");
    await this.client.connect(config.gatewayUrl, config.authToken);

    if (this.client.getState() === "connected") {
      await this.refreshSessions();
      await this.loadConfigAndModels();
    }
  }

  private updateStatusUI(state: ConnectionState, detail?: string): void {
    this.statusDot.className = `status-dot ${state}`;
    switch (state) {
      case "connected":
        this.statusText.textContent = "Verbunden";
        this.statusBadge.title = `Verbunden mit ${this.client.getUrl()}`;
        break;
      case "connecting":
        this.statusText.textContent = "Verbindet...";
        this.statusBadge.title = "Verbindung wird aufgebaut...";
        break;
      case "error":
        this.statusText.textContent = "Fehler";
        this.statusBadge.title = detail || "Verbindungsfehler. Klicke zum erneuten Versuch.";
        break;
      case "disconnected":
      default:
        this.statusText.textContent = "Getrennt";
        this.statusBadge.title = "Getrennt vom Gateway. Klicke zum Verbinden.";
        break;
    }
  }

  private async refreshSessions(): Promise<void> {
    try {
      const sessions = await this.client.getSessions();
      this.sessionSelect.innerHTML = `<option value="">(Neue Sitzung)</option>`;

      for (const s of sessions) {
        const opt = document.createElement("option");
        opt.value = s.id;
        opt.textContent = s.title || `Chat ${s.id.substring(0, 8)}`;
        if (s.id === this.currentSessionId) {
          opt.selected = true;
        }
        this.sessionSelect.appendChild(opt);
      }
    } catch {
      // Ignore if session fetch fails temporarily
    }
  }

  private startNewSession(): void {
    this.currentSessionId = null;
    this.sessionSelect.value = "";
    this.clearMessagesUI();
    this.promptInput.focus();
  }

  private async loadSession(sessionId: string): Promise<void> {
    this.currentSessionId = sessionId;
    this.clearMessagesUI();

    try {
      const history = await this.client.getHistory(sessionId);
      if (history.length > 0) {
        this.emptyState.style.display = "none";
        for (const msg of history) {
          this.appendMessage(msg);
        }
      }
    } catch (e: any) {
      this.appendMessage({
        role: "assistant",
        content: `Konnte Verlauf nicht laden: ${e.message}`,
      });
    }
  }

  /**
   * Safe helper to find the active browser tab.
   */
  private async getActiveTab(): Promise<chrome.tabs.Tab | null> {
    try {
      const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
      if (tabs.length > 0 && tabs[0].id) return tabs[0];
    } catch {}
    try {
      const tabs = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
      if (tabs.length > 0 && tabs[0].id) return tabs[0];
    } catch {}
    return null;
  }

  /**
   * Safely extract page context from a tab.
   */
  private async getPageContext(tab: chrome.tabs.Tab): Promise<PageContext> {
    if (!tab.url || tab.url.startsWith("chrome://") || tab.url.startsWith("chrome-extension://") || tab.url.startsWith("edge://")) {
      return {
        url: tab.url || "",
        title: tab.title || "Browser-Seite",
      };
    }

    if (tab.id) {
      // 1. Try content script message
      try {
        const res = await chrome.tabs.sendMessage(tab.id, { type: "GHOST_GET_PAGE_CONTEXT" });
        if (res && res.context) {
          return res.context;
        }
      } catch {}

      // 2. Try dynamic execution fallback
      try {
        const results = await chrome.scripting.executeScript({
          target: { tabId: tab.id },
          func: extractPageContext,
        });
        if (results && results[0]?.result) {
          return results[0].result;
        }
      } catch (err) {
        console.warn("[Ghost] Could not executeScript on tab:", err);
      }
    }

    return {
      url: tab.url || "",
      title: tab.title || "",
    };
  }

  /**
   * Automatically detect and attach context from the active tab.
   */
  private async syncActiveTabContext(): Promise<void> {
    const tab = await this.getActiveTab();
    if (!tab || !tab.url || tab.url.startsWith("chrome://") || tab.url.startsWith("chrome-extension://")) {
      this.attachedContext = null;
      this.updateTabContextUI();
      return;
    }

    const ctx = await this.getPageContext(tab);
    this.attachedContext = ctx;
    this.updateTabContextUI();
  }

  private updateTabContextUI(): void {
    if (this.attachedContext && this.attachedContext.url && !this.attachedContext.url.startsWith("chrome://")) {
      this.attachTabBtn.classList.add("active");
      const shortTitle = (this.attachedContext.title || this.attachedContext.url).substring(0, 22);
      this.attachTabBtn.innerHTML = `<span>🌐 ${shortTitle}</span> <span style="opacity:0.7;margin-left:4px;">✕</span>`;
      this.attachTabBtn.title = `Kontext aktiv: ${this.attachedContext.title} (${this.attachedContext.url}). Klicke zum Entfernen.`;
    } else {
      this.attachTabBtn.classList.remove("active");
      this.attachTabBtn.innerHTML = `<span>🌐 Aktiven Tab anhängen</span>`;
      this.attachTabBtn.title = "Aktiven Tab als Kontext für Prompts anhängen";
    }
  }

  private async toggleActiveTabContext(): Promise<void> {
    if (this.attachedContext) {
      // User clicked to detach
      this.attachedContext = null;
      this.autoSyncTab = false; // pause auto-sync until clicked again
      this.updateTabContextUI();
      return;
    }

    // User clicked to attach
    this.autoSyncTab = true;
    await this.syncActiveTabContext();
  }

  private async handleSendOrStop(): Promise<void> {
    if (this.isStreaming) {
      if (this.currentSessionId) {
        await this.client.stop(this.currentSessionId);
      }
      this.finalizeStreaming();
      return;
    }

    const text = this.promptInput.value.trim();
    if (!text) return;

    this.emptyState.style.display = "none";
    this.promptInput.value = "";
    this.promptInput.style.height = "auto";

    // If auto-sync is active, refresh the active tab context right before sending
    if (this.autoSyncTab) {
      await this.syncActiveTabContext();
    }

    let fullPrompt = text;
    if (this.attachedContext && this.attachedContext.url && !this.attachedContext.url.startsWith("chrome://")) {
      let contextHeader = `[Web-Kontext: ${this.attachedContext.title} (${this.attachedContext.url})]\n`;
      if (this.attachedContext.selectedText) {
        contextHeader += `Markierter Text auf der Seite:\n"""\n${this.attachedContext.selectedText}\n"""\n\n`;
      } else if (this.attachedContext.pageContentSnippet) {
        contextHeader += `Inhalt / Seitenausschnitt:\n"""\n${this.attachedContext.pageContentSnippet}\n"""\n\n`;
      }
      fullPrompt = contextHeader + text;
    }

    // Render user message in UI
    this.appendMessage({
      role: "user",
      content: text,
    });

    // Start streaming UI
    this.isStreaming = true;
    this.sendBtn.textContent = "⏹";
    this.sendBtn.classList.add("stop");
    this.sendBtn.title = "Generierung anhalten";
    this.showActivity("Ghost denkt nach...");

    this.currentStreamingText = "";
    this.currentStreamingBubble = this.createMessageBubble("assistant", "");

    try {
      const res = await this.client.chat(fullPrompt, {
        sessionId: this.currentSessionId || undefined,
        provider: this.currentProvider || undefined,
        model: this.currentModel || undefined,
      });

      if (!this.currentSessionId && res.sessionId) {
        this.currentSessionId = res.sessionId;
      }
    } catch (err: any) {
      this.finalizeStreaming();
      this.appendMessage({
        role: "assistant",
        content: `❌ Verbindungsfehler: ${err.message}`,
      });
    }
  }

  private appendStreamChunk(chunk: string): void {
    if (!this.currentStreamingBubble) {
      this.currentStreamingBubble = this.createMessageBubble("assistant", "");
    }
    this.currentStreamingText += chunk;
    this.renderMarkdown(this.currentStreamingBubble, this.currentStreamingText);
    this.scrollToBottom();
  }

  private showActivity(activity: string): void {
    if (!activity) {
      this.toolActivity.style.display = "none";
      return;
    }
    this.toolActivity.style.display = "flex";
    this.activityText.textContent = activity;
    this.scrollToBottom();
  }

  private finalizeStreaming(): void {
    this.isStreaming = false;
    this.sendBtn.textContent = "➤";
    this.sendBtn.classList.remove("stop");
    this.sendBtn.title = "Senden";
    this.toolActivity.style.display = "none";

    // Clean up empty bubble if no text was streamed
    if (this.currentStreamingBubble) {
      if (!this.currentStreamingText.trim()) {
        this.currentStreamingBubble.remove();
      }
    }
    this.currentStreamingBubble = null;
    this.currentStreamingText = "";
  }

  private clearMessagesUI(): void {
    this.messagesContainer.innerHTML = "";
    this.messagesContainer.appendChild(this.emptyState);
    this.emptyState.style.display = "flex";
  }

  private appendMessage(msg: Message): void {
    this.emptyState.style.display = "none";
    const bubble = this.createMessageBubble(msg.role, msg.content);
    this.renderMarkdown(bubble, msg.content);
    this.scrollToBottom();
  }

  private createMessageBubble(role: string, initialContent: string): HTMLElement {
    const bubble = document.createElement("div");
    bubble.className = `message ${role}`;
    this.renderMarkdown(bubble, initialContent);
    this.messagesContainer.appendChild(bubble);
    return bubble;
  }

  private scrollToBottom(): void {
    this.messagesContainer.scrollTop = this.messagesContainer.scrollHeight;
  }

  /**
   * Lightweight Markdown formatter for streaming text.
   */
  private renderMarkdown(el: HTMLElement, raw: string): void {
    let html = raw
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");

    // Code blocks ```lang\ncode\n```
    html = html.replace(/```([a-zA-Z0-9_-]*)\n([\s\S]*?)```/g, (_match, _lang, code) => {
      return `
        <pre>
          <div class="code-header">
            <button class="copy-btn">Kopieren</button>
          </div>
          <code>${code}</code>
        </pre>
      `;
    });

    // Inline code `code`
    html = html.replace(/`([^`]+)`/g, "<code>$1</code>");

    // Bold **text**
    html = html.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");

    // Italic *text*
    html = html.replace(/\*([^*]+)\*/g, "<em>$1</em>");

    // Line breaks
    html = html.replace(/\n/g, "<br>");

    el.innerHTML = html;

    // Attach copy button handlers
    const copyButtons = el.querySelectorAll(".copy-btn");
    copyButtons.forEach((btn) => {
      btn.addEventListener("click", () => {
        const pre = btn.closest("pre");
        const code = pre?.querySelector("code")?.innerText || "";
        navigator.clipboard.writeText(code);
        btn.textContent = "Kopiert! ✓";
        setTimeout(() => (btn.textContent = "Kopieren"), 2000);
      });
    });
  }

  private async checkPendingAction(): Promise<void> {
    const data = await chrome.storage.session.get("pendingAction");
    if (data.pendingAction) {
      await chrome.storage.session.remove("pendingAction");
      this.handleActionPayload(data.pendingAction);
    }
  }

  private handleActionPayload(payload: {
    action: string;
    selectedText: string;
    pageUrl: string;
    pageTitle: string;
  }): void {
    const { action, selectedText, pageUrl, pageTitle } = payload;

    switch (action) {
      case "ghost-explain":
        this.attachedContext = { url: pageUrl, title: pageTitle, selectedText };
        this.updateTabContextUI();
        this.promptInput.value = `Erkläre bitte folgenden Code / Text aus ${pageTitle}:\n\n"""\n${selectedText}\n"""`;
        break;
      case "ghost-summarize":
        this.attachedContext = { url: pageUrl, title: pageTitle, selectedText };
        this.updateTabContextUI();
        this.promptInput.value = `Fasse bitte folgenden Inhalt prägnant zusammen:\n\n"""\n${selectedText}\n"""`;
        break;
      case "ghost-create-task":
        this.attachedContext = { url: pageUrl, title: pageTitle, selectedText };
        this.updateTabContextUI();
        this.promptInput.value = `/plan ${selectedText.substring(0, 100)}`;
        break;
      case "ghost-page-qa":
        this.attachedContext = { url: pageUrl, title: pageTitle };
        this.updateTabContextUI();
        this.promptInput.value = `Analysiere bitte diese Seite (${pageTitle}) und gib eine prägnante Übersicht der Hauptpunkte.`;
        break;
    }

    this.promptInput.focus();
    this.promptInput.dispatchEvent(new Event("input"));
  }

  private openDeleteModal(): void {
    if (!this.currentSessionId) {
      this.confirmDeleteCurrentBtn.style.display = "none";
    } else {
      this.confirmDeleteCurrentBtn.style.display = "block";
    }
    this.deleteModal.style.display = "flex";
  }

  private closeDeleteModal(): void {
    this.deleteModal.style.display = "none";
  }

  private async loadConfigAndModels(): Promise<void> {
    try {
      const config = await this.client.getConfig();
      if (config && config.agent) {
        if (config.agent.provider) {
          this.currentProvider = config.agent.provider;
          this.providerSelect.value = this.currentProvider;
        }
        if (config.agent.model) {
          this.currentModel = config.agent.model;
        }
      }
      await this.loadModelsForProvider(this.currentProvider);
    } catch (e) {
      console.warn("[Ghost] Could not load gateway config:", e);
      await this.loadModelsForProvider(this.currentProvider);
    }
  }

  private async loadModelsForProvider(provider: string): Promise<void> {
    try {
      this.modelSelect.innerHTML = `<option value="">(Lade Modelle...)</option>`;
      const models = await this.client.listModels(provider);
      this.modelSelect.innerHTML = "";
      if (models && models.length > 0) {
        for (const m of models) {
          const opt = document.createElement("option");
          opt.value = m;
          opt.textContent = m;
          if (m === this.currentModel) {
            opt.selected = true;
          }
          this.modelSelect.appendChild(opt);
        }
        if (!this.modelSelect.value && models.length > 0) {
          this.modelSelect.value = models[0];
          this.currentModel = models[0];
        } else {
          this.currentModel = this.modelSelect.value;
        }
      } else {
        const opt = document.createElement("option");
        opt.value = this.currentModel || provider;
        opt.textContent = this.currentModel || `Standard (${provider})`;
        opt.selected = true;
        this.modelSelect.appendChild(opt);
      }
    } catch {
      this.modelSelect.innerHTML = `<option value="${this.currentModel || ''}">${this.currentModel || 'Standard'}</option>`;
    }
  }
}

// Bootstrap on DOM load
document.addEventListener("DOMContentLoaded", () => {
  const app = new GhostSidePanel();
  app.init().catch(console.error);
});
