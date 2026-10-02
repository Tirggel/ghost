import * as vscode from "vscode";
import { GhostChatViewProvider } from "../views/chatViewProvider";

export function registerEditorCommands(
  context: vscode.ExtensionContext,
  chatProvider: GhostChatViewProvider
) {
  // 1. Explain Selection
  context.subscriptions.push(
    vscode.commands.registerCommand("ghost.explainSelection", async () => {
      const editor = vscode.window.activeTextEditor;
      if (!editor || editor.selection.isEmpty) {
        vscode.window.showInformationMessage("Bitte markiere zuerst den Code, den Ghost erklären soll.");
        return;
      }
      const code = editor.document.getText(editor.selection);
      await chatProvider.sendPromptWithActiveContext(
        "Bitte erkläre diesen Codeabschnitt detailliert und verständlich:",
        code
      );
    })
  );

  // 2. Refactor Selection
  context.subscriptions.push(
    vscode.commands.registerCommand("ghost.refactorSelection", async () => {
      const editor = vscode.window.activeTextEditor;
      if (!editor || editor.selection.isEmpty) {
        vscode.window.showInformationMessage("Bitte markiere zuerst den Code, den Ghost refaktorisieren soll.");
        return;
      }
      const code = editor.document.getText(editor.selection);
      await chatProvider.sendPromptWithActiveContext(
        "Refaktorisiere diesen Code. Achte auf Lesbarkeit, Performance, Typ-Sicherheit und Best Practices. Zeige mir den verbesserten Code und erkläre kurz die Änderungen:",
        code
      );
    })
  );

  // 3. Generate Unit Tests
  context.subscriptions.push(
    vscode.commands.registerCommand("ghost.generateTests", async () => {
      const editor = vscode.window.activeTextEditor;
      if (!editor || editor.selection.isEmpty) {
        vscode.window.showInformationMessage("Bitte markiere zuerst den Code, für den Ghost Tests schreiben soll.");
        return;
      }
      const code = editor.document.getText(editor.selection);
      await chatProvider.sendPromptWithActiveContext(
        "Schreibe vollständige, robuste Unit-Tests für diese Funktion/Klasse inklusive Randfälle und Fehlerbehandlung:",
        code
      );
    })
  );

  // 4. Fix Diagnostics / Linter Errors
  context.subscriptions.push(
    vscode.commands.registerCommand("ghost.fixErrors", async () => {
      const editor = vscode.window.activeTextEditor;
      if (!editor) {
        vscode.window.showInformationMessage("Kein aktiver Editor geöffnet.");
        return;
      }

      const doc = editor.document;
      const diagnostics = vscode.languages.getDiagnostics(doc.uri);

      // Filter diagnostics intersecting current selection or file
      const relevant = editor.selection.isEmpty
        ? diagnostics
        : diagnostics.filter((d) => d.range.intersection(editor.selection) !== undefined);

      if (relevant.length === 0) {
        vscode.window.showInformationMessage("Keine Compiler- oder Linter-Fehler im markierten Bereich gefunden! 🎉");
        return;
      }

      const errorDescriptions = relevant
        .map((d) => `- Zeile ${d.range.start.line + 1}: [${d.source || "Linter"}] ${d.message}`)
        .join("\n");

      const code = editor.selection.isEmpty
        ? doc.getText()
        : doc.getText(editor.selection);

      await chatProvider.sendPromptWithActiveContext(
        `Bitte analysiere und behebe die folgenden Fehler:\n\n${errorDescriptions}\n\nRelevanter Code:`,
        code
      );
    })
  );
}
