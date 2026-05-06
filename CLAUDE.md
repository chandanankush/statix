# Claude Code Instructions

## Before making any changes

Always read these two files first:

- **`AGENTS.md`** — codebase conventions, security rules, environment variable reference, and the PR checklist. Every rule here is mandatory.
- **`CONTRIBUTING.md`** — branch naming, commit message format, step-by-step guides for adding metrics, endpoints, and installer changes.

When a task touches `client/`, also read `client/README.md`. When it touches `server/`, also read `server/README.md`. When it touches both, read all three READMEs.

## Git Workflow

- **Never merge directly to `main`.** All merges to `main` must go through a pull request, no exceptions.
- Create feature branches for all non-trivial work following the naming in `CONTRIBUTING.md` (`feat/`, `fix/`, `docs/`, `chore/`).
- When work on a branch is ready, open a PR via `gh pr create` and stop — do not merge it yourself.
