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
