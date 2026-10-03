import * as vscode from "vscode";
import { GhostGatewayClient } from "../gateway/client";

export type AutopilotMode = "reviewMode" | "autoAccept";

/**
 * Manages Guarded Autopilot review requests and execution modes.
 */
export class AntigravityGuardrails implements vscode.Disposable {
  private currentMode: AutopilotMode = "reviewMode";
  private disposables: vscode.Disposable[] = [];

  constructor(private readonly client: GhostGatewayClient) {
    const config = vscode.workspace.getConfiguration("ghost");
    this.currentMode = config.get<AutopilotMode>("antigravity.autopilotMode", "reviewMode");
    this.registerReviewListener();
  }

  public getMode(): AutopilotMode {
    return this.currentMode;
  }

  /**
   * Toggle between reviewMode and autoAccept.
   */
  public async toggleMode(): Promise<AutopilotMode> {
    const newMode: AutopilotMode = this.currentMode === "reviewMode" ? "autoAccept" : "reviewMode";
    this.currentMode = newMode;

    const config = vscode.workspace.getConfiguration("ghost");
    await config.update("antigravity.autopilotMode", newMode, vscode.ConfigurationTarget.Global);

    const modeLabel = newMode === "autoAccept" ? "⚡ Auto-Accept (Vollautonom)" : "🛡️ Review-Mode (Guarded Autopilot)";
    vscode.window.showInformationMessage(`Ghost Autopilot-Modus geändert: ${modeLabel}`);

    return newMode;
  }

  private registerReviewListener() {
    // Listen for custom or ACP review requests over the client connection
    this.client.on("review_request", async (data: any) => {
      await this.handleReviewRequest(data);
    });
  }

  /**
   * Handle an interactive review request from Ghost.
   */
  public async handleReviewRequest(data: {
    reviewId: string;
    sessionId: string;
    actionType: string;
    details: any;
  }) {
    const { reviewId, sessionId, actionType, details } = data;
    const target = details?.path || details?.command || details?.filePath || "Aktion";

    const promptMessage = `🛡️ [Ghost Guarded Autopilot] Der Coding-Agent schlägt vor: ${actionType} auf "${target}". Freigeben?`;

    const choice = await vscode.window.showInformationMessage(
      promptMessage,
      { modal: true },
      "Freigeben (Accept)",
      "Ablehnen (Reject)",
      ...(details?.diff || details?.patch ? ["Diff ansehen"] : [])
    );

    if (choice === "Diff ansehen") {
      // Show diff in virtual document
      const doc = await vscode.workspace.openTextDocument({
        content: details.diff || details.patch,
        language: "diff",
      });
      await vscode.window.showTextDocument(doc, { preview: true });

      const finalChoice = await vscode.window.showInformationMessage(
        `Änderungen an "${target}" nach Diff-Prüfung anwenden?`,
        { modal: true },
        "Freigeben (Accept)",
        "Ablehnen (Reject)"
      );

      const approved = finalChoice === "Freigeben (Accept)";
      await this.sendReviewResponse(reviewId, sessionId, approved);
    } else {
      const approved = choice === "Freigeben (Accept)";
      await this.sendReviewResponse(reviewId, sessionId, approved);
    }
  }

  private async sendReviewResponse(reviewId: string, sessionId: string, approved: boolean) {
    try {
      await this.client.sendRpc("acp.session/review_response", {
        reviewId,
        sessionId,
        approved,
      });
      console.log(`[AntigravityGuardrails] Sent review response for ${reviewId}: approved=${approved}`);
    } catch (e) {
      console.error("[AntigravityGuardrails] Failed to send review response:", e);
    }
  }

  public dispose() {
    for (const d of this.disposables) {
      d.dispose();
    }
    this.disposables = [];
  }
}
