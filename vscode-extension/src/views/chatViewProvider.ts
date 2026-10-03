import * as vscode from "vscode";
import { GhostGatewayClient } from "../gateway/client";
import { Message } from "../gateway/protocol";
import chatViewHtml from "./chatView.html";

export class GhostChatViewProvider implements vscode.WebviewViewProvider {
  public static readonly viewType = "ghost.chatView";
  private _view?: vscode.WebviewView;
  private currentSessionId: string | null = null;
  private isGenerating = false;
  private streamingContent = "";
  private currentProvider = "google";
  private currentModel = "";

  public get generating(): boolean {
    return this.isGenerating;
  }

  public getProvider(): string {
    return this.currentProvider;
  }

  public getModel(): string {
    return this.currentModel;
  }

  constructor(
    private readonly _extensionUri: vscode.Uri,
    private readonly client: GhostGatewayClient
  ) {
    this.registerClientListeners();
  }

  public resolveWebviewView(
    webviewView: vscode.WebviewView,
    _context: vscode.WebviewViewResolveContext,
    _token: vscode.CancellationToken
  ) {
    this._view = webviewView;

    webviewView.webview.options = {
      enableScripts: true,
      localResourceRoots: [this._extensionUri],
    };

    webviewView.webview.html = this.getHtmlForWebview(webviewView.webview);

    webviewView.webview.onDidReceiveMessage(async (data) => {
      switch (data.type) {
        case "ready":
          await this.syncFullState();
          break;
        case "sendMessage":
          await this.handleUserMessage(data.text);
          break;
        case "stop":
          if (this.currentSessionId) {
            await this.client.stop(this.currentSessionId);
            this.isGenerating = false;
            this.postMessage({ type: "generationStopped" });
          }
          break;
        case "newSession":
          await this.startNewSession();
          break;
        case "deleteCurrentSession":
          await this.deleteCurrentSession();
          break;
        case "deleteAllSessions":
          await this.deleteAllSessions();
          break;
        case "changeProvider":
          await this.handleProviderChange(data.provider);
          break;
        case "changeModel":
          await this.handleModelChange(data.provider, data.model);
          break;
        case "manageApiKeys":
          vscode.commands.executeCommand("ghost.manageApiKeys");
          break;
        case "switchSession":
          await this.loadSession(data.sessionId);
          break;
        case "insertCode":
          this.insertCodeIntoActiveEditor(data.code);
          break;
        case "copyCode":
          vscode.env.clipboard.writeText(data.code);
          vscode.window.showInformationMessage("Code in die Zwischenablage kopiert.");
          break;
        case "connect":
          vscode.commands.executeCommand("ghost.connect");
          break;
      }
    });

    // Send active editor context on change
    vscode.window.onDidChangeActiveTextEditor(() => {
      this.sendEditorContext();
    });
    vscode.window.onDidChangeTextEditorSelection(() => {
      this.sendEditorContext();
    });
  }

  private registerClientListeners() {
    this.client.on("stateChange", (state: string) => {
      this.postMessage({ type: "connectionState", state });
      if (state === "connected") {
        this.refreshSessions();
      }
    });

    this.client.on("stream", (payload: { sessionId: string; chunk: string }) => {
      if (this.currentSessionId && payload.sessionId === this.currentSessionId) {
        this.streamingContent += payload.chunk;
        this.postMessage({
          type: "streamChunk",
          sessionId: payload.sessionId,
          chunk: payload.chunk,
          fullStream: this.streamingContent,
        });
      }
    });

    this.client.on("activity", (payload: { sessionId: string; activity: string }) => {
      if (this.currentSessionId && payload.sessionId === this.currentSessionId) {
        this.postMessage({
          type: "activity",
          sessionId: payload.sessionId,
          activity: payload.activity,
        });
      }
    });

    this.client.on("response", (payload: { sessionId: string; message: Message }) => {
      if (this.currentSessionId && payload.sessionId === this.currentSessionId) {
        this.isGenerating = false;
        this.streamingContent = "";
        this.postMessage({
          type: "responseComplete",
          sessionId: payload.sessionId,
          message: payload.message,
        });
        this.refreshSessions();
      }
    });

    this.client.on("error", (payload: { sessionId: string; error: string }) => {
      if (this.currentSessionId && payload.sessionId === this.currentSessionId) {
        this.isGenerating = false;
        this.streamingContent = "";
        this.postMessage({
          type: "error",
          sessionId: payload.sessionId,
          error: payload.error,
        });
      }
    });

    this.client.on("sessionUpdated", (payload: { sessionId: string; title?: string }) => {
      this.postMessage({
        type: "sessionUpdated",
        sessionId: payload.sessionId,
        title: payload.title,
      });
      this.refreshSessions();
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

  public async startNewSession() {
    this.currentSessionId = `vscode-${Date.now()}`;
    this.streamingContent = "";
    this.isGenerating = false;
    this.postMessage({
      type: "sessionSwitched",
      sessionId: this.currentSessionId,
      messages: [],
    });
    await this.refreshSessions();
  }

  public async loadSession(sessionId: string) {
    this.currentSessionId = sessionId;
    this.streamingContent = "";
    this.isGenerating = false;
    try {
      const messages = await this.client.getHistory(sessionId, 50);
      this.postMessage({
        type: "sessionSwitched",
        sessionId,
        messages,
      });
    } catch (e: any) {
      vscode.window.showErrorMessage(`Konnte Sitzung nicht laden: ${e.message}`);
    }
  }

  public async refreshSessions() {
    try {
      const sessions = await this.client.getSessions();
      this.postMessage({
        type: "sessionsList",
        sessions,
        currentSessionId: this.currentSessionId,
      });
    } catch {}
  }

  public async sendPromptWithActiveContext(prefixPrompt: string, codeSnippet?: string) {
    const editor = vscode.window.activeTextEditor;
    let fullPrompt = prefixPrompt;

    if (editor && codeSnippet) {
      const doc = editor.document;
      const fileName = doc.fileName.split(/[\\/]/).pop() || doc.fileName;
      const lang = doc.languageId;
      fullPrompt += `\n\nDatei: \`${fileName}\` (${lang})\n\`\`\`${lang}\n${codeSnippet}\n\`\`\``;
    }

    if (this._view) {
      this._view.show?.(true);
      await this.handleUserMessage(fullPrompt);
    }
  }

  public async handleUserMessage(text: string) {
    if (!text || !text.trim()) return;

    if (this.client.getState() !== "connected") {
      vscode.window.showWarningMessage("Ghost ist nicht verbunden. Bitte verbinden Sie sich zuerst.");
      return;
    }

    if (!this.currentSessionId) {
      this.currentSessionId = `vscode-${Date.now()}`;
    }

    this.isGenerating = true;
    this.streamingContent = "";

    // Show user message in Webview
    this.postMessage({
      type: "userMessageAdded",
      sessionId: this.currentSessionId,
      text,
    });

    const wsFolders = vscode.workspace.workspaceFolders;
    const activeWorkspaceDir = wsFolders && wsFolders.length > 0 ? wsFolders[0].uri.fsPath : undefined;

    try {
      await this.client.chat(text, {
        sessionId: this.currentSessionId,
        workspaceDir: activeWorkspaceDir,
        provider: this.currentProvider || undefined,
        model: this.currentModel || undefined,
      });
    } catch (e: any) {
      this.isGenerating = false;
      this.postMessage({
        type: "error",
        sessionId: this.currentSessionId,
        error: e.message || String(e),
      });
    }
  }

  private async syncFullState() {
    this.postMessage({
      type: "connectionState",
      state: this.client.getState(),
      url: this.client.getUrl(),
    });

    if (this.client.getState() === "connected") {
      const sessions = await this.client.getSessions().catch(() => []);
      if (!this.currentSessionId && sessions.length > 0) {
        this.currentSessionId = sessions[0].id;
        const messages = await this.client.getHistory(this.currentSessionId).catch(() => []);
        this.postMessage({
          type: "sessionSwitched",
          sessionId: this.currentSessionId,
          messages,
        });
      } else if (!this.currentSessionId) {
        await this.startNewSession();
      }
      this.postMessage({
        type: "sessionsList",
        sessions,
        currentSessionId: this.currentSessionId,
      });
      await this.syncModelConfig();
    }

    this.sendEditorContext();
  }

  public async deleteCurrentSession() {
    if (this.currentSessionId) {
      await this.client.deleteSession(this.currentSessionId);
      await this.startNewSession();
      await this.refreshSessions();
      vscode.window.showInformationMessage("Sitzung gelöscht.");
    }
  }

  public async deleteAllSessions() {
    await this.client.deleteAllSessions();
    await this.startNewSession();
    await this.refreshSessions();
    vscode.window.showInformationMessage("Alle Sitzungen wurden gelöscht.");
  }

  public async syncModelConfig() {
    try {
      const config = await this.client.getConfig();
      if (config && config.agent) {
        if (config.agent.provider) this.currentProvider = config.agent.provider;
        if (config.agent.model) this.currentModel = config.agent.model;
      }
      const models = await this.client.listModels(this.currentProvider);
      this.postMessage({
        type: "modelConfig",
        provider: this.currentProvider,
        model: this.currentModel,
        models,
      });
    } catch {}
  }

  public async handleProviderChange(provider: string) {
    this.currentProvider = provider;
    try {
      const models = await this.client.listModels(provider);
      this.currentModel = models && models.length > 0 ? models[0] : "";
      this.postMessage({
        type: "modelConfig",
        provider: this.currentProvider,
        model: this.currentModel,
        models,
      });
      if (this.currentSessionId && this.currentModel) {
        await this.client.setSessionModel(this.currentSessionId, this.currentModel, this.currentProvider);
      }
    } catch {}
  }

  public async handleModelChange(provider: string, model: string) {
    this.currentProvider = provider;
    this.currentModel = model;
    if (this.currentSessionId && this.currentModel) {
      await this.client.setSessionModel(this.currentSessionId, this.currentModel, this.currentProvider);
    }
  }

  private sendEditorContext() {
    const editor = vscode.window.activeTextEditor;
    const wsFolders = vscode.workspace.workspaceFolders;
    const wsName = wsFolders && wsFolders.length > 0 ? wsFolders[0].name : null;
    const wsPath = wsFolders && wsFolders.length > 0 ? wsFolders[0].uri.fsPath : null;

    if (!editor) {
      this.postMessage({
        type: "editorContext",
        context: wsName ? { workspaceName: wsName, workspacePath: wsPath } : null,
      });
      return;
    }

    const doc = editor.document;
    const fileName = doc.fileName.split(/[\\/]/).pop() || doc.fileName;
    const selection = editor.selection;
    const hasSelection = !selection.isEmpty;
    const selectedText = hasSelection ? doc.getText(selection) : "";

    this.postMessage({
      type: "editorContext",
      context: {
        workspaceName: wsName,
        workspacePath: wsPath,
        fileName,
        language: doc.languageId,
        line: selection.active.line + 1,
        hasSelection,
        selectionLength: selectedText.length,
      },
    });
  }

  private insertCodeIntoActiveEditor(code: string) {
    const editor = vscode.window.activeTextEditor;
    if (!editor) {
      vscode.window.showWarningMessage("Kein aktiver Editor geöffnet.");
      return;
    }

    editor.edit((editBuilder) => {
      if (editor.selection.isEmpty) {
        editBuilder.insert(editor.selection.active, code);
      } else {
        editBuilder.replace(editor.selection, code);
      }
    });
  }

  private postMessage(message: any) {
    this._view?.webview.postMessage(message);
  }

  private getHtmlForWebview(_webview: vscode.Webview): string {
    return chatViewHtml;
  }
}
