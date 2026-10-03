import * as vscode from "vscode";
import { GhostGatewayClient } from "../gateway/client";

/**
 * Handles bidirectional state synchronization between VS Code / Antigravity IDE and Ghost.
 */
export class AntigravitySync implements vscode.Disposable {
  private disposables: vscode.Disposable[] = [];

  constructor(private readonly client: GhostGatewayClient) {
    this.registerWorkspaceWatchers();
    this.registerGatewayListeners();
  }

  private registerWorkspaceWatchers() {
    // 1. Sync on file save to keep Ghost Workspace-RAG immediately up to date
    this.disposables.push(
      vscode.workspace.onDidSaveTextDocument(async (doc) => {
        const config = vscode.workspace.getConfiguration("ghost");
        const enabled = config.get<boolean>("antigravity.enabled", true);
        const syncWorkspace = config.get<boolean>("antigravity.syncWorkspace", true);

        if (!enabled || !syncWorkspace || doc.uri.scheme !== "file") {
          return;
        }

        const workspaceFolder = vscode.workspace.getWorkspaceFolder(doc.uri);
        if (!workspaceFolder) return;

        const relPath = vscode.workspace.asRelativePath(doc.uri, false);
        console.log(`[AntigravitySync] File saved: ${relPath}, syncing with Ghost RAG...`);

        try {
          if (this.client.getState() === "connected") {
            await this.client.sendRpc("acp.context/query", {
              query: `sync_file:${relPath}`,
              workspacePath: workspaceFolder.uri.fsPath,
            });
          }
        } catch (e) {
          console.warn("[AntigravitySync] Failed to notify Gateway of file save:", e);
        }
      })
    );
  }

  private registerGatewayListeners() {
    // Listen for agent responses or task updates to notify editor
    this.client.on("response", (payload: any) => {
      const config = vscode.workspace.getConfiguration("ghost");
      if (!config.get<boolean>("antigravity.syncKanban", true)) return;

      if (payload?.message?.metadata?.antigravity_plan) {
        vscode.window.showInformationMessage(
          `🤖 Ghost: Plan-Schritt abgeschlossen: ${payload.message.metadata.antigravity_plan}`
        );
      }
    });
  }

  /**
   * Manually trigger workspace sync.
   */
  public async syncCurrentWorkspace(): Promise<boolean> {
    const folders = vscode.workspace.workspaceFolders;
    if (!folders || folders.length === 0) {
      vscode.window.showWarningMessage("Kein Workspace-Ordner in VS Code / Antigravity geöffnet.");
      return false;
    }

    const folderPath = folders[0].uri.fsPath;
    try {
      await vscode.window.withProgress(
        {
          location: vscode.ProgressLocation.Notification,
          title: "Ghost: Synchronisiere Workspace-RAG mit Antigravity...",
          cancellable: false,
        },
        async () => {
          await this.client.sendRpc("acp.context/query", {
            query: "project_overview",
            workspacePath: folderPath,
          });
        }
      );
      vscode.window.showInformationMessage("✅ Workspace erfolgreich mit Ghost synchronisiert!");
      return true;
    } catch (e: any) {
      vscode.window.showErrorMessage(`Synchronisation fehlgeschlagen: ${e.message || e}`);
      return false;
    }
  }

  public dispose() {
    for (const d of this.disposables) {
      d.dispose();
    }
    this.disposables = [];
  }
}
