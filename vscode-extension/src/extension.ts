import * as vscode from "vscode";
import { GhostGatewayClient } from "./gateway/client";
import { GhostStatusBar } from "./ui/statusBar";
import { GhostChatViewProvider } from "./views/chatViewProvider";
import { registerEditorCommands } from "./commands/editorCommands";

let client: GhostGatewayClient | null = null;
let statusBar: GhostStatusBar | null = null;

export async function activate(context: vscode.ExtensionContext) {
  console.log("Activating Ghost AI Assistant extension...");

  // 1. Initialize Gateway Client
  client = new GhostGatewayClient();

  // 2. Initialize Status Bar
  statusBar = new GhostStatusBar(client);
  context.subscriptions.push(statusBar);

  // 3. Initialize Sidebar Webview Provider
  const chatProvider = new GhostChatViewProvider(context.extensionUri, client);
  context.subscriptions.push(
    vscode.window.registerWebviewViewProvider(
      GhostChatViewProvider.viewType,
      chatProvider,
      {
        webviewOptions: {
          retainContextWhenHidden: true,
        },
      }
    )
  );

  // 4. Register Editor Context Commands
  registerEditorCommands(context, chatProvider);

  // 5. Register Base Commands
  context.subscriptions.push(
    vscode.commands.registerCommand("ghost.connect", async () => {
      const config = vscode.workspace.getConfiguration("ghost");
      const url = config.get<string>("gatewayUrl") || "ws://localhost:3000";
      const token = config.get<string>("authToken") || "";

      vscode.window.withProgress(
        {
          location: vscode.ProgressLocation.Notification,
          title: `Verbinde mit Ghost Gateway (${url})...`,
          cancellable: false,
        },
        async () => {
          const success = await client!.connect(url, token);
          if (success) {
            vscode.window.showInformationMessage(`✅ Erfolgreich mit Ghost Gateway verbunden!`);
          } else {
            vscode.window
              .showErrorMessage(
                `Konnte nicht mit Ghost Gateway (${url}) verbinden. Läuft die Ghost-App?`,
                "Einstellungen öffnen",
                "Wiederholen"
              )
              .then((choice) => {
                if (choice === "Einstellungen öffnen") {
                  vscode.commands.executeCommand("workbench.action.openSettings", "ghost");
                } else if (choice === "Wiederholen") {
                  vscode.commands.executeCommand("ghost.connect");
                }
              });
          }
        }
      );
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand("ghost.disconnect", () => {
      client?.disconnect();
      vscode.window.showInformationMessage("Verbindung zu Ghost getrennt.");
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand("ghost.openChat", () => {
      vscode.commands.executeCommand("ghost.chatView.focus");
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand("ghost.newSession", async () => {
      await chatProvider.startNewSession();
      vscode.commands.executeCommand("ghost.chatView.focus");
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand("ghost.statusBarClick", () => {
      statusBar?.showQuickPick();
    })
  );

  const SUPPORTED_PROVIDERS = [
    { id: "google", name: "Google Gemini", isLocal: false },
    { id: "anthropic", name: "Anthropic Claude", isLocal: false },
    { id: "openai", name: "OpenAI", isLocal: false },
    { id: "deepseek", name: "DeepSeek", isLocal: false },
    { id: "mistral", name: "Mistral AI", isLocal: false },
    { id: "groq", name: "Groq", isLocal: false },
    { id: "openrouter", name: "OpenRouter", isLocal: false },
    { id: "xai", name: "xAI (Grok)", isLocal: false },
    { id: "perplexity", name: "Perplexity", isLocal: false },
    { id: "ollama", name: "Ollama (Lokal)", isLocal: true, defaultUrl: "http://localhost:11434/v1" },
    { id: "lmstudio", name: "LM Studio (Lokal)", isLocal: true, defaultUrl: "http://localhost:1234/v1" },
    { id: "vllm", name: "vLLM (Lokal)", isLocal: true, defaultUrl: "http://localhost:8000/v1" },
  ];

  context.subscriptions.push(
    vscode.commands.registerCommand("ghost.deleteCurrentSession", async () => {
      const confirm = await vscode.window.showWarningMessage(
        "Möchtest du die aktuelle Sitzung wirklich löschen?",
        { modal: true },
        "Löschen"
      );
      if (confirm === "Löschen") {
        await chatProvider.deleteCurrentSession();
      }
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand("ghost.deleteAllSessions", async () => {
      const confirm = await vscode.window.showWarningMessage(
        "Möchtest du wirklich ALLE gespeicherten Sitzungen unwiderruflich löschen?",
        { modal: true },
        "Alle löschen"
      );
      if (confirm === "Alle löschen") {
        await chatProvider.deleteAllSessions();
      }
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand("ghost.changeModel", async () => {
      if (client?.getState() !== "connected") {
        vscode.window.showWarningMessage("Ghost ist nicht verbunden. Bitte zuerst verbinden.");
        return;
      }

      const providerItems = SUPPORTED_PROVIDERS.map((p) => ({
        label: p.name,
        description: p.id,
        provider: p,
      }));

      const selectedProvider = await vscode.window.showQuickPick(providerItems, {
        placeHolder: "Wähle den AI-Provider:",
      });
      if (!selectedProvider) return;

      const providerId = selectedProvider.provider.id;
      let models: string[] = [];
      try {
        models = await client.listModels(providerId);
      } catch (err: any) {
        vscode.window.showErrorMessage(`Fehler beim Abrufen der Modelle für ${selectedProvider.label}: ${err.message}`);
        return;
      }

      if (!models || models.length === 0) {
        vscode.window.showInformationMessage(`Keine Modelle für ${selectedProvider.label} gefunden. Bitte API-Key / Base-URL prüfen.`);
        return;
      }

      const selectedModel = await vscode.window.showQuickPick(
        models.map((m) => ({ label: m })),
        { placeHolder: `Wähle das Modell für ${selectedProvider.label}:` }
      );
      if (!selectedModel) return;

      const scope = await vscode.window.showQuickPick(
        [
          { label: "Für aktuelle Sitzung & Standard setzen", detail: "both" },
          { label: "Nur für aktuelle Sitzung", detail: "session" },
          { label: "Nur als Standard für neue Sitzungen", detail: "global" },
        ],
        { placeHolder: "Gültigkeitsbereich für den Modellwechsel:" }
      );
      if (!scope) return;

      if (scope.detail === "session" || scope.detail === "both") {
        await chatProvider.handleModelChange(providerId, selectedModel.label);
      }
      if (scope.detail === "global" || scope.detail === "both") {
        await client.setModel(selectedModel.label, providerId);
      }

      statusBar?.update();
      vscode.window.showInformationMessage(`✅ Modell auf ${providerId} / ${selectedModel.label} gesetzt!`);
    })
  );

  context.subscriptions.push(
    vscode.commands.registerCommand("ghost.manageApiKeys", async () => {
      if (client?.getState() !== "connected") {
        vscode.window.showWarningMessage("Ghost ist nicht verbunden. Bitte zuerst verbinden.");
        return;
      }

      let vaultKeys: string[] = [];
      try {
        const cfg = await client.getConfig();
        vaultKeys = (cfg?.vault?.keys as string[]) || [];
      } catch {}

      const providerItems = SUPPORTED_PROVIDERS.map((p) => {
        const isConfigured = vaultKeys.some((k) => k.startsWith(p.id));
        return {
          label: p.isLocal ? `$(server) ${p.name}` : `$(key) ${p.name}`,
          description: isConfigured ? "✅ Konfiguriert" : "⚪ Nicht hinterlegt",
          provider: p,
        };
      });

      const chosen = await vscode.window.showQuickPick(providerItems, {
        placeHolder: "Wähle einen Provider zur Verwaltung des API-Keys / der Base-URL:",
      });
      if (!chosen) return;

      const p = chosen.provider;
      let existingVal = "";
      try {
        existingVal = await client.getKey(p.id);
      } catch {}

      const input = await vscode.window.showInputBox({
        title: `${p.name} konfigurieren`,
        prompt: p.isLocal
          ? `Gib die Base-URL für ${p.name} ein (z. B. ${p.defaultUrl}):`
          : `Gib den API-Key für ${p.name} ein (leer lassen zum Löschen):`,
        value: existingVal,
        password: !p.isLocal,
      });

      if (input === undefined) return;

      try {
        await client.setKey(p.id, input.trim());
        vscode.window.showInformationMessage(
          input.trim()
            ? `✅ Konfiguration für ${p.name} erfolgreich gespeichert!`
            : `Schlüssel für ${p.name} entfernt.`
        );
      } catch (err: any) {
        vscode.window.showErrorMessage(`Fehler beim Speichern für ${p.name}: ${err.message}`);
      }
    })
  );

  // 6. Handle Configuration Changes
  context.subscriptions.push(
    vscode.workspace.onDidChangeConfiguration(async (e) => {
      if (e.affectsConfiguration("ghost.gatewayUrl") || e.affectsConfiguration("ghost.authToken")) {
        const config = vscode.workspace.getConfiguration("ghost");
        const url = config.get<string>("gatewayUrl") || "ws://localhost:3000";
        const token = config.get<string>("authToken") || "";
        if (client?.getState() === "connected") {
          await client.connect(url, token);
        }
      }
    })
  );

  // 7. Auto-connect if enabled
  const config = vscode.workspace.getConfiguration("ghost");
  if (config.get<boolean>("autoConnect", true)) {
    const url = config.get<string>("gatewayUrl") || "ws://localhost:3000";
    const token = config.get<string>("authToken") || "";
    // Background connect
    client.connect(url, token).catch(() => {});
  }
}

export function deactivate() {
  if (client) {
    client.disconnect();
    client = null;
  }
}
