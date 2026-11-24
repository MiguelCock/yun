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

Diff commands use `--no-color --no-ext-diff --no-textconv`, so repository-configured diff drivers cannot execute. `src/git/diff.c3` parses unified diffs into hunks and typed lines; `src/git/diff_view.c3` renders inline and side-by-side modes.

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
