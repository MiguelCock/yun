# tree-sitter grammars

Yun highlights code with [tree-sitter](https://github.com/tree-sitter/tree-sitter).
The runtime is vendored once; each language is a separate grammar library.

## Layout

Each grammar is a vendored C3L directory, `lib/tree_sitter_<name>.c3l/`:

```
lib/tree_sitter_<name>.c3l/
├── tree-sitter-<name>.c3i   # extern fn TSLanguage* tree_sitter_<name>();
├── manifest.json            # provides, linklib-dir, linked-libraries per target
├── grammar.conf             # src/queries/lib options for the build scripts
├── queries/highlights.scm   # bundled highlight query
├── README.md
├── LICENSE
├── linked-libs/<target>/libtree-sitter-<name>.a
└── upstream/                # pinned grammar source (git submodule)
```

The runtime lives in `lib/tree_sitter.c3l/` and is linked by every grammar
(`dependencies: ["tree_sitter"]`).

The `yun::language` registry (`src/language.c3`) lists each language (extensions,
grammar function, query paths); adding a grammar also means adding a registry
entry. See #151.

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
highlight query and license, generates the README/manifest/`grammar.conf`, and
inserts the dependency into `project.json` plus the import/enum/`LanguageSpec`
stub in `src/language.c3`. Then:

1. `scripts/build-tree-sitter.sh linux-x64 rust` — build the grammar library.
2. Review the `LanguageSpec` entry (fill `import_query` / `module_query` /
   `symbols_query` if the language has them).
3. `c3c build && c3c test`.

## Building

```sh
scripts/build-tree-sitter.sh [target] [grammar...]
```

- `target` defaults to `linux-x64`; `grammar...` filters by stem (`rust`, `c3`).
  With no filter, every `lib/tree_sitter_*.c3l` is built in one pass.
- The script compiles `parser.c` and, when present, `scanner.c` / `scanner.cc`
  (`$CXX` is used for `.cc`) into `linked-libs/<target>/lib<name>.a`.
- `grammar.conf` overrides `src`, `queries`, and `lib` when a grammar's sources
  live in a subdirectory (e.g. TypeScript's `typescript/src`) or its library
  name differs from the default.
- `macos-aarch64` / `windows-x64` need a matching toolchain; the Windows script
  (`scripts/build-tree-sitter-windows.ps1`) mirrors the same logic with MSVC.

Only `linux-x64` libraries are committed (CI is Linux-only). Other targets are
built on demand.

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
4. `c3c build && c3c test`; commit the regenerated `linked-libs`.

## Static vs lazy loading

**Decision: keep static linking for now** (see #152). Every grammar library is
linked into the executable, which is simple, offline, and needs no packaging
work. The measurements below set the point at which we revisit this.

Measured on the dev machine (`linux-x64`, 4 grammars):

| library | size |
| --- | --- |
| runtime | 309 KB |
| c3 | 1.15 MB |
| c | 636 KB |
| javascript | 443 KB |
| python | 526 KB |
| **grammar total** | **~2.7 MB** |

A clean `c3c build` takes ~1.8 s. Extrapolating to the ~24 grammars in the
umbrella (#161) gives roughly 15-20 MB of linked grammar code and a
correspondingly larger binary and link step.

If that becomes a problem, switch to loading grammars from shared libraries on
demand; the prototype and its risks are tracked in **#163**. Grammar `parser.c`
is self-contained (it exports `tree_sitter_<lang>()` and calls no runtime
symbols), so a shared grammar needs no exported runtime symbols.

## Licenses

Vendored grammars and the runtime keep their own licenses (`LICENSE` in each
C3L). The current set is MIT:

| grammar | upstream | pinned | license |
| --- | --- | --- | --- |
| tree_sitter (runtime) | tree-sitter/tree-sitter | `d97971e` | MIT |
| tree_sitter_c3 | c3lang/tree-sitter-c3 | `56d7388` | MIT |
| tree_sitter_c | tree-sitter/tree-sitter-c | `v0.24.2` | MIT |
| tree_sitter_javascript | tree-sitter/tree-sitter-javascript | `44c892e` | MIT |
| tree_sitter_python | tree-sitter/tree-sitter-python | `293fdc0` | MIT |

The scaffold copies the upstream license into the new C3L; add a row here.

## Checks

- `scripts/check-tree-sitter-grammars.sh` — every grammar C3L has a c3i,
  manifest, highlight query, README, LICENSE, and a `linux-x64` library. Runs in
  CI (`.github/workflows/ci.yml`).
- `scripts/check-tree-sitter-abi.sh` — grammar ABI vs the runtime.
