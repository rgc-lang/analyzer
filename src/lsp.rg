# RGC analyzer: language server (LSP 3.x over stdio JSON-RPC)
#
# Shares the compiler frontend (lexer/parser/sema/module loading) copied from the
# rgc repository at build time; see scripts/build-analyzer.js. Provides:
#   - publishDiagnostics: full parse + sema (type/borrow checks) on didOpen/didChange
#   - textDocument/documentSymbol: top-level def/class/enum/interface (with class members)
#   - textDocument/hover: symbol signatures (current file + imported module files)
#   - textDocument/definition: jump to definition (current file + imported module files)
#
# Protocol layer: Content-Length framing plus a minimal built-in JSON parser/serializer
# (bootstrap constraint: compiler source cannot depend on lib/ standard-library modules).
# Document sync is full-file (TextDocumentSyncKind.Full); positions use byte columns (like
# diagnostics, so non-ASCII column numbers differ from the client's UTF-16 counting).

import util
import token
import ast
import lexer
import parser
import sema
import modules
import diag

# libc: fd reads and stdout writes. str parameters are passed as raw pointers (same as lib/net.rg).
# Writes use dprintf (fixed-arg call into a variadic function, SysV ABI compatible): ir.rg already declares
# @write as (i32, ptr, i64), while RGC's extern def int parameters are i64, so redeclaring would conflict.
extern def read(fd: int, buf: str, n: int) -> int
extern def dprintf(fd: int, fmt: str, s: str) -> int

# ---------------------------------------------------------------------------
# JSON values and parsing
# ---------------------------------------------------------------------------

public enum JKind {
    JNull
    JBool
    JNum
    JStr
    JArr
    JObj
}

public class JVal {
    kind: JKind
    b: bool
    n: int
    s: str
    keys: List[str]     # keys of JObj
    vals: List[JVal]    # values of JObj / elements of JArr
}

public def jv_null() -> JVal {
    v = JVal()
    v.kind = JNull()
    v.b = False
    v.n = 0
    v.s = ""
    v.keys = List[str]()
    v.vals = List[JVal]()
    return v
}

public def jv_is_null(v: @JVal) -> bool {
    return v.kind == JNull()
}

# Get a key from JObj; returns the JNull sentinel when missing.
public def jv_get(v: @JVal, key: str) -> JVal {
    if v.kind != JObj() {
        return jv_null()
    }
    i = 0
    while i < v.keys.len() {
        if str_eq(v.keys.get(i), key) {
            return v.vals.get(i)
        }
        i = i + 1
    }
    return jv_null()
}

# Get an index from JArr; returns the JNull sentinel when out of bounds.
public def jv_at(v: @JVal, idx: int) -> JVal {
    if v.kind != JArr() or idx < 0 or idx >= v.vals.len() {
        return jv_null()
    }
    return v.vals.get(idx)
}

public class JParser {
    s: str
    i: int
    ok: bool
}

public def make_jparser(s: str) -> JParser {
    p = JParser()
    p.s = s
    p.i = 0
    p.ok = True
    return p
}

public def jp_peek(p: @var JParser) -> int {
    if p.i < p.s.len() {
        return p.s.char_at(p.i)
    }
    return 0
}

public def jp_skip_ws(p: @var JParser) {
    while p.i < p.s.len() {
        c = p.s.char_at(p.i)
        if c == 32 or c == 9 or c == 10 or c == 13 {
            p.i = p.i + 1
        } else {
            break
        }
    }
}

public def jp_parse_value(p: @var JParser) -> JVal {
    jp_skip_ws(p)
    c = jp_peek(p)
    if c == 123 {           # {
        return jp_parse_obj(p)
    }
    if c == 91 {            # [
        return jp_parse_arr(p)
    }
    if c == 34 {            # "
        v = jv_null()
        v.kind = JStr()
        v.s = jp_parse_str(p)
        return v
    }
    if c == 116 {           # t
        p.i = p.i + 4
        v2 = jv_null()
        v2.kind = JBool()
        v2.b = True
        return v2
    }
    if c == 102 {           # f
        p.i = p.i + 5
        v3 = jv_null()
        v3.kind = JBool()
        v3.b = False
        return v3
    }
    if c == 110 {           # n
        p.i = p.i + 4
        return jv_null()
    }
    if c == 45 or (c >= 48 and c <= 57) {
        return jp_parse_num(p)
    }
    p.ok = False
    return jv_null()
}

public def jp_parse_obj(p: @var JParser) -> JVal {
    v = jv_null()
    v.kind = JObj()
    p.i = p.i + 1               # {
    jp_skip_ws(p)
    if jp_peek(p) == 125 {      # }
        p.i = p.i + 1
        return v
    }
    while p.ok {
        jp_skip_ws(p)
        k = jp_parse_str(p)
        jp_skip_ws(p)
        if jp_peek(p) != 58 {   # :
            p.ok = False
            break
        }
        p.i = p.i + 1
        val = jp_parse_value(p)
        v.keys.push(k)
        v.vals.push(val)
        jp_skip_ws(p)
        c = jp_peek(p)
        if c == 44 {            # ,
            p.i = p.i + 1
            continue
        }
        if c == 125 {           # }
            p.i = p.i + 1
            break
        }
        p.ok = False
    }
    return v
}

public def jp_parse_arr(p: @var JParser) -> JVal {
    v = jv_null()
    v.kind = JArr()
    p.i = p.i + 1               # [
    jp_skip_ws(p)
    if jp_peek(p) == 93 {       # ]
        p.i = p.i + 1
        return v
    }
    while p.ok {
        val = jp_parse_value(p)
        v.vals.push(val)
        jp_skip_ws(p)
        c = jp_peek(p)
        if c == 44 {            # ,
            p.i = p.i + 1
            continue
        }
        if c == 93 {            # ]
            p.i = p.i + 1
            break
        }
        p.ok = False
    }
    return v
}

public def jp_parse_str(p: @var JParser) -> str {
    if jp_peek(p) != 34 {
        p.ok = False
        return ""
    }
    p.i = p.i + 1
    out = ""
    while p.i < p.s.len() {
        c = p.s.char_at(p.i)
        if c == 34 {
            p.i = p.i + 1
            return out
        }
        if c == 92 {            # backslash
            p.i = p.i + 1
            e = jp_peek(p)
            if e == 110 {
                out = out + "\n"
                p.i = p.i + 1
            } elif e == 116 {
                out = out + "\t"
                p.i = p.i + 1
            } elif e == 114 {
                out = out + "\r"
                p.i = p.i + 1
            } elif e == 98 {
                out = out + chr(8)
                p.i = p.i + 1
            } elif e == 102 {
                out = out + chr(12)
                p.i = p.i + 1
            } elif e == 34 {
                out = out + "\""
                p.i = p.i + 1
            } elif e == 92 {
                out = out + "\\"
                p.i = p.i + 1
            } elif e == 47 {
                out = out + "/"
                p.i = p.i + 1
            } elif e == 117 {   # \uXXXX
                p.i = p.i + 1
                cp = jp_hex4(p)
                if cp >= 0xD800 and cp < 0xDC00 and jp_peek(p) == 92 {
                    # surrogate pair: \uD800-\uDBFF + \uDC00-\uDFFF
                    save = p.i
                    p.i = p.i + 1
                    if jp_peek(p) == 117 {
                        p.i = p.i + 1
                        lo = jp_hex4(p)
                        if lo >= 0xDC00 and lo < 0xE000 {
                            cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
                        } else {
                            p.i = save
                        }
                    } else {
                        p.i = save
                    }
                }
                if cp > 0 {
                    out = out + chr(cp)
                }
            } else {
                p.ok = False
                return out
            }
        } else {
            out = out + p.s.slice(p.i, p.i + 1)
            p.i = p.i + 1
        }
    }
    p.ok = False
    return out
}

public def jp_hex4(p: @var JParser) -> int {
    v = 0
    k = 0
    while k < 4 {
        c = jp_peek(p)
        d = -1
        if c >= 48 and c <= 57 {
            d = c - 48
        } elif c >= 97 and c <= 102 {
            d = c - 97 + 10
        } elif c >= 65 and c <= 70 {
            d = c - 65 + 10
        }
        if d < 0 {
            p.ok = False
            return v
        }
        v = v * 16 + d
        p.i = p.i + 1
        k = k + 1
    }
    return v
}

public def jp_parse_num(p: @var JParser) -> JVal {
    v = jv_null()
    v.kind = JNum()
    neg = False
    if jp_peek(p) == 45 {
        neg = True
        p.i = p.i + 1
    }
    n = 0
    while p.i < p.s.len() {
        c = p.s.char_at(p.i)
        if c >= 48 and c <= 57 {
            n = n * 10 + (c - 48)
            p.i = p.i + 1
        } else {
            break
        }
    }
    # Skip fractional/exponent parts (LSP ids are integers only; positions are integers too).
    if jp_peek(p) == 46 {
        p.i = p.i + 1
        while p.i < p.s.len() {
            c2 = p.s.char_at(p.i)
            if c2 >= 48 and c2 <= 57 {
                p.i = p.i + 1
            } else {
                break
            }
        }
    }
    if jp_peek(p) == 101 or jp_peek(p) == 69 {
        p.i = p.i + 1
        if jp_peek(p) == 43 or jp_peek(p) == 45 {
            p.i = p.i + 1
        }
        while p.i < p.s.len() {
            c3 = p.s.char_at(p.i)
            if c3 >= 48 and c3 <= 57 {
                p.i = p.i + 1
            } else {
                break
            }
        }
    }
    if neg {
        n = -n
    }
    v.n = n
    return v
}

# ---------------------------------------------------------------------------
# JSON serialization (only the shapes needed by responses)
# ---------------------------------------------------------------------------

public def jw_escape(s: str) -> str {
    out = "\""
    i = 0
    while i < s.len() {
        c = s.char_at(i)
        if c == 34 {
            out = out + "\\\""
        } elif c == 92 {
            out = out + "\\\\"
        } elif c == 10 {
            out = out + "\\n"
        } elif c == 9 {
            out = out + "\\t"
        } elif c == 13 {
            out = out + "\\r"
        } elif c < 32 {
            out = out + "\\u"
            h = "0123456789abcdef"
            out = out + "00" + h.slice((c // 16) + 1, (c // 16) + 2) + h.slice((c % 16) + 1, (c % 16) + 2)
        } else {
            out = out + s.slice(i, i + 1)
        }
        i = i + 1
    }
    return out + "\""
}

# ---------------------------------------------------------------------------
# stdio framing: read one Content-Length frame and return the message body; EOF returns ""
# ---------------------------------------------------------------------------

public class LspInput {
    pending: str
    eof: bool
}

public def make_lsp_input() -> LspInput {
    r = LspInput()
    r.pending = ""
    r.eof = False
    return r
}

# Read from stdin once, appending; returns whether data was read.
public def lsp_refill(r: @var LspInput) -> bool {
    if r.eof {
        return False
    }
    b = buf_alloc(8192)
    n = read(0, b, 8192)
    if n <= 0 {
        r.eof = True
        return False
    }
    r.pending = r.pending + buf_to_str(b, n)
    return True
}

# Ensure pending has at least n bytes; returns False when EOF and insufficient.
public def lsp_ensure(r: @var LspInput, n: int) -> bool {
    while r.pending.len() < n {
        if not lsp_refill(r) {
            return False
        }
    }
    return True
}

# Read a complete frame (headers + Content-Length body); returns the body text; EOF returns "".
public def lsp_read_frame(r: @var LspInput) -> str {
    # 1. the header terminator \r\n\r\n (pos points at the start of the 4-byte marker).
    hdr_end = -1
    while True {
        hdr_end = str_find(r.pending, "\r\n\r\n")
        if hdr_end >= 0 {
            break
        }
        if not lsp_refill(r) {
            return ""
        }
    }
    # 2. Content-Length。
    kpos = str_find(r.pending, "Content-Length:")
    if kpos < 0 or kpos > hdr_end {
        return ""
    }
    colon = kpos + "Content-Length:".len()
    num_start = colon
    while num_start < hdr_end and r.pending.char_at(num_start) == 32 {
        num_start = num_start + 1
    }
    num_end = num_start
    while num_end < hdr_end {
        c = r.pending.char_at(num_end)
        if c >= 48 and c <= 57 {
            num_end = num_end + 1
        } else {
            break
        }
    }
    if num_end == num_start {
        return ""
    }
    num_res = r.pending.slice(num_start, num_end).to_int()
    if num_res.is_err() {
        return ""
    }
    length = num_res.unwrap()
    # 3. the body.
    body_start = hdr_end + 4
    if not lsp_ensure(r, body_start + length) {
        return ""
    }
    body = r.pending.slice(body_start, body_start + length)
    r.pending = r.pending.slice(body_start + length, r.pending.len())
    return body
}

# Write to stdout verbatim (the LSP channel; print appends a newline so it is not used).
public def lsp_write_raw(s: str) {
    dprintf(1, "%s", s)
}

public def lsp_send(msg: str) {
    head = "Content-Length: " + to_string(msg.len()) + "\r\n\r\n"
    lsp_write_raw(head + msg)
}

# ---------------------------------------------------------------------------
# Symbol scanning: collect top-level definitions from the AST (signature / location / type)
# ---------------------------------------------------------------------------

public class LspSym {
    name: str
    detail: str          # "def f(a: int) -> int" / "class C : Show"
    kind: int            # LSP SymbolKind: 12 function, 5 class, 10 enum, 11 interface
    line: int            # 1-based
    col: int             # 1-based (first character of the name)
}

public def lsp_sym(name: str, detail: str, kind: int, line: int, col: int) -> LspSym {
    s = LspSym()
    s.name = name
    s.detail = detail
    s.kind = kind
    s.line = line
    s.col = col
    return s
}

# Render TypeExpr back to source form: int / Point / List[int] / @var T
public def lsp_ty_str(t: @TypeExpr) -> str {
    out = ""
    if t.is_borrow {
        if t.is_mut_borrow {
            out = "@var "
        } else {
            out = "@"
        }
    }
    out = out + t.name
    if t.args.len() > 0 {
        out = out + "["
        i = 0
        while i < t.args.len() {
            if i > 0 {
                out = out + ", "
            }
            ta = t.args.get(i)
            out = out + lsp_ty_str(@ta)
            i = i + 1
        }
        out = out + "]"
    }
    return out
}

# Function signature: "def name(a: int, b: str) -> int" (generic parameters are in type_params).
public def lsp_fn_detail(s: @Stmt) -> str {
    out = ""
    if s.is_public {
        out = "public "
    }
    if s.is_async {
        out = out + "async "
    }
    out = out + "def " + s.name
    if s.type_params.len() > 0 {
        out = out + "["
        i = 0
        while i < s.type_params.len() {
            if i > 0 {
                out = out + ", "
            }
            out = out + s.type_params.get(i)
            i = i + 1
        }
        out = out + "]"
    }
    out = out + "("
    i = 0
    while i < s.params.len() {
        if i > 0 {
            out = out + ", "
        }
        p = s.params.get(i)
        out = out + p.name
        if p.type.name.len() > 0 {
            pt = p.type
            out = out + ": " + lsp_ty_str(@pt)
        }
        i = i + 1
    }
    out = out + ")"
    if s.ret_type.name.len() > 0 {
        rt = s.ret_type
        out = out + " -> " + lsp_ty_str(@rt)
    }
    return out
}

# detail for classes / enums / interfaces.
public def lsp_type_detail(s: @Stmt) -> str {
    if s.kind == StmtClassDef() {
        out = "class " + s.name
        if s.type_params.len() > 0 {
            out = out + "[" + s.type_params.get(0)
            i = 1
            while i < s.type_params.len() {
                out = out + ", " + s.type_params.get(i)
                i = i + 1
            }
            out = out + "]"
        }
        if s.interfaces.len() > 0 {
            out = out + " : " + s.interfaces.get(0)
            i = 1
            while i < s.interfaces.len() {
                out = out + ", " + s.interfaces.get(i)
                i = i + 1
            }
        }
        return out
    }
    if s.kind == StmtEnumDef() {
        return "enum " + s.name
    }
    return "interface " + s.name
}

# Collect symbols from a statement list (top level; class methods/fields are collected as child symbols).
public def lsp_collect_syms(stmts: @List[Stmt], out: @var List[LspSym]) {
    i = 0
    while i < stmts.len() {
        s = stmts.get(i)
        if s.kind == StmtFnDef() {
            out.push(lsp_sym(s.name, lsp_fn_detail(@s), 12, s.line, s.col))
        } elif s.kind == StmtClassDef() {
            out.push(lsp_sym(s.name, lsp_type_detail(@s), 5, s.line, s.col))
            j = 0
            while j < s.methods.len() {
                m = s.methods.get(j)
                if m.kind == StmtFnDef() {
                    out.push(lsp_sym(m.name, lsp_fn_detail(@m), 12, m.line, m.col))
                }
                j = j + 1
            }
            j = 0
            while j < s.fields.len() {
                f = s.fields.get(j)
                ft = f.type
                d = f.name + ": " + lsp_ty_str(@ft)
                out.push(lsp_sym(f.name, d, 8, s.line, s.col))
                j = j + 1
            }
        } elif s.kind == StmtEnumDef() {
            out.push(lsp_sym(s.name, lsp_type_detail(@s), 10, s.line, s.col))
            j = 0
            while j < s.variants.len() {
                v = s.variants.get(j)
                out.push(lsp_sym(v.name, s.name + "." + v.name, 22, s.line, s.col))
                j = j + 1
            }
        } elif s.kind == StmtInterfaceDef() {
            out.push(lsp_sym(s.name, lsp_type_detail(@s), 11, s.line, s.col))
        }
        i = i + 1
    }
}

# Get the identifier at (line0, char0) in the file content (returns 1-based line/col).
public class LspWord {
    text: str
    line: int
    col: int
}

public def lsp_word_at(text: str, line0: int, char0: int) -> LspWord {
    w = LspWord()
    w.text = ""
    w.line = line0 + 1
    w.col = char0 + 1
    # found the line
    start = 0
    ln = 0
    while ln < line0 and start < text.len() {
        if text.char_at(start) == 10 {
            ln = ln + 1
        }
        start = start + 1
    }
    end = start
    while end < text.len() and text.char_at(end) != 10 {
        end = end + 1
    }
    # restrict to within the line
    if char0 > end - start {
        return w
    }
    lo = char0
    hi = char0
    while lo > 0 and lsp_is_ident_char(text.char_at(start + lo - 1)) {
        lo = lo - 1
    }
    while start + hi < end and lsp_is_ident_char(text.char_at(start + hi)) {
        hi = hi + 1
    }
    if hi <= lo {
        return w
    }
    w.text = text.slice(start + lo, start + hi)
    w.col = lo + 1
    return w
}

public def lsp_is_ident_char(c: int) -> bool {
    if c >= 48 and c <= 57 {
        return True
    }
    if c >= 97 and c <= 122 {
        return True
    }
    if c >= 65 and c <= 90 {
        return True
    }
    return c == 95
}

# URI -> local path: strip file:// and %XX escapes.
public def lsp_uri_to_path(uri: str) -> str {
    p = uri
    if p.startswith("file://") {
        p = p.slice(7, p.len())
    }
    out = ""
    i = 0
    while i < p.len() {
        c = p.char_at(i)
        if c == 37 and i + 2 < p.len() {
            hi = lsp_hex_val(p.char_at(i + 1))
            lo = lsp_hex_val(p.char_at(i + 2))
            if hi >= 0 and lo >= 0 {
                out = out + chr(hi * 16 + lo)
                i = i + 3
                continue
            }
        }
        out = out + p.slice(i, i + 1)
        i = i + 1
    }
    return out
}

public def lsp_hex_val(c: int) -> int {
    if c >= 48 and c <= 57 {
        return c - 48
    }
    if c >= 97 and c <= 102 {
        return c - 97 + 10
    }
    if c >= 65 and c <= 70 {
        return c - 65 + 10
    }
    return -1
}

# ---------------------------------------------------------------------------
# Document store (uri -> content; linear lookup over a parallel list)
# ---------------------------------------------------------------------------

public class LspDocs {
    uris: List[str]
    texts: List[str]
    paths: List[str]
}

public def make_lsp_docs() -> LspDocs {
    d = LspDocs()
    d.uris = List[str]()
    d.texts = List[str]()
    d.paths = List[str]()
    return d
}

public def lsp_docs_index(d: @LspDocs, uri: str) -> int {
    i = 0
    while i < d.uris.len() {
        if str_eq(d.uris.get(i), uri) {
            return i
        }
        i = i + 1
    }
    return -1
}

public def lsp_docs_put(d: @var LspDocs, uri: str, text: str) {
    idx = lsp_docs_index(d, uri)
    if idx >= 0 {
        d.texts.set(idx, text)
        return
    }
    d.uris.push(uri)
    d.texts.push(text)
    d.paths.push(lsp_uri_to_path(uri))
}

# ---------------------------------------------------------------------------
# Diagnostics: run the full frontend on the document and publish publishDiagnostics
# ---------------------------------------------------------------------------

# Parse the document (with module loading); on failure errs carries the loader's structured diagnostics.
public class LspParsed {
    stmts: List[Stmt]
    ok: bool
    errs: List[DiagItem]
}

public def lsp_parse(path: str, text: str) -> LspParsed {
    r = LspParsed()
    r.stmts = List[Stmt]()
    r.ok = False
    r.errs = List[DiagItem]()
    loader = make_module_loader(path)
    r.stmts = loader_load_entry(@var loader, text)
    if not loader.ok {
        i = 0
        while i < loader.err_items.len() {
            r.errs.push(loader.err_items.get(i))
            i = i + 1
        }
        return r
    }
    r.ok = True
    return r
}

# Collect diagnostics (1-based line/col + message; file resolved to a path). Duplicate entries at the same position are deduplicated.
public def lsp_diag_items(path: str, text: str, out: @var List[DiagItem]) {
    loader = make_module_loader(path)
    stmts = loader_load_entry(@var loader, text)
    if not loader.ok {
        i = 0
        while i < loader.err_items.len() {
            out.push(loader.err_items.get(i))
            i = i + 1
        }
        return
    }
    s = make_sema()
    s.diag_source_name = path
    s.diag_source = text
    sema_check_program(@var s, @stmts)
    i = 0
    while i < s.diag_items.len() {
        it = s.diag_items.get(i)
        if it.file.len() > 0 and loader.module_paths.contains(it.file) {
            it.file = loader.module_paths.get(it.file)
        } else {
            it.file = path
        }
        dup = False
        j = 0
        while j < out.len() {
            prev = out.get(j)
            if prev.line == it.line and prev.col == it.col and
               str_eq(prev.msg, it.msg) and str_eq(prev.file, it.file) {
                dup = True
            }
            j = j + 1
        }
        if not dup {
            out.push(it)
        }
        i = i + 1
    }
}

# Publish diagnostics for a single file (only entries with file == path; no entries clears them).
public def lsp_send_diagnostics(uri: str, path: str, items: @List[DiagItem]) {
    msg = "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/publishDiagnostics\",\"params\":{\"uri\":" +
          jw_escape(uri) + ",\"diagnostics\":["
    n = 0
    i = 0
    while i < items.len() {
        it = items.get(i)
        if not str_eq(it.file, path) {
            i = i + 1
            continue
        }
        if n > 0 {
            msg = msg + ","
        }
        n = n + 1
        ln = it.line - 1
        if ln < 0 {
            ln = 0
        }
        cl = it.col - 1
        if cl < 0 {
            cl = 0
        }
        pos = "{\"line\":" + to_string(ln) + ",\"character\":" + to_string(cl) + "}"
        msg = msg + "{\"range\":{\"start\":" + pos + ",\"end\":" + pos +
              "},\"severity\":1,\"source\":\"rgc\",\"message\":" + jw_escape(it.msg) + "}"
        i = i + 1
    }
    msg = msg + "]}}"
    lsp_send(msg)
}

# Diagnostic push: the main document is always published; module files involved in errors are pushed too,
# so the editor can see problems in unopened files.
public def lsp_publish_diagnostics(uri: str, path: str, text: str) {
    items = List[DiagItem]()
    lsp_diag_items(path, text, @var items)
    lsp_send_diagnostics(uri, path, @items)
    others = List[str]()
    i = 0
    while i < items.len() {
        f = items.get(i).file
        if f.len() > 0 and not str_eq(f, path) {
            seen = False
            j = 0
            while j < others.len() {
                if str_eq(others.get(j), f) {
                    seen = True
                }
                j = j + 1
            }
            if not seen {
                others.push(f)
                lsp_send_diagnostics("file://" + f, f, @items)
            }
        }
        i = i + 1
    }
}

# ---------------------------------------------------------------------------
# hover / definition / documentSymbol
# ---------------------------------------------------------------------------

# Symbol lookup result: detail + definition location (can cross files).
public class LspSymHit {
    found: bool
    detail: str
    path: str
    line: int
    col: int
    name_len: int
}

public def lsp_sym_hit() -> LspSymHit {
    h = LspSymHit()
    h.found = False
    h.detail = ""
    h.path = ""
    h.line = 0
    h.col = 0
    h.name_len = 0
    return h
}

# Find a name in the statement list; fills hit when found.
public def lsp_find_in_stmts(stmts: @List[Stmt], name: str, path: str, hit: @var LspSymHit) {
    if hit.found {
        return
    }
    syms = List[LspSym]()
    lsp_collect_syms(stmts, @var syms)
    i = 0
    while i < syms.len() {
        s = syms.get(i)
        if str_eq(s.name, name) {
            hit.found = True
            hit.detail = s.detail
            hit.path = path
            hit.line = s.line
            hit.col = s.col
            hit.name_len = s.name.len()
            return
        }
        i = i + 1
    }
}

# Global lookup: the current document plus module files it imports (read from disk).
public def lsp_lookup(docs: @LspDocs, idx: int, name: str) -> LspSymHit {
    hit = lsp_sym_hit()
    text = docs.texts.get(idx)
    path = docs.paths.get(idx)
    parsed = lsp_parse(path, text)
    if parsed.ok {
        psl = parsed.stmts
        lsp_find_in_stmts(@psl, name, path, @var hit)
    }
    if hit.found {
        return hit
    }
    # imported modules: <name>.rg in the same directory.
    dir_end = str_rfind(path, "/")
    dir = ""
    if dir_end >= 0 {
        dir = path.slice(0, dir_end + 1)
    }
    imp = List[str]()
    if parsed.ok {
        i = 0
        while i < parsed.stmts.len() {
            st = parsed.stmts.get(i)
            if st.kind == StmtImport() {
                imp.push(st.import_module)
            }
            i = i + 1
        }
    }
    i = 0
    while i < imp.len() and not hit.found {
        mpath = dir + imp.get(i) + ".rg"
        r = read_file(mpath)
        if r.is_ok() {
            mtext = r.unwrap()
            mparsed = lsp_parse(mpath, mtext)
            if mparsed.ok {
                mpsl = mparsed.stmts
                lsp_find_in_stmts(@mpsl, name, mpath, @var hit)
            }
        }
        i = i + 1
    }
    return hit
}

public def lsp_hover(docs: @LspDocs, idx: int, line0: int, char0: int) -> str {
    w = lsp_word_at(docs.texts.get(idx), line0, char0)
    if w.text.len() == 0 {
        return "null"
    }
    hit = lsp_lookup(docs, idx, w.text)
    if not hit.found {
        return "null"
    }
    return "{\"contents\":{\"kind\":\"markdown\",\"value\":\"```rg\\n" +
           jw_escape_inner(hit.detail) + "\\n```\"}}"
}

# Escape a string embedded in the hover JSON: escape backslashes and quotes (the outer layer does not wrap in quotes).
public def jw_escape_inner(s: str) -> str {
    out = ""
    i = 0
    while i < s.len() {
        c = s.char_at(i)
        if c == 34 {
            out = out + "\\\""
        } elif c == 92 {
            out = out + "\\\\"
        } else {
            out = out + s.slice(i, i + 1)
        }
        i = i + 1
    }
    return out
}

public def lsp_definition(docs: @LspDocs, idx: int, line0: int, char0: int) -> str {
    w = lsp_word_at(docs.texts.get(idx), line0, char0)
    if w.text.len() == 0 {
        return "null"
    }
    hit = lsp_lookup(docs, idx, w.text)
    if not hit.found {
        return "null"
    }
    end_char = hit.col - 1 + hit.name_len
    if end_char < hit.col {
        end_char = hit.col
    }
    return "{\"uri\":" + jw_escape("file://" + hit.path) +
           ",\"range\":{\"start\":{\"line\":" + to_string(hit.line - 1) +
           ",\"character\":" + to_string(hit.col - 1) +
           "},\"end\":{\"line\":" + to_string(hit.line - 1) +
           ",\"character\":" + to_string(end_char) + "}}}"
}

# ---------------------------------------------------------------------------
# Request dispatch and the main loop
# ---------------------------------------------------------------------------

public def lsp_pos(line0: int, char0: int) -> str {
    return "{\"line\":" + to_string(line0) + ",\"character\":" + to_string(char0) + "}"
}

# uri -> docs index; tries loading from disk when the document is not open.
public def lsp_docs_ensure(docs: @var LspDocs, uri: str) -> int {
    idx = lsp_docs_index(docs, uri)
    if idx >= 0 {
        return idx
    }
    path = lsp_uri_to_path(uri)
    r = read_file(path)
    if r.is_err() {
        return -1
    }
    lsp_docs_put(docs, uri, r.unwrap())
    return lsp_docs_index(docs, uri)
}

public def lsp_syms_json(stmts: @List[Stmt]) -> str {
    syms = List[LspSym]()
    lsp_collect_syms(stmts, @var syms)
    out = "["
    i = 0
    while i < syms.len() {
        if i > 0 {
            out = out + ","
        }
        s = syms.get(i)
        pos = lsp_pos(s.line - 1, s.col - 1)
        rng = "{\"start\":" + pos + ",\"end\":" + pos + "}"
        out = out + "{\"name\":" + jw_escape(s.name) +
              ",\"detail\":" + jw_escape(s.detail) +
              ",\"kind\":" + to_string(s.kind) +
              ",\"range\":" + rng + ",\"selectionRange\":" + rng + "}"
        i = i + 1
    }
    return out + "]"
}

# The document's current AST (returns ok=False when unopened or parse failed).
public def lsp_doc_symbols(docs: @var LspDocs, idx: int) -> str {
    text = docs.texts.get(idx)
    path = docs.paths.get(idx)
    parsed = lsp_parse(path, text)
    if not parsed.ok {
        return "[]"
    }
    psl = parsed.stmts
    return lsp_syms_json(@psl)
}

public def lsp_respond(id: @JVal, result: str) {
    id_str = "null"
    if id.kind == JNum() {
        id_str = to_string(id.n)
    } elif id.kind == JStr() {
        id_str = jw_escape(id.s)
    }
    lsp_send("{\"jsonrpc\":\"2.0\",\"id\":" + id_str + ",\"result\":" + result + "}")
}

public def lsp_error(id: @JVal, code: int, message: str) {
    id_str = "null"
    if id.kind == JNum() {
        id_str = to_string(id.n)
    } elif id.kind == JStr() {
        id_str = jw_escape(id.s)
    }
    lsp_send("{\"jsonrpc\":\"2.0\",\"id\":" + id_str + ",\"error\":{\"code\":" +
             to_string(code) + ",\"message\":" + jw_escape(message) + "}}")
}

# After didChange / didOpen, sync the document and push diagnostics.
public def lsp_apply_doc(docs: @var LspDocs, params: @JVal, text: str) {
    td = jv_get(params, "textDocument")
    uri_v = jv_get(@td, "uri")
    if uri_v.kind != JStr() {
        return
    }
    uri = uri_v.s
    lsp_docs_put(docs, uri, text)
    path = lsp_uri_to_path(uri)
    lsp_publish_diagnostics(uri, path, text)
}

public def lsp_run() -> int {
    docs = make_lsp_docs()
    inp = make_lsp_input()
    shutting_down = False
    while True {
        body = lsp_read_frame(@var inp)
        if body.len() == 0 {
            break
        }
        p = make_jparser(body)
        msg = jp_parse_value(@var p)
        if not p.ok or msg.kind != JObj() {
            continue
        }
        method_v = jv_get(@msg, "method")
        if method_v.kind != JStr() {
            continue
        }
        method = method_v.s
        id_v = jv_get(@msg, "id")
        is_req = not jv_is_null(@id_v)
        params = jv_get(@msg, "params")

        if str_eq(method, "initialize") {
            lsp_respond(@id_v, "{\"capabilities\":{\"textDocumentSync\":1," +
                              "\"hoverProvider\":true," +
                              "\"definitionProvider\":true," +
                              "\"documentSymbolProvider\":true}," +
                              "\"serverInfo\":{\"name\":\"rgc-analyzer\",\"version\":\"0.1.0\"}}")
        } elif str_eq(method, "initialized") {
            pass
        } elif str_eq(method, "shutdown") {
            shutting_down = True
            lsp_respond(@id_v, "null")
        } elif str_eq(method, "exit") {
            if shutting_down {
                return 0
            }
            return 1
        } elif str_eq(method, "textDocument/didOpen") {
            td = jv_get(@params, "textDocument")
            text_v = jv_get(@td, "text")
            if text_v.kind == JStr() {
                lsp_apply_doc(@var docs, @params, text_v.s)
            }
        } elif str_eq(method, "textDocument/didChange") {
            changes = jv_get(@params, "contentChanges")
            last = jv_at(@changes, changes.vals.len() - 1)
            text_v = jv_get(@last, "text")
            if text_v.kind == JStr() {
                lsp_apply_doc(@var docs, @params, text_v.s)
            }
        } elif str_eq(method, "textDocument/didClose") {
            td = jv_get(@params, "textDocument")
            uri_v = jv_get(@td, "uri")
            if uri_v.kind == JStr() {
                lsp_send("{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/publishDiagnostics\"," +
                         "\"params\":{\"uri\":" + jw_escape(uri_v.s) + ",\"diagnostics\":[]}}")
            }
        } elif str_eq(method, "textDocument/hover") {
            pos = jv_get(@params, "position")
            line0 = jv_get(@pos, "line").n
            char0 = jv_get(@pos, "character").n
            td = jv_get(@params, "textDocument")
            idx = -1
            if td.kind == JObj() {
                idx = lsp_docs_ensure(@var docs, jv_get(@td, "uri").s)
            }
            if idx < 0 {
                if is_req {
                    lsp_respond(@id_v, "null")
                }
            } else {
                lsp_respond(@id_v, lsp_hover(@docs, idx, line0, char0))
            }
        } elif str_eq(method, "textDocument/definition") {
            pos = jv_get(@params, "position")
            line0 = jv_get(@pos, "line").n
            char0 = jv_get(@pos, "character").n
            td = jv_get(@params, "textDocument")
            idx = -1
            if td.kind == JObj() {
                idx = lsp_docs_ensure(@var docs, jv_get(@td, "uri").s)
            }
            if idx < 0 {
                if is_req {
                    lsp_respond(@id_v, "null")
                }
            } else {
                lsp_respond(@id_v, lsp_definition(@docs, idx, line0, char0))
            }
        } elif str_eq(method, "textDocument/documentSymbol") {
            td = jv_get(@params, "textDocument")
            idx = -1
            if td.kind == JObj() {
                idx = lsp_docs_ensure(@var docs, jv_get(@td, "uri").s)
            }
            if idx < 0 {
                lsp_respond(@id_v, "[]")
            } else {
                lsp_respond(@id_v, lsp_doc_symbols(@var docs, idx))
            }
        } elif method.startswith("$") {
            pass
        } elif is_req {
            lsp_error(@id_v, -32601, "method not found: " + method)
        }
        pass
    }
    return 0
}
