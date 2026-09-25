---
description: Create a feature branch for a GitHub issue and restate its acceptance criteria
agent: build
---
Create a feature branch for issue $ARGUMENTS.

Steps:
1. `git checkout development && git pull --ff-only`
2. Read the issue (`gh issue view $ARGUMENTS`) and derive a short kebab-case slug from its title.
3. `git checkout -b $ARGUMENTS-<slug>`.
4. Report the branch name and restate the issue's acceptance criteria and task list.

Follow the branch/PR workflow in CONTRIBUTING.md.
