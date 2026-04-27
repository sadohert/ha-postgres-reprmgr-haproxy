---
name: issue-worktree
description: "Set up a git worktree for working on a GitHub project board issue in the ha-postgres-reprmgr-haproxy repo. Use when the user says 'start an issue', 'work on issue #N', 'create a worktree for issue', 'pick up issue', or similar."
---

# Issue Worktree Setup

Creates a git worktree from `feature/dc2-warm-standby-nodes` scoped to a single GitHub issue, so each issue gets an isolated working tree with its own branch.

## Step 1: Resolve the issue

If the user already specified an issue number, fetch it directly:

```bash
gh issue view <number> --repo sadohert/ha-postgres-reprmgr-haproxy --json number,title,url
```

If no issue was specified, list open issues and ask:

```bash
gh issue list --repo sadohert/ha-postgres-reprmgr-haproxy --state open \
  --json number,title,url --jq '.[] | "#\(.number)  \(.title)  \(.url)"'
```

## Step 2: Determine worktree name

Derive a short slug from the issue number and title. Use only lowercase letters, numbers, and hyphens. Examples:
- Issue #3 "Grafana lag metric disappears" → `issue-3-grafana-lag`
- Issue #4 "Publish to community forum" → `issue-4-forum-post`
- Issue #5 "Grafana HA out of scope" → `issue-5-grafana-ha-oos`

If the user suggests a name, use theirs.

## Step 3: Create the worktree and branch

```bash
REPO_ROOT="/Users/stu/development/ha-postgres-reprmgr-haproxy"
SLUG="<derived-slug>"
BRANCH="$SLUG"
WORKTREE_PATH="$REPO_ROOT/.worktrees/$SLUG"

cd "$REPO_ROOT"
git worktree add "$WORKTREE_PATH" -b "$BRANCH" feature/dc2-warm-standby-nodes
```

Confirm success by listing the worktree:
```bash
git worktree list
```

## Step 4: Confirm and summarise

Tell the user the worktree is ready:

> Worktree `.worktrees/<slug>` created on branch `<branch>`.
> You can work on it directly in this session, or open it as a separate folder in VS Code for a dedicated Claude Code session there.

## Step 5: Optionally assign the issue

If the user wants to self-assign the issue on GitHub:
```bash
gh issue edit <number> --repo sadohert/ha-postgres-reprmgr-haproxy --add-assignee "@me"
```

Only do this if the user asks.

## Notes

- Worktrees live in `.worktrees/` which is gitignored — they are local only.
- All worktrees share the same `terraform/` state file (`terraform.tfstate` at repo root). Don't run `terraform apply` from a worktree without coordinating with any other active sessions.
- The SSH key for all infrastructure is at `terraform/ha-postgres-admin-key.pem` in the repo root — accessible from any worktree via relative path `../../terraform/ha-postgres-admin-key.pem`.
- When work on the issue is complete, merge the branch back into `feature/dc2-warm-standby-nodes` and remove the worktree:
  ```bash
  cd /Users/stu/development/ha-postgres-reprmgr-haproxy
  git worktree remove .worktrees/<slug>
  git branch -d <slug>
  ```
