import * as path from "path";
import * as vscode from "vscode";

import { getConfig } from "./config";

function activeRgcDocument(): vscode.TextDocument | undefined {
  const editor = vscode.window.activeTextEditor;
  if (!editor || editor.document.languageId !== "rgc") {
    void vscode.window.showWarningMessage(
      vscode.l10n.t("Please open a .rg file first."),
    );
    return undefined;
  }
  return editor.document;
}

function quote(value: string): string {
  return `"${value.replace(/"/g, '\\"')}"`;
}

function runInTerminal(cwd: string, commandLine: string): void {
  const terminal = vscode.window.createTerminal({ name: "RGC", cwd });
  terminal.show();
  terminal.sendText(commandLine);
}

export function registerCommands(context: vscode.ExtensionContext): void {
  context.subscriptions.push(
    vscode.commands.registerCommand("rgc.build", async () => {
      const document = activeRgcDocument();
      if (!document) {
        return;
      }

      const directory = path.dirname(document.uri.fsPath);
      const stem = path.parse(document.uri.fsPath).name;
      const output = await vscode.window.showInputBox({
        prompt: vscode.l10n.t("Output file name (without path)"),
        value: stem,
      });
      if (output === undefined) {
        return;
      }

      const compiler = getConfig(context).compilerPath;
      const outputPath = path.join(directory, output.trim() || stem);
      runInTerminal(
        directory,
        `${quote(compiler)} ${quote(document.uri.fsPath)} -o ${quote(outputPath)}`,
      );
    }),

    vscode.commands.registerCommand("rgc.run", async () => {
      const document = activeRgcDocument();
      if (!document) {
        return;
      }

      const args = await vscode.window.showInputBox({
        prompt: vscode.l10n.t("Run arguments (optional)"),
      });
      if (args === undefined) {
        return;
      }

      const compiler = getConfig(context).compilerPath;
      const suffix = args.trim() ? ` ${args.trim()}` : "";
      runInTerminal(
        path.dirname(document.uri.fsPath),
        `${quote(compiler)} run ${quote(document.uri.fsPath)}${suffix}`,
      );
    }),

    vscode.commands.registerCommand("rgc.test", () => {
      const document = activeRgcDocument();
      if (!document) {
        return;
      }

      const compiler = getConfig(context).compilerPath;
      runInTerminal(
        path.dirname(document.uri.fsPath),
        `${quote(compiler)} test ${quote(document.uri.fsPath)}`,
      );
    }),
  );
}
