# tree-sitter grammars

Yun highlights code with [tree-sitter](https://github.com/tree-sitter/tree-sitter).
The runtime is vendored once and linked into the executable; each language is a
separate grammar library that is **loaded lazily at runtime** from a shared
library (`.so`/`.dylib`/`.dll`).

## Layout

Each grammar is a vendored C3L directory, `lib/tree_sitter_<name>.c3l/`:

```
lib/tree_sitter_<name>.c3l/
├── tree-sitter-<name>.c3i   # extern fn TSLanguage* tree_sitter_<name>(); (static builds)
├── manifest.json            # provides, linklib-dir, linked-libraries per target (static builds)
├── grammar.conf             # src/queries/lib options for the build scripts
├── queries/highlights.scm   # bundled highlight query
├── queries/injections.scm   # optional embedded-language query
├── README.md
├── LICENSE
├── linked-libs/<target>/    # built artifacts (not committed)
└── upstream/                # pinned grammar source (git submodule)
```

The runtime lives in `lib/tree_sitter.c3l/` and is linked statically
(`dependencies: ["tree_sitter"]`). Grammar libraries are **not** committed; build
them with the script below.

The `yun::language` registry (`src/language.c3`) lists each language (extensions,
library name, symbol, query paths). See #151.

## Adding a grammar

Use the scaffold (run from the repo root):

```sh
scripts/add-tree-sitter-grammar.sh rust \
    --url https://github.com/tree-sitter/tree-sitter-rust \
    --module tree_sitter_rust --function tree_sitter_rust \
    --extensions .rs --rev v0.24.0
```

Options:

| flag | meaning |
| --- | --- |
| `--url` | upstream git URL (added as a submodule at `upstream/`) |
| `--module` / `--function` | C3 module name and the exported `TSLanguage*` symbol |
| `--extensions` | comma-separated file extensions for the registry entry |
| `--rev` | tag/commit to pin the submodule to |
| `--src` | source subdirectory inside upstream (default `src`) |
| `--queries` | queries subdirectory inside upstream (default `queries`) |
| `--license` | license file to copy (default: upstream `LICENSE`) |

It creates the C3L directory, registers the submodule (`.gitmodules`), copies the
highlight (and, when present, injections) query and license, generates the
README/manifest/`grammar.conf`, and adds the enum member + `LanguageSpec` stub
(`lib`/`symbol`/`injections_path`) in `src/language.c3`. Then:

1. `scripts/build-tree-sitter.sh linux-x64 rust` — build the shared library.
2. Review the `LanguageSpec` entry (fill `import_query` / `module_query` /
   `symbols_query` if the language has them).
3. `c3c build && c3c test`.

## Building

```sh
scripts/build-tree-sitter.sh [--static] [target] [grammar...]
```

- The runtime is always built as a static library (`.a`, linked into the
  executable). Grammars build as shared libraries by default; `--static` builds
  grammar `.a` libraries for static linking instead.
- `target` defaults to `linux-x64`; `grammar...` filters by stem (`rust`, `c3`).
  With no filter, every `lib/tree_sitter_*.c3l` is built in one pass.
- The script compiles `parser.c` and, when present, `scanner.c` / `scanner.cc`
  (`$CXX` is used for `.cc`) into `linked-libs/<target>/`.
- `grammar.conf` overrides `src`, `queries`, and `lib` when a grammar's sources
  live in a subdirectory (e.g. TypeScript's `typescript/src`) or its library
  name differs from the default.
- `macos-aarch64` / `windows-x64` need a matching toolchain; the Windows script
  (`scripts/build-tree-sitter-windows.ps1`) mirrors the same logic with MSVC
  (`-Static` for static libraries).

Because nothing is committed, run the script after cloning (and in CI) before
`c3c test`:

```sh
scripts/build-tree-sitter.sh linux-x64
c3c test
```

## Lazy loading

`yun::grammar` (`src/grammar.c3`) loads a grammar the first time a file of that
language is opened, caches the `TSLanguage*`, and returns null (plain text) if the
library or symbol is missing. The registry stores the library base name and the
exported symbol; `language::grammar_language` caches per language.

Search order for `libtree-sitter-<stem>.so`:

1. `$YUN_GRAMMAR_DIR` (if set)
2. `<exe dir>/grammars/`
3. `<exe dir>/`
4. `lib/tree_sitter_<stem>.c3l/linked-libs/<target>/` (development, relative to CWD)

Loaders: `dlopen`/`dlsym` on POSIX, `LoadLibraryA`/`GetProcAddress` on Windows.
The Linux path is verified; macOS and Windows are best-effort. Grammar `parser.c`
is self-contained (it exports `tree_sitter_<lang>()` and calls no runtime
symbols), so a shared grammar needs no exported runtime symbols.

Release archives bundle the shared libraries in a `grammars/` directory next to
the executable (see `.github/workflows/release.yml`); set `YUN_GRAMMAR_DIR` to
override the search location.

## Language ABI

Each generated `parser.c` declares `LANGUAGE_VERSION`. The runtime declares
`TREE_SITTER_LANGUAGE_VERSION` and `TREE_SITTER_MIN_COMPATIBLE_LANGUAGE_VERSION`.
A grammar must satisfy `min <= grammar <= runtime`.

```sh
scripts/check-tree-sitter-abi.sh
```

**Bumping the runtime** (when a grammar needs a newer ABI):

1. Update the runtime submodule: `git -C lib/tree_sitter.c3l/upstream fetch` then
   check out the newer tag/commit and `git add lib/tree_sitter.c3l/upstream`.
2. Rebuild the runtime and every grammar: `scripts/build-tree-sitter.sh linux-x64`.
3. `scripts/check-tree-sitter-abi.sh` — all grammars must report `ok`.
4. `c3c build && c3c test`.

## Static vs lazy loading

**Decision: load grammars lazily from shared libraries** (implemented in #163).
Static linking remains available via `scripts/build-tree-sitter.sh --static` plus
re-adding the grammar entries to `project.json` dependencies.

Measured on the dev machine (`linux-x64`, 4 grammars):

| | static | lazy |
| --- | --- | --- |
| executable | 8.22 MB (text 6.43 MB) | 5.56 MB (text 3.79 MB) |
| grammar code | linked into the exe | ~2.7 MB of shared libraries |
| first grammar load | — | ~40 µs (`dlopen` + `dlsym`) |

Lazy loading keeps the executable ~2.7 MB smaller and avoids loading grammars for
languages a session never opens; startup is dominated by raylib/GL init either
way. The tradeoff is that the shared libraries must be built (CI does this) and
shipped alongside the binary.

## Licenses

Vendored grammars and the runtime keep their own licenses (`LICENSE` in each
C3L). Most are MIT; the Nim grammar is MPL-2.0.

| grammar | upstream | pinned | license |
| --- | --- | --- | --- |
| tree_sitter (runtime) | tree-sitter/tree-sitter | `d97971e` | MIT |
| tree_sitter_c3 | c3lang/tree-sitter-c3 | `56d7388` | MIT |
| tree_sitter_c | tree-sitter/tree-sitter-c | `v0.24.2` | MIT |
| tree_sitter_c_sharp | tree-sitter/tree-sitter-c-sharp | `v0.23.5` | MIT |
| tree_sitter_cpp | tree-sitter/tree-sitter-cpp | `v0.23.4` | MIT |
| tree_sitter_css | tree-sitter/tree-sitter-css | `v0.25.0` | MIT |
| tree_sitter_go | tree-sitter/tree-sitter-go | `v0.25.0` | MIT |
| tree_sitter_html | tree-sitter/tree-sitter-html | `v0.23.2` | MIT |
| tree_sitter_java | tree-sitter/tree-sitter-java | `v0.23.5` | MIT |
| tree_sitter_javascript | tree-sitter/tree-sitter-javascript | `44c892e` | MIT |
| tree_sitter_julia | tree-sitter/tree-sitter-julia | `v0.25.0` | MIT |
| tree_sitter_kotlin | fwcd/tree-sitter-kotlin | `0.3.8` | MIT |
| tree_sitter_lua | tree-sitter-grammars/tree-sitter-lua | `v0.5.0` | MIT |
| tree_sitter_nim | alaviss/tree-sitter-nim | `0.6.2` | MPL-2.0 |
| tree_sitter_odin | tree-sitter-grammars/tree-sitter-odin | `v1.3.0` | MIT |
| tree_sitter_php | tree-sitter/tree-sitter-php | `v0.25.0` | MIT |
| tree_sitter_python | tree-sitter/tree-sitter-python | `293fdc0` | MIT |
| tree_sitter_r | r-lib/tree-sitter-r | `v1.3.0` | MIT |
| tree_sitter_ruby | tree-sitter/tree-sitter-ruby | `v0.23.1` | MIT |
| tree_sitter_rust | tree-sitter/tree-sitter-rust | `v0.24.2` | MIT |
| tree_sitter_scala | tree-sitter/tree-sitter-scala | `v0.26.2` | MIT |
| tree_sitter_tsx | tree-sitter/tree-sitter-typescript | `v0.23.2` | MIT |
| tree_sitter_typescript | tree-sitter/tree-sitter-typescript | `v0.23.2` | MIT |
| tree_sitter_v | nedpals/tree-sitter-v | `fee18d64a5` | MIT |
| tree_sitter_zig | tree-sitter-grammars/tree-sitter-zig | `v1.1.2` | MIT |

The scaffold copies the upstream license into the new C3L; add a row here.

### Inherited queries

A grammar's `queries/highlights.scm` may begin with `; inherits: <lang>[,<lang>]`
(e.g. C++ inherits C). `yun::highlight` resolves each name via the registry and
prepends the parent query before compiling, so inherited captures apply. The
C++ vendored query carries this directive even though the upstream 0.23.4 tree
declares the inheritance in `tree-sitter.json` instead.

### Injections

A grammar may ship `queries/injections.scm` to highlight embedded languages
(PHP's HTML body, HTML `<script>`/`<style>`, C++ raw string literals, JavaScript
tagged templates, ...). When a language's `injections_path` is set,
`yun::highlight` runs the query and re-parses each `@injection.content` capture
with the injected grammar, merging the resulting spans into the parent buffer
(nested/inner spans win). `LanguageSpec.injections_path` is empty for grammars
without one.

Supported query features:

- **Static language**: `(#set! injection.language "html")`.
- **Dynamic language**: a capture named `@injection.language` (or a `#set!`
  value that is a capture). The capture text is resolved through
  `language::language_for_name` with aliases (`js`→javascript, `ts`→typescript,
  `sh`/`md`/`regex`/`comment`/... resolve to nothing). Unresolved names fall back
  to plain text.
- **Combined**: `(#set! injection.combined)` concatenates a pattern's content
  fragments into one parse and maps spans back to the original ranges.
- **Predicates**: `#eq?`, `#not-eq?`, `#any-of?`, `#not-any-of?` are evaluated
  (used by Lua's `cdef` and Julia's prefixed strings); `#set!` is treated as a
  property, and any other predicate (`#offset!`, `#match?`) makes the match be
  skipped rather than mis-inject.
- `(#set! injection.include-children)` needs no handling: the content node's
  byte range already includes its children.

Injections recurse with a depth limit of 3 and reuse a cached parser per
language. Rust's self-injection (`macro token_tree → rust`) is intentionally not
enabled; a few upstream rules resolve to languages that are not vendored yet
(`markdown`, `sql`, `regex`, `comment`, ...) and are therefore no-ops. PHP's
vendored `injections.scm` adds a Yun-specific `(text) → html` rule because the
PHP grammar exposes markup outside `<?php ?>` as a single opaque `(text)` node.

## Checks

- `scripts/check-tree-sitter-grammars.sh` — every grammar C3L has a c3i,
  manifest, highlight query, README, and LICENSE. Runs in CI
  (`.github/workflows/ci.yml`).
- `scripts/check-tree-sitter-abi.sh` — grammar ABI vs the runtime.
