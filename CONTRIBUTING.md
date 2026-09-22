# Contributing to Yun

## Branching model
- `main` is release-ready; only integrated, verified work lands here.
- `development` is the integration branch. All feature work targets it.
- Feature branches are named `<issue>-<slug>` (e.g. `1-canvas-foundation`) and branch off an up-to-date `development`.

Flow:

```
main  <-  (release PR)  <-  development  <-  (squash PR)  <-  <issue>-<slug>
```

## Commit convention
Prefix every commit with the issue number:

```
#1 canvas foundation: camera + adaptive grid
```

## Pull requests
1. Branch off `development` (see the `start-issue` opencode command).
2. Implement against the issue's acceptance criteria; keep its task checklist updated.
3. Verify locally (below).
4. Push and open a PR into `development` using the template; link `Closes #N`.
5. Stop at the open PR. The maintainer reviews it (with CI green) and merges with **Squash and merge**, then deletes the branch. Agents must never merge a PR themselves.

Merging a PR auto-closes any issue referenced with a closing keyword in the PR body (`Closes #N`, `Fixes #N`, `Resolves #N`) via `.github/workflows/close-linked-issues.yml`, since feature PRs merge into `development` rather than the default branch.

The `start-issue` and `finish-issue` opencode commands automate steps 1 and 3-4.

## Verify before pushing
```
c3c build
c3c test
c3fmt --check $(git ls-files '*.c3')
```
CI runs the same checks on every pull request.

## Setup
- C3 compiler `c3c` 0.8.4 or newer; `c3fmt` ships alongside it. CI pins 0.8.4.
- Always clone with submodules, or initialize them in an existing clone:
```
git clone --recurse-submodules https://github.com/MiguelCock/yun.git
git submodule update --init --recursive
```
Submodules include `lib/lua54.c3l` and the tree-sitter `upstream/` sources under `lib/tree_sitter*.c3l/`.
- Build/link needs no submodules (prebuilt `linux-x64` static libs are committed), but rebuilding them or targeting another platform uses `scripts/build-tree-sitter.sh <target>`.
- Lua mods (#33+) will additionally require a system Lua 5.4 (e.g. `liblua5.4-dev`).

## Ground rules
- Do not hand-edit vendored libraries (`lib/*.c3l`, `lib/lua54.c3l`); they are packed or submodules.
- Keep a successful `c3c build` free of `no-unused` warnings.
- Match the C3 style in `.opencode/skills/yun-development/SKILL.md`.

## License
Yun is MIT-licensed (see [`LICENSE`](LICENSE)): use it freely, but any copy or fork must retain the copyright and license notice. By contributing you agree your changes are licensed under the same terms. Vendored libraries and assets keep their own licenses.

