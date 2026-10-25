# RGC for VS Code

<p align="center">
  <img src="resources/lockup.png" alt="RGC" width="480"/>
</p>

[![Visual Studio Marketplace Version](https://img.shields.io/visual-studio-marketplace/v/rgc-dev.rgc-lang.svg?label=VS%20Marketplace&logo=visual-studio-code)](https://marketplace.visualstudio.com/items?itemName=rgc-dev.rgc-lang)
[![Visual Studio Marketplace Installs](https://img.shields.io/visual-studio-marketplace/i/rgc-dev.rgc-lang.svg)](https://marketplace.visualstudio.com/items?itemName=rgc-dev.rgc-lang)
[![Open VSX Version](https://img.shields.io/open-vsx/v/rgc-dev/rgc-lang.svg?label=Open%20VSX)](https://open-vsx.org/extension/rgc-dev/rgc-lang)
[![CI](https://img.shields.io/github/actions/workflow/status/rgc-lang/analyzer/ci.yml.svg?label=CI)](https://github.com/rgc-lang/analyzer/actions)
[![License](https://img.shields.io/github/license/rgc-lang/analyzer.svg)](LICENSE)

[English](#english) · [中文](#中文)

---

## English

**RGC** is a Python-style compiled language with an LLVM backend, static typing,
and ownership/borrow checking. This extension brings full language support to
VS Code: syntax highlighting, snippets, build/run/test commands, and an LSP client
for the RGC analyzer (bundled in the official packages, or `rgc-analyzer` on
`PATH`).

### Features

- Syntax highlighting and language configuration: `#` / `/* */` comments, bracket
  matching, auto-closing.
- Snippets for `def`, `class`, `enum`, `interface`, `if`, `for`, `while`, `match`,
  `import`, `print`, and `main`.
- Build / run / test commands executed in the integrated terminal.
- Real LSP features through the bundled RGC analyzer (`rgc-analyzer`):
  - diagnostics on open/change (parse + semantic + borrow checks)
  - hover with symbol signatures
  - go-to-definition
  - document symbols
- Bilingual UI (English / 简体中文) via VS Code localization.

### Requirements

- VS Code 1.85 or newer.
- The analyzer is bundled in the official packages for `linux-x64`,
  `linux-arm64`, `darwin-x64`, `darwin-arm64`, `win32-x64`, and `win32-arm64`.
  Other platforms need `rgc-analyzer` on `PATH`.
- The `rgc` compiler on `PATH` for the build/run/test commands.

### Installation

From the [Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=rgc-dev.rgc-lang):

```bash
code --install-extension rgc-dev.rgc-lang
```

From [Open VSX](https://open-vsx.org/extension/rgc-dev/rgc-lang) (VSCodium, Gitpod,
Theia, code-server, Windsurf):

```bash
code --install-extension rgc-dev.rgc-lang
```

Or install the `.vsix` package from the
[latest GitHub release](https://github.com/rgc-lang/analyzer/releases): pick the
file matching your platform (`rgc-lang-linux-x64.vsix`, `rgc-lang-darwin-arm64.vsix`,
…). `rgc-lang-universal.vsix` contains no bundled analyzer and falls back to
`rgc-analyzer` on `PATH`.

### Quick start

Create a file named `hello.rg`:

```python
def main() {
    print("Hello, RGC!")
}
```

Open it in VS Code. Diagnostics, hover, and go-to-definition work out of the box
with the bundled analyzer. To compile and run (requires `rgc` on `PATH`):

1. Open the Command Palette (`Ctrl+Shift+P`).
2. Run **RGC: Run Current File** — or, from a terminal, `rgc run hello.rg`.

### Commands

| Command | Description |
| --- | --- |
| `RGC: Build Current File` | `rgc <file> -o <output>` |
| `RGC: Run Current File` | `rgc run <file> [args...]` |
| `RGC: Test Current File` | `rgc test <file>` |
| `RGC: Restart Language Server` | Restart the LSP connection |

### Configuration

| Setting | Default | Description |
| --- | --- | --- |
| `rgc.compilerPath` | `rgc` | Path to the `rgc` compiler executable. |
| `rgc.lsp.serverPath` | `rgc-analyzer` | Analyzer executable. The bundled `server/rgc-analyzer` is preferred when present, then `PATH`. |
| `rgc.lsp.serverArgs` | `[]` | Arguments passed to the analyzer. |
| `rgc.trace.server` | `off` | LSP trace level: `off`, `messages`, `verbose`. |

To use an analyzer installed elsewhere:

```json
{
  "rgc.lsp.serverPath": "/path/to/rgc-analyzer",
  "rgc.lsp.serverArgs": []
}
```

### Documentation

- [Language server contract](docs/lsp-server-contract.md)
- [Analyzer repository](https://github.com/rgc-lang/analyzer) — `rgc-analyzer`
  sources, build scripts, and the release workflows.

### Development

The extension lives in `editors/code` of the analyzer repository:

```bash
git clone https://github.com/rgc-lang/analyzer.git
cd analyzer/editors/code
npm install
npm run compile
```

Press **F5** to launch an Extension Development Host. Without a bundled server the
client falls back to `rgc-analyzer` on `PATH`. To bundle the analyzer into the
package, build it from the repository root:

```bash
node scripts/build-analyzer.js --out editors/code/server
```

To produce a `.vsix`:

```bash
npm run package   # -> rgc-lang.vsix
```

### License

Apache-2.0. The logo is generated for the RGC project.

---

## 中文

**RGC** 是一门 Python 风格、编译型、静态类型、带所有权/借用检查的语言，后端使用
LLVM。本扩展为 VS Code 提供完整的语言支持：语法高亮、代码片段、编译/运行/测试命令，
以及连接 RGC 分析器（官方安装包内置，或使用 `PATH` 中的 `rgc-analyzer`）的 LSP 客户端。

### 功能

- 语法高亮与语言配置：`#` / `/* */` 注释、括号匹配、自动闭合。
- 代码片段：`def`、`class`、`enum`、`interface`、`if`、`for`、`while`、
  `match`、`import`、`print`、`main`。
- 在集成终端中执行编译 / 运行 / 测试命令。
- 通过内置的 RGC 分析器（`rgc-analyzer`）提供真实 LSP 功能：
  - 打开/修改文件时推送诊断（语法 + 语义 + 借用检查）
  - 悬停查看符号签名
  - 跳转到定义
  - 文档符号
- 中英双语界面（通过 VS Code 本地化机制）。

### 环境要求

- VS Code 1.85 或更新版本。
- 官方安装包为 `linux-x64`、`linux-arm64`、`darwin-x64`、`darwin-arm64`、
  `win32-x64`、`win32-arm64` 内置分析器；其他平台需要 `PATH` 中的 `rgc-analyzer`。
- 编译/运行/测试命令需要 `PATH` 中的 `rgc` 编译器。

### 安装

从 [Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=rgc-dev.rgc-lang) 安装：

```bash
code --install-extension rgc-dev.rgc-lang
```

从 [Open VSX](https://open-vsx.org/extension/rgc-dev/rgc-lang) 安装（VSCodium、Gitpod、
Theia、code-server、Windsurf）：

```bash
code --install-extension rgc-dev.rgc-lang
```

或从 [GitHub 最新 Release](https://github.com/rgc-lang/analyzer/releases) 下载
`.vsix` 手动安装：选择与你平台匹配的文件（`rgc-lang-linux-x64.vsix`、
`rgc-lang-darwin-arm64.vsix` 等）。`rgc-lang-universal.vsix` 不含内置分析器，
会回退到 `PATH` 中的 `rgc-analyzer`。

### 快速开始

创建文件 `hello.rg`：

```python
def main() {
    print("Hello, RGC!")
}
```

在 VS Code 中打开它。内置分析器开箱即用，诊断、悬停和跳转定义即可工作。
编译并运行（需要 `PATH` 中的 `rgc`）：

1. 打开命令面板（`Ctrl+Shift+P`）。
2. 执行 **RGC: 运行当前文件**——或在终端中运行 `rgc run hello.rg`。

### 命令

| 命令 | 说明 |
| --- | --- |
| `RGC: 编译当前文件` | `rgc <file> -o <output>` |
| `RGC: 运行当前文件` | `rgc run <file> [args...]` |
| `RGC: 测试当前文件` | `rgc test <file>` |
| `RGC: 重启语言服务器` | 重启 LSP 连接 |

### 配置

| 配置项 | 默认值 | 说明 |
| --- | --- | --- |
| `rgc.compilerPath` | `rgc` | `rgc` 编译器可执行文件路径。 |
| `rgc.lsp.serverPath` | `rgc-analyzer` | 分析器可执行文件路径。存在内置 `server/rgc-analyzer` 时优先使用，否则从 `PATH` 查找。 |
| `rgc.lsp.serverArgs` | `[]` | 传给分析器的参数。 |
| `rgc.trace.server` | `off` | LSP 日志级别：`off`、`messages`、`verbose`。 |

若使用安装在别处的分析器：

```json
{
  "rgc.lsp.serverPath": "/path/to/rgc-analyzer",
  "rgc.lsp.serverArgs": []
}
```

### 文档

- [语言服务器契约](docs/lsp-server-contract.md)
- [分析器仓库](https://github.com/rgc-lang/analyzer)——`rgc-analyzer` 源码、
  构建脚本与发布工作流。

### 开发

扩展位于分析器仓库的 `editors/code` 目录：

```bash
git clone https://github.com/rgc-lang/analyzer.git
cd analyzer/editors/code
npm install
npm run compile
```

按 **F5** 启动扩展开发宿主。没有内置服务器时，客户端回退到 `PATH` 中的
`rgc-analyzer`。如需把分析器打进安装包，在仓库根目录构建：

```bash
node scripts/build-analyzer.js --out editors/code/server
```

打包为 `.vsix`：

```bash
npm run package   # -> rgc-lang.vsix
```

### 许可证

Apache-2.0。logo 为 RGC 项目生成。