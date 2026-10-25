import * as vscode from "vscode";

import { RgcLanguageClient } from "./client";
import { registerCommands } from "./commands";
import { ServerStatusBar } from "./status";

export function activate(context: vscode.ExtensionContext): void {
  const status = new ServerStatusBar();
  const client = new RgcLanguageClient(context, status);

  context.subscriptions.push(status, client);

  registerCommands(context);
  context.subscriptions.push(
    vscode.commands.registerCommand("rgc.restartServer", () => client.restart()),
  );

  // Changing the server executable or its arguments requires a restart.
  context.subscriptions.push(
    vscode.workspace.onDidChangeConfiguration((event) => {
      if (
        event.affectsConfiguration("rgc.lsp.serverPath") ||
        event.affectsConfiguration("rgc.lsp.serverArgs")
      ) {
        void client.restart();
      }
    }),
  );

  void client.start();
}

export function deactivate(): void {
  // Shutdown is handled by the disposables registered in `context.subscriptions`.
}
