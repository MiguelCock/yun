# Import arrows

Yun scans each card's file for its imports and draws an arrow from the card to
the card that defines each import. Imports that resolve inside the project get a
solid arrow; imports that resolve outside it (standard library, third-party
packages) get a dashed arrow labeled with the specifier.

## How it works

1. On project scan, each file is parsed with its language grammar and the
   language's `import_query` (see `src/language.c3`). Each `@path` capture is an
   import specifier; an optional `@fn`/`@kind` capture records which import form
   it is (`require`, `require_relative`, `include`, `@import`, `src`, `href`, …).
2. An **`ImportContext`** is built once per project (`src/imports.c3`). It reads
   the project manifests (see below) and captures the source roots and mappings
   used for resolution.
3. For each specifier, the resolver converts it to candidate paths, tries each
   source root (and the importing file's directory for relative imports), and
   resolves to the first candidate that is an existing project file.
4. If nothing matches, the import is **external**: the dashed arrow still shows
   where it is used, but not where it points.

Nothing outside the project is indexed, so standard-library and third-party
specifiers never resolve and stay external.

## Per-language resolution

| language | specifiers | roots / rules |
| --- | --- | --- |
| C3 | `module::path` | module name match, else path under `src/`, `.c3`/`.c3i` |
| C / C++ | `#include "x.h"` | file dir, then `include/`, `src/`, `inc/` (`<...>` is external) |
| Go | `import "pkg"` | strip the `go.mod` module prefix, then any `.go` in that dir |
| Rust | `mod x;`, `use a::b::C` | `mod` → `x.rs`/`x/mod.rs`; `use crate::a::b::C` → `src/a/b.rs`/`a/b/mod.rs` |
| Zig | `@import("x.zig")` | file dir / roots; `std` external |
| Odin | `import "x"` | directory package; `core:`/`vendor:` external |
| V | `import a.b` | dotted module → directory under the project |
| Nim | `import a/b` | file dir / roots; `std/…` external |
| Java | `import a.b.C;` | package → `src/main/java/a/b/C.java` (also `src/test/java`, `src/`) |
| Kotlin | `import a.b.C` | package → `src/main/kotlin/...`, `src/` |
| Scala | `import a.b.C` | package → `src/main/scala/...`, `src/` |
| C# | `using A.B;` | namespace → `A/B.cs` under the project / `src/` |
| TypeScript / TSX | `import ... from "x"` | relative + index, `tsconfig`/`jsconfig` `baseUrl` and `paths` aliases, `require()` |
| JavaScript | `import`/`require` | relative + index files |
| CSS | `@import "x.css"` | file dir / roots |
| HTML | `<script src>`, `<link href>` | file dir (only `src`/`href` attributes) |
| Lua | `require("a.b")` | file dir / roots → `a/b.lua`, `a/b/init.lua` |
| PHP | `use A\B;`, `require`/`include` | `composer.json` PSR-4 prefixes, else path under `src/` |
| Ruby | `require`, `require_relative` | relative for `require_relative`; `lib/`, project root for `require` |
| R | `source("x.R")` | file dir |
| Julia | `include("x.jl")`, `using A` | relative for `include`; package/file for `using` |
| Haskell | `import A.B` | module → `src/A/B.hs` (`hs-source-dirs` from the `.cabal`, plus `app/`, `test/`) |
| Gleam | `import a/b` | `src/a/b.gleam`; `gleam/*` external |
| Erlang | `-include("x.hrl")` | file dir, `include/` (`-include_lib` external) |
| Elixir | `alias`/`import`/`require A.B` | module → snake_case path under `lib/` |
| Dart | `import 'x.dart'`, `package:n/…` | relative; `package:` → `lib/…` using `pubspec.yaml` `name` |

### Manifest readers

`ImportContext` reads, best-effort, from the project root:

- `go.mod` (`module …`) — Go module prefix.
- `Cargo.toml` (`name = …`) — Rust crate name.
- `tsconfig.json` / `jsconfig.json` (`baseUrl`, `paths`) — TypeScript aliases.
- `composer.json` (`autoload.psr-4`) — PHP namespaces.
- `pubspec.yaml` (`name`) — Dart package name.
- `mix.exs` (`app: :name`) — Elixir app (informational).
- `*.cabal` (`hs-source-dirs`) — Haskell source roots.

When a manifest is missing or unreadable, resolution falls back to the
conventional roots above and relative paths.

## Extending a language

1. Add an `import_query` to its `LanguageSpec` in `src/language.c3` capturing the
   specifier as `@path` (and `@fn`/`@kind` when the import form matters).
2. Add a resolution case in `resolve_import` (`src/imports.c3`) using the shared
   helpers (`try_base`, `try_root`, `try_roots`, `try_module_drop`,
   `any_file_under`, `replace_seps`, `snake_path`).
3. Add a `symbols_query` if the language should feed the symbol palette.
4. Add a fixture case to `fixtures/imports/` and a `FixtureCase` entry in
   `test/imports_test.c3`.

## Code fence / mini project

`fixtures/imports/` is a small project with one example per language (and the
real manifests). It is used by `test/imports_test.c3` and
`test/symbols_test.c3`, and can be opened in Yun to see arrows resolve across
every language. It is listed in `.gitignore` (so it does not clutter the Yun
repo's own canvas) but committed with `git add -f`.

## Configuration

The `arrows` section of the settings/config controls rendering and scanning:
`enabled`, `show_internal`, `show_external`, `labels`, `line_thickness`,
`hover_thickness`, `arrowhead_size`, `hit_tolerance`, `rescan_debounce`, and
`scan_workers`. Resolution runs on a thread pool; edits are debounced and only
the edited file is re-resolved unless a module name changed.
