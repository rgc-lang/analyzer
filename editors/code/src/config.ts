import * as fs from "fs";
import * as path from "path";
import * as vscode from "vscode";

export type TraceLevel = "off" | "messages" | "verbose";

/** Default server command; also the name looked up on `PATH`. */
export const SERVER_NAME = "rgc-analyzer";

export interface RgcConfig {
  /** Path to the `rgc` compiler used by build/run/test commands. */
  compilerPath: string;
  /** Path to the RGC analyzer executable. */
  serverPath: string;
  /** Arguments passed to the analyzer. */
  serverArgs: string[];
  /** Environment for the analyzer process, set when using the bundled server. */
  serverEnv: NodeJS.ProcessEnv | undefined;
  /** LSP trace level. */
  traceServer: TraceLevel;
}

function bundledServer(context: vscode.ExtensionContext): string | undefined {
  const exe = process.platform === "win32" ? `${SERVER_NAME}.exe` : SERVER_NAME;
  const candidate = path.join(context.extensionPath, "server", exe);
  return fs.existsSync(candidate) ? candidate : undefined;
}

function bundledLib(context: vscode.ExtensionContext): string | undefined {
  const candidate = path.join(context.extensionPath, "server", "lib");
  return fs.existsSync(candidate) ? candidate : undefined;
}

export function getConfig(context: vscode.ExtensionContext): RgcConfig {
  const config = vscode.workspace.getConfiguration("rgc");
  const configured = config.get<string>("lsp.serverPath", SERVER_NAME);
  const bundled = configured === SERVER_NAME ? bundledServer(context) : undefined;
  const lib = bundled ? bundledLib(context) : undefined;
  return {
    compilerPath: config.get<string>("compilerPath", "rgc"),
    serverPath: bundled ?? configured,
    serverArgs: config.get<string[]>("lsp.serverArgs", []),
    serverEnv: lib ? { ...process.env, RGC_STD: lib } : undefined,
    traceServer: config.get<TraceLevel>("trace.server", "off"),
  };
}

/** Human-readable server command line, used in diagnostics messages. */
export function serverCommandLine(config: RgcConfig): string {
  return [config.serverPath, ...config.serverArgs].join(" ");
}
