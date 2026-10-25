#!/usr/bin/env node
/*
 * Smoke-test the analyzer over stdio: initialize -> initialized -> shutdown -> exit.
 *
 * Usage: node scripts/smoke-lsp.js [path-to-rgc-analyzer]
 */
"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { spawn } = require("node:child_process");

const repoRoot = path.resolve(__dirname, "..");
const exeName = process.platform === "win32" ? "rgc-analyzer.exe" : "rgc-analyzer";
const serverPath = path.resolve(
  process.argv[2] || path.join(repoRoot, "build", "server", exeName),
);
const TIMEOUT_MS = 10000;

if (!fs.existsSync(serverPath)) {
  console.error(`error: analyzer not found: ${serverPath}`);
  process.exit(1);
}

const child = spawn(serverPath, ["--stdio"], { stdio: ["pipe", "pipe", "pipe"] });

let buffer = Buffer.alloc(0);
const responses = [];
let stderr = "";
let exited = false;

const timer = setTimeout(() => {
  console.error(`error: timed out after ${TIMEOUT_MS} ms`);
  child.kill();
  process.exit(1);
}, TIMEOUT_MS);

child.stderr.on("data", (chunk) => {
  stderr += chunk.toString("utf8");
});

child.on("exit", (code) => {
  exited = true;
  clearTimeout(timer);
  if (!responses.some((message) => message.id === 1)) {
    console.error("error: no initialize response");
    if (stderr) console.error(`server stderr:\n${stderr}`);
    process.exit(1);
  }
  if (code !== 0) {
    console.error(`error: server exited with code ${code}`);
    if (stderr) console.error(`server stderr:\n${stderr}`);
    process.exit(1);
  }
  console.log("smoke: analyzer handshake OK");
});

function send(message) {
  const body = Buffer.from(JSON.stringify(message), "utf8");
  child.stdin.write(`Content-Length: ${body.length}\r\n\r\n`);
  child.stdin.write(body);
}

function parseFrames() {
  for (;;) {
    const headerEnd = buffer.indexOf("\r\n\r\n");
    if (headerEnd < 0) return;
    const header = buffer.subarray(0, headerEnd).toString("ascii");
    const match = /Content-Length:\s*(\d+)/i.exec(header);
    if (!match) {
      console.error(`error: malformed header: ${header}`);
      child.kill();
      process.exit(1);
    }
    const length = Number(match[1]);
    const bodyStart = headerEnd + 4;
    if (buffer.length < bodyStart + length) return;
    const body = buffer.subarray(bodyStart, bodyStart + length).toString("utf8");
    buffer = buffer.subarray(bodyStart + length);

    let message;
    try {
      message = JSON.parse(body);
    } catch (error) {
      console.error(`error: invalid JSON from server: ${error.message}`);
      child.kill();
      process.exit(1);
    }
    handle(message);
  }
}

function handle(message) {
  responses.push(message);
  if (message.id === 1) {
    const info = message.result?.serverInfo;
    if (!info || info.name !== "rgc-analyzer") {
      console.error(`error: unexpected serverInfo: ${JSON.stringify(info)}`);
      child.kill();
      process.exit(1);
    }
    if (message.result?.capabilities?.hoverProvider !== true) {
      console.error("error: hoverProvider not advertised");
      child.kill();
      process.exit(1);
    }
    send({ jsonrpc: "2.0", method: "initialized", params: {} });
    send({ jsonrpc: "2.0", id: 2, method: "shutdown", params: null });
  } else if (message.id === 2) {
    if (message.result !== null) {
      console.error(`error: shutdown returned ${JSON.stringify(message.result)}`);
      child.kill();
      process.exit(1);
    }
    send({ jsonrpc: "2.0", method: "exit" });
  }
}

child.stdout.on("data", (chunk) => {
  buffer = Buffer.concat([buffer, chunk]);
  parseFrames();
});

child.on("error", (error) => {
  console.error(`error: failed to spawn ${serverPath}: ${error.message}`);
  process.exit(1);
});

send({
  jsonrpc: "2.0",
  id: 1,
  method: "initialize",
  params: {
    processId: process.pid,
    clientInfo: { name: "smoke-lsp", version: "1.0.0" },
    rootUri: null,
    capabilities: {},
    initializationOptions: { compilerPath: "rgc" },
  },
});

process.on("exit", () => {
  if (!exited && !child.killed) child.kill();
});
