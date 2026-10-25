import * as vscode from "vscode";

/**
 * Status bar entry showing the RGC language server state.
 * Clicking it runs `rgc.restartServer`.
 */
export class ServerStatusBar implements vscode.Disposable {
  private readonly item: vscode.StatusBarItem;

  constructor() {
    this.item = vscode.window.createStatusBarItem(
      vscode.StatusBarAlignment.Left,
      100,
    );
    this.item.command = "rgc.restartServer";
    this.item.tooltip = vscode.l10n.t(
      "RGC language server status (click to restart)",
    );
    this.setStarting();
    this.item.show();
  }

  setStarting(): void {
    this.item.text = `$(sync~spin) ${vscode.l10n.t("RGC: Starting…")}`;
  }

  setRunning(): void {
    this.item.text = `$(check) ${vscode.l10n.t("RGC: Ready")}`;
  }

  setStopped(): void {
    this.item.text = `$(circle-slash) ${vscode.l10n.t("RGC: Not Running")}`;
  }

  dispose(): void {
    this.item.dispose();
  }
}
