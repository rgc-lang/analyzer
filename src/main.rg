# RGC analyzer entry point — language server over stdio (LSP 3.x).
#
# The analyzer shares the rgc compiler frontend: scripts/build-analyzer.js stages
# the compiler modules (lexer/parser/sema/...) next to this file before compiling.
#
# Usage:
#   rgc-analyzer [--stdio]     # run the language server
#   rgc-analyzer --version
#   rgc-analyzer --help

import lsp

def print_usage() {
    print("RGC analyzer — language server (LSP 3.x over stdio)")
    print("Usage: rgc-analyzer [--stdio]")
    print("       rgc-analyzer --version")
    print("       rgc-analyzer --help")
}

public def main() -> int {
    argv = args()
    i = 1
    while i < argv.len() {
        arg = argv.get(i)
        if str_eq(arg, "--help") or str_eq(arg, "-h") {
            print_usage()
            return 0
        }
        if str_eq(arg, "--version") or str_eq(arg, "-V") {
            print("rgc-analyzer 0.1.0")
            return 0
        }
        if not str_eq(arg, "--stdio") {
            write_stderr("error: unknown argument: " + arg + "\n")
            print_usage()
            return 1
        }
        i = i + 1
    }
    return lsp_run()
}
