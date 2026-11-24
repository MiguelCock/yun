# Git integration

Yun runs the system Git executable directly through argv arrays. It never builds a shell command and never stores credentials.

## Backend

`src/git/executor.c3` owns a worker thread and two channels. Each request is a command line, timeout, and output cap. The worker spawns the process with `ASYNC_OUTPUT`, drains stdout/stderr without blocking the UI, and returns a result that the main thread polls once per frame. Cancelling a request or stopping the worker terminates the process.

`src/git/repo.c3` builds the command lines:

```
git --no-pager --no-optional-locks -C <root> status \
  --porcelain=v2 -z --branch --untracked-files=all --renames
```

Status parsing is NUL-delimited. It handles branch headers (`branch.oid`, `branch.head`, `branch.upstream`, `branch.ab`) plus ordinary (`1`), rename/copy (`2`), unmerged (`u`), untracked (`?`), and ignored (`!`) records.

`src/git/state.c3` owns the per-project state. It debounces refreshes, coalesces requests, keeps the last good status on failure, and exposes stage/unstage/discard/commit/diff actions. Refreshes are triggered by project open, saves, file operations (`cards_revision`), window focus, explicit refresh, and a low-frequency fallback poll.

## UI

The Source Control panel (`Ctrl+Shift+G`) docks on the left and lists merge conflicts, staged changes, working-tree changes, and untracked files. Cards and browser rows receive a coloured status stripe/letter.

Click the branch row (or press `B`) to open the branch picker. It lists local branches with the current branch marked and the upstream shown; `Enter` switches, `N` creates a branch from the current HEAD, and `R` refreshes the list. Switching is blocked by Git when local changes would be overwritten and the error is shown in the panel.

Conflicted files appear under Merge Changes. Press `C` on a selected conflict to open the resolution view: `1`/`2`/`3` choose Current, Incoming, or Both, `S` saves and stages the resolved file, and `A` aborts the merge. The view shows the conflict labels and base text when available.

The remote bar provides Fetch, Pull, Push/Publish, and Sync. Fetch and Push use `git.default_remote`; Pull uses the branch upstream with `--ff-only`; Publish runs `git push -u <remote> <branch>` when no upstream exists; Sync runs Pull followed by Push. Remote commands set `credential.interactive=false` so Git cannot wait on a terminal prompt; credential helpers and SSH agents still work. Pull and Sync are disabled while editors have unsaved changes.

Diff commands use `--no-color --no-ext-diff --no-textconv`, so repository-configured diff drivers cannot execute. `src/git/diff.c3` parses unified diffs into hunks and typed lines; `src/git/diff_view.c3` renders inline and side-by-side modes. In the diff overlay, `[`/`]` select a hunk and `S`/`U` stage or unstage it. Hunk patches are written to a temporary file and applied with `git apply --cached` (or `--reverse` for staged diffs); the viewer refreshes after each action.

## Security

- Commands are argv arrays; no shell interpolation.
- `--no-optional-locks` keeps background status reads from refreshing the index.
- Diff commands disable external diff and textconv drivers.
- Credentials are never stored. Git's configured credential helper/SSH remains responsible for authentication.
- Error details are shown in the UI; remote URLs containing credentials are not persisted by Yun.

## Limits

- One repository per project (the nearest repository containing the project root).
- Nested repositories and submodules do not get separate status.
- Hunk staging and commit history are separate milestones.
- Untracked files are shown as added-file diffs via `git diff --no-index`.

## History

Press `H` in the Source Control panel to open recent history (or history for the selected file). The overlay lists commits with hash, date, and subject; the details pane shows author/date and changed files. `Tab` switches focus to the file list and `Enter` opens a per-file commit diff in the normal diff overlay. History is capped at 200 commits and 1000 changed files per commit.
