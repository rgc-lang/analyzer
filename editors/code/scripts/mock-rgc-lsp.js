#!/usr/bin/env node
/*
 * Minimal LSP server used ONLY to verify the rgc-lang client wiring.
 *
 * It is NOT the real RGC language server. The real analyzer is written in RGC and lives in this repository
 * and must implement the contract documented in docs/lsp-server-contract.md.
 *
 * Usage (in VS Code settings):
 *   "rgc.lsp.serverPath": "node",
 *   "rgc.lsp.serverArgs": ["<absolute path to this file>"]
 *
 * Or from a terminal:
 *   node analyzer/editors/code/scripts/mock-rgc-lsp.js
 */
"use strict";

const { stdin, stdout, exit } = process;

let buffer = Buffer.alloc(0);

function send(message) {
  const payload = Buffer.from(JSON.stringify(message), "utf8");
  stdout.write(`Content-Length: ${payload.length}\r\n\r\n`);
  stdout.write(payload);
}

function reply(id, result) {
  send({ jsonrpc: "2.0", id, result });
}

function replyError(id, code, message) {
  send({ jsonrpc: "2.0", id, error: { code, message } });
}

function publishMockDiagnostics(uri, version) {
  send({
    jsonrpc: "2.0",
    method: "textDocument/publishDiagnostics",
    params: {
      uri,
      version,
      diagnostics: [
        {
          range: {
            start: { line: 0, character: 0 },
            end: { line: 0, character: 0 },
          },
          severity: 3,
          source: "mock-rgc-lsp",
          message:
            "mock server connected — real diagnostics will come from the RGC server / mock 服务器已连接，真实诊断将由 RGC 服务器提供",
        },
      ],
    },
  });
}

function handleRequest(message) {
  switch (message.method) {
    case "initialize":
      reply(message.id, {
        capabilities: {
          textDocumentSync: { openClose: true, change: 1 },
          completionProvider: { triggerCharacters: [".", ":", "@"] },
          hoverProvider: true,
          definitionProvider: true,
          documentSymbolProvider: true,
        },
        serverInfo: { name: "mock-rgc-lsp", version: "0.1.0" },
      });
      return;
    case "shutdown":
      reply(message.id, null);
      return;
    default:
      replyError(message.id, -32601, `method not implemented: ${message.method}`);
  }
}

function handleNotification(message) {
  switch (message.method) {
    case "exit":
      exit(0);
      return;
    case "textDocument/didOpen":
      publishMockDiagnostics(
        message.params.textDocument.uri,
        message.params.textDocument.version,
      );
      return;
    case "textDocument/didChange":
      publishMockDiagnostics(
        message.params.textDocument.uri,
        message.params.textDocument.version,
      );
      return;
    case "textDocument/didClose":
      send({
        jsonrpc: "2.0",
        method: "textDocument/publishDiagnostics",
        params: { uri: message.params.textDocument.uri, diagnostics: [] },
      });
      return;
    default:
      // Ignore initialized, didSave, $/cancelRequest, ...
      return;
  }
}

function processBuffer() {
  for (;;) {
    const headerEnd = buffer.indexOf("\r\n\r\n");
    if (headerEnd === -1) {
      return;
    }

    const header = buffer.slice(0, headerEnd).toString("ascii");
    const match = /(?:^|\r\n)Content-Length:\s*(\d+)/i.exec(header);
    if (!match) {
      buffer = buffer.slice(headerEnd + 4);
      continue;
    }

    const length = Number.parseInt(match[1], 10);
    const bodyStart = headerEnd + 4;
    if (buffer.length < bodyStart + length) {
      return;
    }

    const body = buffer.slice(bodyStart, bodyStart + length).toString("utf8");
    buffer = buffer.slice(bodyStart + length);

    let message;
    try {
      message = JSON.parse(body);
    } catch {
      continue;
    }

    if (typeof message.method === "string") {
      if (message.id !== undefined && message.id !== null) {
        handleRequest(message);
      } else {
        handleNotification(message);
      }
    }
  }
}

stdin.on("data", (chunk) => {
  buffer = Buffer.concat([buffer, chunk]);
  processBuffer();
});

stdin.on("end", () => exit(0));
