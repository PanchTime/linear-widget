---
name: ticket-worktree
description: >
  Bootstrap a Linear ticket with a git worktree: create a Linear issue assigned
  to the user, create a branch and worktree under a configured folder, and write
  `branch:` plus `* Worktree:` onto the Linear description so the Omarchy Linear
  widget can open it. Also clean up the worktree after the related merge and
  mark the Linear issue Done. Use when the user runs /ticket-worktree, "new
  ticket worktree", "open Linear + branch + worktree", "cleanup merged
  worktree", or "remove worktree after merge".
---

# Ticket + worktree

Fill in **Defaults** before the first run. If any value is still `REPLACE_ME`, ask — do not guess paths, teams, or remotes.

This skill owns **lifecycle** only:

1. **Bootstrap** — Linear issue → branch → worktree → write the Linear `Worktree:` line
2. **Cleanup** — after the branch is **merged**: remove worktree + local branch, mark Linear **Done**

Do **not** implement the ticket unless the user explicitly asks after bootstrap **and** the session cwd is already that worktree.

## Defaults

Replace every `REPLACE_ME`. Duplicate this skill per repo if you have more than one layout.

| Setting | Value |
|---------|--------|
| Linear team | `REPLACE_ME` (team name or key the Linear MCP can see) |
| Linear assignee | `me` |
| Main checkout | `REPLACE_ME` (absolute path of the repo you branch from) |
| Base ref | `REPLACE_ME` (`origin/main` or `origin/master`) |
| Worktree root | `REPLACE_ME` (absolute folder for ticket checkouts) |
| Branch source | `REPLACE_ME` — `linear` (use Linear `gitBranchName`) or `custom` |
| Custom branch pattern | `REPLACE_ME` if source is `custom` (example: `feature/<short-name>`) |
| Extra symlinks | none, or a list of `worktree-name -> MAIN/relative` (example: `data -> data`) |

The Omarchy Linear widget only opens directories **inside** `~/work` or `~/personal`. Put `Worktree root` under one of those (or a subdirectory).

Worktree directory name: take the full branch and replace `/` with `-`.

## Prerequisites

1. `mkdir -p "<Worktree root>"`
2. `git -C "<Main checkout>" fetch` the base ref
3. Linear MCP against the workspace that owns the team above. If the team is missing, stop and re-auth. Never print tokens.
4. Branch name and worktree path must not already exist — stop and ask.

## Bootstrap (in order)

### Step 0 — Intake

From the user message extract: **title**, **problem / evidence**, **priority** (default Medium; High if they said prod/urgent), **labels** if obvious, optional **parent** issue id only if they named one, draft **short-name** (lowercase kebab, 2–5 words, no ticket id in the slug).

If there is no title-worthy signal, ask one question. Do not invent scope.

### Step 1 — Create Linear ticket

Create with the Linear MCP (`save_issue` / equivalent, no id):

- `team`: from Defaults
- `assignee`: `me` (mandatory)
- `title`, `priority`, `labels` (if known), `parentId` (only if given)
- `state`: `In Progress` if they want to start now; else default / Backlog
- `description`: Summary, evidence, likely surface, acceptance — **no** branch block yet

Record the identifier (`ABC-N`) and URL.

### Step 2 — Branch name

If **Branch source** is `linear`: read the issue and use **`gitBranchName` exactly**. If it is missing, ask — do not invent a username prefix.

If **Branch source** is `custom`: substitute the short-name into **Custom branch pattern**. If the pattern is still `REPLACE_ME`, ask.

### Step 3 — Worktree

```bash
MAIN="<Main checkout>"
WT_ROOT="<Worktree root>"
BASE="<Base ref>"
BRANCH="<branch from Step 2>"
WT="$WT_ROOT/$(echo "$BRANCH" | tr '/' '-')"

mkdir -p "$WT_ROOT"
git -C "$MAIN" fetch origin
test ! -e "$WT"
git -C "$MAIN" rev-parse --verify "refs/heads/$BRANCH" >/dev/null 2>&1 && exit 1 || true
git -C "$MAIN" worktree add -b "$BRANCH" "$WT" "$BASE"
```

If path or branch exists: stop and ask. Do not delete or overwrite. Never nest a worktree inside another worktree; always add from **Main checkout**.

**Extra symlinks** (only names listed in Defaults; skip if none):

```bash
# example: link MAIN/data -> WT/data
if [ -e "$MAIN/<src>" ] && [ ! -e "$WT/<dest>" ]; then
  ln -sfn "$MAIN/<src>" "$WT/<dest>"
fi
```

Symlink only. Never `cp -r`. If `$WT/<dest>` exists and is not that symlink, do not overwrite — report.

**Optional `.grok`:** worktrees do not inherit untracked dirs. If main has `.grok` and the worktree does not, `ln -sfn "$MAIN/.grok" "$WT/.grok"` using the same rules.

**Grok header:** a session’s branch/cwd is fixed at launch. After bootstrap, open a **new** Grok in the worktree (`cd "$WT" && grok` or `grok --cwd "$WT"`). Do **not** use `grok --worktree=` (that creates a second Grok-managed tree).

If this skill directory has `scripts/open-grok-worktree.sh`, you may run it with `--write-only "$WT" "$BRANCH"`.

### Step 4 — Write branch onto Linear

Update the issue with the Step 1 description **plus** a branch block. The widget matches a `Worktree:` line; keep the path absolute or `~/work/...`.

````markdown
## Branch

```text
branch: <full-branch-name>
```

* Worktree: `<Worktree root>/<dir>`
* Base: `<Base ref>`
````

### Step 5 — Report

| Item | Value |
|------|--------|
| Linear | identifier + URL |
| Assignee | you (me) |
| Branch | from Step 2 |
| Worktree | absolute path |
| HEAD | short sha + base |

Then print:

```text
## Open Grok in this worktree (required for correct branch/cwd header)

cd <worktree-absolute-path>
grok
# or: grok --cwd <worktree-absolute-path>
```

Branch is **local only**. Do not commit or push. Do not start implementation in the bootstrap session unless cwd is already this worktree.

Mention: *When the MR/PR merges, run cleanup (same skill).*

---

## Cleanup — after merge

Trigger: “cleanup worktree”, “MR merged, remove worktree”, or a named branch / Linear id / path.

| Rule | Detail |
|------|--------|
| **When** | Branch is **merged** into the base ref, or the user says “merged, delete anyway” |
| **Where** | Under **Worktree root** only, unless the user names another path |
| **Never** remove **Main checkout** or the base branch |
| **Dirty / unpushed** | Stop and report; no force-remove unless they override |

### C0 — Identify

```bash
git -C "<Main checkout>" worktree list
ls -la "<Worktree root>"
```

Resolve the Linear id: user named it, session notes, or Linear search for `branch: <full-branch-name>` on the configured team.

### C1 — Prove merged

```bash
MAIN="<Main checkout>"
BASE="<Base ref>"
git -C "$MAIN" fetch origin --prune
git -C "$MAIN" merge-base --is-ancestor "$BRANCH" "$BASE" && echo MERGED
```

Not merged or inconclusive → do not delete; ask.

### C2 — Safety

```bash
git -C "$WT" status --porcelain
git -C "$WT" log "$BASE"..HEAD --oneline
```

Dirty or unique commits → stop; require “force cleanup”.

### C3 — Remove

From **main**, not inside the worktree:

```bash
git -C "$MAIN" worktree remove "$WT"
git -C "$MAIN" worktree prune
git -C "$MAIN" branch -d "$BRANCH"
```

`--force` / `branch -D` only with explicit OK. Do **not** `push --delete` unless they ask.

### C4 — Linear Done

Same request as git cleanup. Set the issue `state: Done`. Do not cancel/archive. Skip only if they said not to close the ticket, cleanup aborted, or multiple issues map to one branch.

### C5 — Report

Removed path, deleted local branch, remote left alone, merge proof, Linear Done.

**Bulk:** list all under Worktree root, show merged/dirty table, get one approval, then C3+C4 per approved row.

## Hard rules

1. Always assign Linear to `me`.
2. Fill Defaults; never substitute `REPLACE_ME` with invented paths.
3. Branch source is `linear` or `custom` as configured — do not mix schemes.
4. Always write `branch: …` and `Worktree:` onto Linear after the worktree exists.
5. Always a **new** worktree under Worktree root. Never switch the main checkout to the new branch.
6. From main checkout: only `fetch` + `worktree add` (bootstrap) or `worktree remove` (cleanup).
7. Do not push or open MRs/PRs unless the user asks later.
8. Path/branch collision → stop and ask.
9. Cleanup only after merge (or explicit force). Prefer `worktree remove` + `branch -d`.
10. Successful merged cleanup marks Linear **Done** unless they said not to.

## Failure modes

| Failure | Action |
|---------|--------|
| Defaults still `REPLACE_ME` | Ask; no Linear create |
| Linear create fails | Stop; no branch |
| `gitBranchName` missing (`linear` source) | Ask; no branch until known |
| Branch/path exists | Report; ask |
| Main checkout missing | Ask |
| Cleanup not merged / dirty | Refuse delete; do not mark Done |
| Linear Done fails | Report; git cleanup still counts if C3 succeeded |

## Out of scope

- Implementing the ticket
- Opening MRs/PRs (unless asked outside bootstrap)
- Guessing a second repo’s paths; duplicate the skill instead
