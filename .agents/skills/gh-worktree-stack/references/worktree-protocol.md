# Worktree stack protocol

Use these commands only after the core skill has selected a genuinely dependent stack.

## Contents

- [Create the worktrees](#create-the-worktrees)
- [Worker handoff](#worker-handoff)
- [Link the pull requests](#link-the-pull-requests)
- [Cascade a lower-layer update](#cascade-a-lower-layer-update)
- [Verify and merge](#verify-and-merge)
- [Recovery](#recovery)

## Create the worktrees

Choose explicit absolute paths outside the primary checkout. Example three-layer stack:

```sh
git fetch origin

git worktree add \
  -b codex/<topic>/01-model \
  /absolute/path/<repo>-<topic>-01-model \
  origin/main
```

After layer 1 has a stable commit:

```sh
git worktree add \
  -b codex/<topic>/02-domain \
  /absolute/path/<repo>-<topic>-02-domain \
  codex/<topic>/01-model
```

After layer 2 has a stable commit:

```sh
git worktree add \
  -b codex/<topic>/03-ui \
  /absolute/path/<repo>-<topic>-03-ui \
  codex/<topic>/02-domain
```

Never point two workers at the same branch or worktree.

## Worker handoff

Workers commit and push only their branch:

```sh
git status --short --branch
git push -u origin codex/<topic>/<layer>
git rev-parse HEAD
```

Handoff must report:

- exact branch and worktree;
- commit SHA;
- files and concern owned;
- tests and checks run;
- clean or dirty state;
- any changed contract consumed by an upper layer.

## Link the pull requests

From the steward worktree, verify ancestry pairwise:

```sh
git fetch origin
git merge-base --is-ancestor \
  origin/codex/<topic>/01-model \
  origin/codex/<topic>/02-domain
git merge-base --is-ancestor \
  origin/codex/<topic>/02-domain \
  origin/codex/<topic>/03-ui
```

An exit status other than zero means the chain is not linear. Do not link or merge it.

Create draft PRs and link the stack bottom-to-top:

```sh
gh stack link \
  --base main \
  --remote origin \
  codex/<topic>/01-model \
  codex/<topic>/02-domain \
  codex/<topic>/03-ui
```

Add `--open` only when the user wants every newly linked PR ready for review. Edit generated PR titles and bodies afterward when necessary.

`gh stack link` intentionally writes no local stack-tracking state. Do not expect `gh stack up`, `down`, `top`, or `bottom` navigation to work.

## Cascade a lower-layer update

Pause every affected worker and require a clean checkpoint. After the parent is updated and pushed, rebase the immediate child in the child's own worktree:

```sh
git fetch origin
git rebase origin/codex/<topic>/<parent-layer>
git push --force-with-lease origin codex/<topic>/<current-layer>
```

Repeat in the next child's worktree, always bottom-to-top. Never skip a layer. Run that layer's relevant tests before proceeding.

After all layers move, rerun the ancestry checks and `gh stack link` in the same order. Wait for fresh CI on every rewritten PR.

## Verify and merge

Before merging:

```sh
git status --short --branch
gh pr checks <bottom-pr>
gh pr checks <next-pr>
gh pr checks <top-pr>
```

Confirm:

- all worktrees involved in a rewrite are clean;
- every PR base is the branch immediately below it;
- every parent is an ancestor of its child;
- all required reviews and checks pass;
- the intended merge set is contiguous from the lowest unmerged PR upward.

Use the GitHub stack merge UI or the official stack command described by the installed `gh-stack` skill. Never substitute a bare `gh pr merge` for a stack merge.

## Recovery

- **Conflict:** stop the cascade, resolve in the current layer's worktree, test, and continue only after a clean commit.
- **Remote moved:** fetch and repeat with `--force-with-lease`; never use an unconditional force push.
- **Wrong topology:** preserve commits, unlink/restructure the stack, rewrite ancestry, then link the corrected bottom-to-top chain.
- **Dirty worktree:** do not stash or discard another worker's files. Ask that owner to checkpoint or clean it.
- **Stale worktree after a server rebase:** pause. Compare local and remote SHAs before choosing a recovery; never reset destructively by assumption.
- **Independent layer discovered:** remove it from this dependency chain and create a sibling PR or separate stack.
