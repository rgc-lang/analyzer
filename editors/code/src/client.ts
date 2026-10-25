import * as vscode from "vscode";
import * as lc from "vscode-languageclient/node";

import { getConfig, serverCommandLine } from "./config";
import { ServerStatusBar } from "./status";

/**
 * Owns the lifecycle of the RGC language server connection.
 *
 * The server is an external executable speaking LSP over stdio. By default the
 * client runs `rgc-analyzer`; both the executable and its arguments are
 * configurable through `rgc.lsp.serverPath` / `rgc.lsp.serverArgs`.
 */
export class RgcLanguageClient implements vscode.Disposable {
  private readonly outputChannel: vscode.OutputChannel;
  private readonly traceOutputChannel: vscode.OutputChannel;

  private client: lc.LanguageClient | undefined;
  private disposed = false;
  private stopping = false;
  private warned = false;

  constructor(
    private readonly context: vscode.ExtensionContext,
    private readonly status: ServerStatusBar,
  ) {
    this.outputChannel = vscode.window.createOutputChannel(
      vscode.l10n.t("RGC Language Server"),
    );
    this.traceOutputChannel = vscode.window.createOutputChannel(
      vscode.l10n.t("RGC LSP Trace"),
    );
  }

  async start(): Promise<void> {
    if (this.disposed) {
      return;
    }
    await this.stop();
    if (this.disposed) {
      return;
    }

    const config = getConfig(this.context);

    const serverOptions: lc.ServerOptions = {
      command: config.serverPath,
      args: config.serverArgs,
      options: {
        cwd: vscode.workspace.workspaceFolders?.[0]?.uri.fsPath,
        env: config.serverEnv,
      },
    };

    const clientOptions: lc.LanguageClientOptions = {
      documentSelector: [{ language: "rgc", scheme: "file" }],
      synchronize: {
        configurationSection: "rgc",
      },
      outputChannel: this.outputChannel,
      traceOutputChannel: this.traceOutputChannel,
      initializationOptions: {
        compilerPath: config.compilerPath,
      },
      connectionOptions: {
        // The RGC server may not be implemented yet; do not respawn forever.
        maxRestartCount: 0,
      },
      // Suppress the client's default "force" notifications. Server lifecycle
      // is reported by our own status bar and a single warning instead.
      errorHandler: {
        error: () => ({ action: lc.ErrorAction.Continue, handled: true }),
        closed: () => ({ action: lc.CloseAction.DoNotRestart, handled: true }),
      },
    };

    const client = new lc.LanguageClient(
      "rgc",
      "RGC Language Server",
      serverOptions,
      clientOptions,
    );
    this.client = client;

    client.onDidChangeState((event) => {
      if (this.client !== client) {
        return;
      }
      void this.updateServerContext(event.newState === lc.State.Running);
      switch (event.newState) {
        case lc.State.Starting:
          this.status.setStarting();
          break;
        case lc.State.Running:
          this.status.setRunning();
          this.warned = false;
          break;
        case lc.State.Stopped:
          this.status.setStopped();
          if (!this.warned && !this.stopping && !this.disposed) {
            this.warned = true;
            void vscode.window.showWarningMessage(
              vscode.l10n.t(
                "The RGC language server is not available yet. Syntax highlighting and build commands still work.",
              ),
            );
          }
          break;
      }
    });

    this.status.setStarting();
    try {
      await client.start();
    } catch (error) {
      this.status.setStopped();
      void this.updateServerContext(false);
      if (!this.warned && !this.stopping && !this.disposed) {
        this.warned = true;
        const message = error instanceof Error ? error.message : String(error);
        void vscode.window.showWarningMessage(
          vscode.l10n.t("RGC language server failed to start: {0}", message),
        );
        void vscode.window.showInformationMessage(
          vscode.l10n.t("Configured command: {0}", serverCommandLine(config)),
        );
      }
    }
  }

  async stop(): Promise<void> {
    const client = this.client;
    this.client = undefined;
    if (!client) {
      return;
    }
    this.stopping = true;
    try {
      await client.stop();
    } catch {
      // The server process may already have exited; nothing to clean up.
    } finally {
      this.stopping = false;
    }
  }

  async restart(): Promise<void> {
    await this.start();
  }

  dispose(): void {
    this.disposed = true;
    void this.stop();
    this.outputChannel.dispose();
    this.traceOutputChannel.dispose();
  }

  private async updateServerContext(running: boolean): Promise<void> {
    await vscode.commands.executeCommand(
      "setContext",
      "rgc.serverRunning",
      running,
    );
  }
}
