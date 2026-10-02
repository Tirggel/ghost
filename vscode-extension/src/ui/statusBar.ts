import * as vscode from "vscode";
import { GhostGatewayClient, ConnectionState } from "../gateway/client";

export class GhostStatusBar {
  private item: vscode.StatusBarItem;
  private client: GhostGatewayClient;
  private currentActivity = "";

  constructor(client: GhostGatewayClient) {
    this.client = client;
    this.item = vscode.window.createStatusBarItem(
      vscode.StatusBarAlignment.Right,
      100
    );
    this.item.command = "ghost.statusBarClick";
    this.update();
    this.item.show();

    // Listen to gateway events
    this.client.on("stateChange", (state: ConnectionState) => {
      this.currentActivity = "";
      this.update(state);
    });

    this.client.on("activity", (payload: { activity: string }) => {
      this.currentActivity = payload.activity;
      this.update();
    });

    this.client.on("response", () => {
      this.currentActivity = "";
      this.update();
    });

    this.client.on("error", () => {
      this.currentActivity = "";
      this.update();
    });
  }

  public update(state?: ConnectionState) {
    const currentState = state ?? this.client.getState();

    if (this.currentActivity) {
      this.item.text = `$(loading~spin) Ghost: ${this.currentActivity}`;
      this.item.tooltip = `Ghost verarbeitet: ${this.currentActivity}\nKlicken für Optionen.`;
      this.item.backgroundColor = undefined;
      return;
    }

    switch (currentState) {
      case "connected":
        this.item.text = "$(pass-filled) Ghost";
        this.item.tooltip = `Verbunden mit Ghost Gateway (${this.client.getUrl()})\nKlicken für Menü.`;
        this.item.backgroundColor = undefined;
        break;

      case "connecting":
        this.item.text = "$(sync~spin) Ghost";
        this.item.tooltip = "Verbinde mit Ghost Gateway...";
        this.item.backgroundColor = undefined;
        break;

      case "error":
        this.item.text = "$(error) Ghost (Fehler)";
        this.item.tooltip = "Verbindungsfehler zum Ghost Gateway.\nKlicken zum Wiederholen.";
        this.item.backgroundColor = new vscode.ThemeColor("statusBarItem.errorBackground");
        break;

      case "disconnected":
      default:
        this.item.text = "$(plug) Ghost: Getrennt";
        this.item.tooltip = "Nicht mit Ghost Gateway verbunden.\nKlicken zum Verbinden.";
        this.item.backgroundColor = new vscode.ThemeColor("statusBarItem.warningBackground");
        break;
    }
  }

  public async showQuickPick() {
    const state = this.client.getState();
    const items: vscode.QuickPickItem[] = [];

    if (state === "connected") {
      items.push(
        {
          label: "$(comment-discussion) Ghost Chat öffnen",
          description: "Öffnet die Chat-Seitenleiste",
          detail: "open_chat",
        },
        {
          label: "$(add) Neue Sitzung starten",
          description: "Startet eine frische Chat-Sitzung",
          detail: "new_session",
        },
        {
          label: "$(symbol-color) Modell wechseln",
          description: "Aktives KI-Modell für Ghost auswählen",
          detail: "change_model",
        },
        {
          label: "$(refresh) Gateway neu verbinden",
          description: "Trennt die Verbindung und verbindet sich neu",
          detail: "reconnect",
        },
        {
          label: "$(debug-disconnect) Verbindung trennen",
          description: "Ghost WebSocket trennen",
          detail: "disconnect",
        }
      );
    } else {
      items.push(
        {
          label: "$(play) Mit Ghost Gateway verbinden",
          description: this.client.getUrl(),
          detail: "connect",
        },
        {
          label: "$(gear) Ghost Einstellungen öffnen",
          description: "URL und Token anpassen",
          detail: "settings",
        }
      );
    }

    const selected = await vscode.window.showQuickPick(items, {
      placeHolder: `Ghost Status: ${state.toUpperCase()}`,
    });

    if (!selected) return;

    switch (selected.detail) {
      case "open_chat":
        vscode.commands.executeCommand("ghost.openChat");
        break;
      case "new_session":
        vscode.commands.executeCommand("ghost.newSession");
        break;
      case "change_model":
        this.showModelPicker();
        break;
      case "connect":
      case "reconnect":
        vscode.commands.executeCommand("ghost.connect");
        break;
      case "disconnect":
        vscode.commands.executeCommand("ghost.disconnect");
        break;
      case "settings":
        vscode.commands.executeCommand(
          "workbench.action.openSettings",
          "ghost"
        );
        break;
    }
  }

  private async showModelPicker() {
    try {
      const models = await this.client.listModels();
      if (!models || models.length === 0) {
        vscode.window.showInformationMessage("Keine zusätzlichen Modelle vom Gateway gemeldet.");
        return;
      }

      const selected = await vscode.window.showQuickPick(
        models.map((m) => ({ label: m })),
        { placeHolder: "Wähle das Modell für Ghost:" }
      );

      if (selected) {
        vscode.window.showInformationMessage(`Ghost Modell gewählt: ${selected.label}`);
      }
    } catch (e: any) {
      vscode.window.showErrorMessage(`Fehler beim Abrufen der Modelle: ${e.message}`);
    }
  }

  public dispose() {
    this.item.dispose();
  }
}
