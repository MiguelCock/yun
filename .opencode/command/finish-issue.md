---
description: Verify, commit, push, and open a pull request for the current issue branch
agent: build
---
Finish the current issue branch. Argument: $ARGUMENTS, formatted as an issue-prefixed summary (e.g. `1 canvas foundation: camera + adaptive grid`).

Steps:
1. Run `c3c build`, `c3c test`, and `c3fmt --check` on changed files; fix failures and format with `c3fmt --in-place`.
2. Stage only the intended files and commit with message `#<issue> <summary>`.
3. `git push -u origin HEAD`.
4. Open a PR into `development` using the repo template, linking `Closes #<issue>`:
   `gh pr create --base development --title "#<issue> <summary>" --body-file <filled template>`
5. Report the PR URL and stop. **Do not merge the PR** — the maintainer reviews every PR before merging.

Follow the branch/PR workflow in CONTRIBUTING.md.
