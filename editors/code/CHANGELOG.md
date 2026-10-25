# Changelog

All notable changes to the RGC VS Code extension are documented here.

## 0.3.0

### Changed

- The language server now ships as the standalone `rgc-analyzer`, built and
  versioned in the [analyzer repository](https://github.com/rgc-lang/analyzer)
  together with this extension. The `rgc lsp` subcommand was removed from the
  compiler, mirroring rust-analyzer's separation from rustc.
- Official VSIX packages are built per platform (`linux-x64`, `linux-arm64`,
  `darwin-x64`, `darwin-arm64`, `win32-x64`, `win32-arm64`) and bundle
  `server/rgc-analyzer` plus `server/lib`. A universal package without a server
  is published for other platforms and falls back to `rgc-analyzer` on `PATH`.
- `rgc.lsp.serverPath` now defaults to `rgc-analyzer` (bundled server first,
  then `PATH`), and `rgc.lsp.serverArgs` defaults to `[]`.
- `rgc.compilerPath` still defaults to `rgc` on `PATH`; the compiler remains a
  separate toolchain used by the build/run/test commands.

## 0.2.0

### Added

- The RGC language server is implemented. Running `rgc lsp --stdio` now
  provides real LSP features through the bundled client:
  - Diagnostics on open/change (full-file parse plus semantic and borrow checks).
  - Document symbols for top-level `def` / `class` / `enum` / `interface`.
  - Hover with symbol signatures (current file and imported modules).
  - Go-to-definition across the current file and imported modules.
- The zero-dependency mock server remains available for wiring tests.

### Changed

- Display name is now `RGC`.

## 0.1.0

### Added

- `.rg` language registration and TextMate syntax highlighting.
- Language configuration: `#` / `/* */` comments, brackets, auto-closing.
- Snippets for functions, classes, enums, interfaces, control flow, imports, and
  printing.
- Commands: build, run, and test the current file with the `rgc` compiler.
- LSP client for the RGC-written language server over stdio.
- Bilingual UI (English / 简体中文).

### Notes

- The language server is **not bundled**; it is a separate executable, by
  default `rgc lsp --stdio`. Until it exists, syntax highlighting and the
  build/run/test commands remain available.
