# RGC Analyzer

Language server for **RGC**, plus the official VS Code extension. The layout
mirrors [rust-analyzer](https://github.com/rust-lang/rust-analyzer): the analyzer
and the editor integration live in one repository.

```
src/                analyzer entry point + LSP implementation (RGC source)
editors/code/       VS Code extension (TypeScript)
scripts/            build and smoke-test scripts
.github/workflows/  CI and multi-platform release
rgc-version         pinned rgc toolchain tag (frontend + compiler)
```

## How it is built

The analyzer shares the compiler frontend with `rgc` and does **not** link LLVM.
`scripts/build-analyzer.js` resolves the import closure of the analyzer sources
against a checkout of the `rgc` repository, stages those modules into a flat
build directory, compiles `src/main.rg`, and assembles a relocatable server
directory:

```
server/rgc-analyzer       (rgc-analyzer.exe on Windows)
server/lib/               standard library modules used for analysis
```

Local build (uses `../rgc/src/src` automatically and `../rgc/build/rgc` when present):

```bash
node scripts/build-analyzer.js            # -> build/server/
node scripts/smoke-lsp.js                 # initialize/shutdown handshake
node scripts/build-analyzer.js --check    # validate the module closure only
```

To stage the server inside the extension for `vsce package`:

```bash
node scripts/build-analyzer.js --out editors/code/server
cd editors/code && npm ci && npm run package
```

## Multi-platform packaging

The release workflow builds one VSIX per platform (`linux-x64`, `linux-arm64`,
`darwin-x64`, `darwin-arm64`, `win32-x64`, `win32-arm64`), plus a universal
package without a bundled server. Each platform package contains
`server/rgc-analyzer` and `server/lib`; the universal package falls back to
`rgc-analyzer` on `PATH`.

`linux-armhf`, `alpine-*` and the web target are not built by `rgc` yet; those
users get the universal package.

## Development

```bash
cd editors/code
npm ci
npm run typecheck
npm run compile
npm run package
```

Press **F5** to launch an Extension Development Host. Without a bundled server
the client falls back to `rgc-analyzer` on `PATH`; `rgc.lsp.serverPath` and
`rgc.lsp.serverArgs` override both.

See [editors/code/README.md](editors/code/README.md) and the
[language server contract](editors/code/docs/lsp-server-contract.md).

## License

Apache-2.0.
