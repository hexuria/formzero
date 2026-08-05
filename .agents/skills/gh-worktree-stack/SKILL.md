---
name: gh-worktree-stack
description: Orchestrate multiple agent-owned Git worktrees as a linear GitHub stacked-PR dependency chain with one stack steward, safe bottom-up rebasing, focused layer ownership, CI verification, and controlled landing. Use only when explicitly invoked as $gh-worktree-stack or when the user explicitly asks to coordinate multiple agents or worktrees as dependent stacked pull requests. Do not use for ordinary app development, one PR, or independent parallel branches.
---

# GitHub Worktree Stack

Coordinate dependent agent work without loading stack procedures into ordinary coding tasks.

Before changing branches or GitHub state, read the installed `gh-stack` skill completely. Read [worktree-protocol.md](references/worktree-protocol.md) before creating worktrees, rebasing any layer, linking PRs, or merging.

## Decide whether to stack

- Stack only changes that must land in order because an upper layer depends on a lower layer.
- Give each layer one reviewable concern describable in one sentence.
- Use sibling PRs or separate stacks for independent work. Parallel execution alone is not a reason to stack.
- Put foundations below consumers: model/schema, domain/persistence, application wiring, UI, then integration verification.

Stop and report the proposed layer order before creating branches when the dependency direction is ambiguous.

## Assign ownership

Assign one **stack steward** and one branch/worktree per worker agent.

The steward owns:

- the bottom-to-top layer plan;
- worktree and branch creation;
- ancestry and clean-state checks;
- `gh stack link`, PR bases, CI status, and merging;
- pausing workers before any history rewrite.

Each worker owns only its assigned branch, worktree, and concern. A worker must not run stack-wide `rebase`, `sync`, `push`, `submit`, `modify`, or merge operations.

Maintain a live coordination table in the task commentary:

| Layer | Branch | Parent | Worktree | Owner | Scope | Commit | State |
|---|---|---|---|---|---|---|---|

## Inspect before acting

Run read-only checks first:

```sh
git status --short --branch
git worktree list --porcelain
git remote -v
gh auth status
gh extension list
```

Require `gh stack` and configure the repository once:

```sh
gh extension install github/gh-stack
git config rerere.enabled true
git config remote.pushDefault origin
```

## Execute the stack

1. Plan branch names as `codex/<topic>/<nn>-<concern>`.
2. Create the bottom worktree from the current `origin/main`.
3. Let the bottom worker reach a committed checkpoint before creating its dependent child worktree from that branch.
4. Repeat upward only from stable parent checkpoints.
5. Require every worker handoff to include commit SHA, tests run, dirty status, and dependency changes.
6. Verify every parent is an ancestor of its child.
7. Link branches bottom-to-top using `gh stack link --base main --remote origin ...`. This is the worktree-safe path because it does not depend on local `.git/gh-stack` tracking.
8. Keep new PRs draft unless the user explicitly asks to open them for review.

## Handle lower-layer changes

Freeze the affected workers. Require clean, committed worktrees. Push the corrected lower layer, then rebase each child inside its own worktree onto the updated remote parent, proceeding bottom-to-top. Stop at the first conflict, resolve and test that layer, then continue upward.

Do not run cascading `gh stack rebase` or `gh stack sync` while stack branches are checked out in separate worktrees. Do not use GitHub's server-side Rebase Stack while workers are active; it changes remote branch tips and leaves their worktrees stale.

## Review and land

- Review each layer against its immediate parent, not against `main`.
- Require fresh CI after the final history rewrite for every layer being merged.
- Merge only a contiguous bottom-up portion. Merging the top PR lands the whole stack below it.
- After a partial merge, reconcile remaining worktrees before workers resume.
- Never delete a worktree until its changes are merged or otherwise preserved and its exact path is verified.

Finish with the stack order, PR links, CI status, merge scope, and any worktrees that remain active.
