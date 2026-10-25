# RGC Language Server Contract

[English](#english) · [中文](#中文)

This document defines the interface between the `rgc-lang` client and the
language server that is written in **RGC**. The client is already implemented;
the server only has to satisfy this contract.

---

## English

### 1. Transport

- The server is an executable launched by the VS Code extension.
- Communication uses **stdin/stdout** with the LSP base protocol:
  - Each message is a JSON-RPC 2.0 object encoded as UTF-8.
  - Messages are framed by ASCII headers:

```text
Content-Length: <byte length of the JSON body>\r\n
\r\n
<JSON body>
```

- `Content-Length` counts **bytes**, not characters.
- The server must not write anything else to stdout (use stderr for logs).

### 2. Launch

Default configuration:

```text
rgc-analyzer --stdio
```

The official VSIX packages bundle the analyzer at `server/rgc-analyzer` (with
`server/lib` for module resolution) and set `RGC_STD` accordingly. An analyzer
installed elsewhere can be configured:

```json
{
  "rgc.lsp.serverPath": "/path/to/rgc-analyzer",
  "rgc.lsp.serverArgs": []
}
```

The client sends `initialize` immediately after spawning the process, then
`initialized`. The server should exit when it receives `exit`, and should reply
to `shutdown` with `null` before that.

### 3. `initialize`

The client sends:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "processId": 12345,
    "clientInfo": { "name": "Visual Studio Code", "version": "..." },
    "rootUri": "file:///path/to/project",
    "capabilities": { "...": "..." },
    "initializationOptions": { "compilerPath": "rgc" }
  }
}
```

`initializationOptions.compilerPath` is the configured `rgc.compilerPath`.

The server replies with its capabilities. A minimal, useful set:

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "capabilities": {
      "textDocumentSync": { "openClose": true, "change": 1 },
      "completionProvider": { "triggerCharacters": [".", ":", "@"] },
      "hoverProvider": true,
      "definitionProvider": true,
      "documentSymbolProvider": true
    },
    "serverInfo": { "name": "rgc-analyzer", "version": "0.1.0" }
  }
}
```

`change: 1` means **full document sync**: each `textDocument/didChange`
contains the complete new text. This is the simplest correct choice for a first
implementation. Switch to `change: 2` (incremental) later if needed.

### 4. Document synchronization

The client sends:

- `textDocument/didOpen` with `{ textDocument: { uri, languageId, version, text } }`
- `textDocument/didChange` with the full text (when `change: 1`)
- `textDocument/didSave`
- `textDocument/didClose`

The server should keep an in-memory map `uri -> text` and re-analyze on open,
change, and save.

### 5. Diagnostics

The server pushes diagnostics at any time:

```json
{
  "jsonrpc": "2.0",
  "method": "textDocument/publishDiagnostics",
  "params": {
    "uri": "file:///path/to/file.rg",
    "version": 3,
    "diagnostics": [
      {
        "range": {
          "start": { "line": 1, "character": 13 },
          "end": { "line": 1, "character": 20 }
        },
        "severity": 1,
        "source": "rgc",
        "message": "type mismatch: expected `int`, found `str`"
      }
    ]
  }
}
```

- `line` and `character` are **zero-based**.
- `character` is measured in **UTF-16 code units** (the LSP default). For ASCII
  source this is the same as bytes; for non-ASCII text, convert carefully.
- `severity`: `1` error, `2` warning, `3` information, `4` hint.
- To clear diagnostics, publish an empty array.

### 6. Language features

| Request | Result |
| --- | --- |
| `textDocument/completion` | `CompletionItem[]` or `CompletionList` |
| `textDocument/hover` | `Hover` (`contents` as Markdown or plain text) |
| `textDocument/definition` | `Location` or `Location[]` |
| `textDocument/documentSymbol` | `DocumentSymbol[]` or `SymbolInformation[]` |

These are optional: the client displays whatever the server advertises and
returns.

### 7. Error handling

- Unknown requests: reply with JSON-RPC error `-32601` (method not found).
- Malformed messages: ignore them and keep reading; never crash the process.
- The server must tolerate incomplete reads: buffer stdin until a complete
  `Content-Length` body is available.

### 8. Testing the client

Use the bundled mock server to check that the client can connect:

```json
{
  "rgc.lsp.serverPath": "node",
  "rgc.lsp.serverArgs": ["/absolute/path/to/analyzer/editors/code/scripts/mock-rgc-lsp.js"]
}
```

Expected result: the status bar shows **RGC: Ready**, and an information
diagnostic appears on line 1 of each opened `.rg` file.

### 9. Implementation notes for the RGC analyzer

The analyzer is written in RGC and lives in the analyzer repository, together
with the VS Code extension. The pieces it needs:

1. Read raw bytes from stdin until `\r\n\r\n`, parse `Content-Length`, then read
   exactly that many bytes.
2. JSON parse/serialize (a minimal parser is enough for the messages above).
3. A dispatch loop over `method`.
4. A document store (`Map[str, str]` or equivalent).
5. The RGC lexer/parser/type checker, shared with the compiler through the
   frontend sources staged by `scripts/build-analyzer.js`.
6. Diagnostic conversion from compiler positions (1-based line/column) to LSP
   positions (0-based line/character).

Until the RGC server exists, the client remains fully usable for syntax
highlighting and build/run/test commands.

---

## 中文

本文档定义 `rgc-lang` 客户端与**用 RGC 编写**的语言服务器之间的接口。
客户端已经完成，服务器只需满足本契约。

### 1. 传输层

- 服务器是由 VS Code 扩展启动的可执行文件。
- 通过 **stdin/stdout** 通信，遵循 LSP 基础协议：
  - 每条消息是一个 UTF-8 编码的 JSON-RPC 2.0 对象。
  - 消息使用 ASCII 头分帧：

```text
Content-Length: <JSON 体的字节数>\r\n
\r\n
<JSON 体>
```

- `Content-Length` 计的是**字节数**，不是字符数。
- 服务器不能向 stdout 写任何其他内容（日志请写 stderr）。

### 2. 启动方式

默认配置：

```text
rgc-analyzer --stdio
```

官方 VSIX 安装包把分析器放在 `server/rgc-analyzer`（`server/lib` 用于模块解析），
并相应设置 `RGC_STD`。使用安装在别处的分析器：

```json
{
  "rgc.lsp.serverPath": "/path/to/rgc-analyzer",
  "rgc.lsp.serverArgs": []
}
```

客户端启动进程后立即发送 `initialize`，随后发送 `initialized`。收到 `exit`
时服务器应退出；退出前应先对 `shutdown` 回复 `null`。

### 3. `initialize`

客户端发送：

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "processId": 12345,
    "clientInfo": { "name": "Visual Studio Code", "version": "..." },
    "rootUri": "file:///path/to/project",
    "capabilities": { "...": "..." },
    "initializationOptions": { "compilerPath": "rgc" }
  }
}
```

`initializationOptions.compilerPath` 即配置项 `rgc.compilerPath`。

服务器返回能力声明。一组最小可用能力：

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "capabilities": {
      "textDocumentSync": { "openClose": true, "change": 1 },
      "completionProvider": { "triggerCharacters": [".", ":", "@"] },
      "hoverProvider": true,
      "definitionProvider": true,
      "documentSymbolProvider": true
    },
    "serverInfo": { "name": "rgc-analyzer", "version": "0.1.0" }
  }
}
```

`change: 1` 表示**全量同步**：每次 `textDocument/didChange` 都携带完整新文本。
这是首个实现最简单、最正确的选择。后续如有需要再切换到 `change: 2`（增量）。

### 4. 文档同步

客户端会发送：

- `textDocument/didOpen`：`{ textDocument: { uri, languageId, version, text } }`
- `textDocument/didChange`：全量文本（当 `change: 1` 时）
- `textDocument/didSave`
- `textDocument/didClose`

服务器应维护 `uri -> text` 的内存映射，并在打开、修改、保存时重新分析。

### 5. 诊断

服务器可随时推送诊断：

```json
{
  "jsonrpc": "2.0",
  "method": "textDocument/publishDiagnostics",
  "params": {
    "uri": "file:///path/to/file.rg",
    "version": 3,
    "diagnostics": [
      {
        "range": {
          "start": { "line": 1, "character": 13 },
          "end": { "line": 1, "character": 20 }
        },
        "severity": 1,
        "source": "rgc",
        "message": "type mismatch: expected `int`, found `str`"
      }
    ]
  }
}
```

- `line` 与 `character` 均为 **0 基**。
- `character` 按 **UTF-16 code unit** 计算（LSP 默认）。纯 ASCII 源码与字节数
  相同；含非 ASCII 字符时需正确换算。
- `severity`：`1` 错误、`2` 警告、`3` 信息、`4` 提示。
- 清除诊断：发送空数组。

### 6. 语言功能

| 请求 | 结果 |
| --- | --- |
| `textDocument/completion` | `CompletionItem[]` 或 `CompletionList` |
| `textDocument/hover` | `Hover`（`contents` 为 Markdown 或纯文本） |
| `textDocument/definition` | `Location` 或 `Location[]` |
| `textDocument/documentSymbol` | `DocumentSymbol[]` 或 `SymbolInformation[]` |

这些均为可选：客户端展示服务器声明并返回的内容。

### 7. 错误处理

- 未知请求：返回 JSON-RPC 错误 `-32601`（method not found）。
- 消息格式错误：忽略并继续读取，进程不得崩溃。
- 必须能处理不完整读取：缓冲 stdin，直到凑齐完整的 `Content-Length` 消息体。

### 8. 测试客户端

使用附带的 mock 服务器验证客户端能否连接：

```json
{
  "rgc.lsp.serverPath": "node",
  "rgc.lsp.serverArgs": ["/absolute/path/to/analyzer/editors/code/scripts/mock-rgc-lsp.js"]
}
```

预期结果：状态栏显示 **RGC: 已就绪**，每个打开的 `.rg` 文件首行出现一条
信息级诊断。

### 9. RGC 分析器实现要点

分析器用 RGC 编写，与 VS Code 扩展同处分析器仓库。需要：

1. 从 stdin 读取原始字节直到 `\r\n\r\n`，解析 `Content-Length`，再精确读取
   对应字节数。
2. JSON 解析/序列化（覆盖上述消息的最小解析器即可）。
3. 按 `method` 分发的循环。
4. 文档存储（`Map[str, str]` 或等价结构）。
5. 与编译器共享的 RGC 词法/语法/类型检查器（由 `scripts/build-analyzer.js`
   把前端源码暂存到构建目录）。
6. 把编译器位置（1 基行列）转换为 LSP 位置（0 基行列）。

在 RGC 服务器完成之前，客户端仍可正常用于语法高亮与编译/运行/测试命令。
