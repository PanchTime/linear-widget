# Linear widget

Omarchy bar widget for [Linear](https://linear.app) issues: multi-account filters, Herdr worktrees, the default editor, and GitLab/GitHub merge-request links.

Enter or left-click opens the ticket's git worktree in Herdr (if `herdr` is on PATH) and can start or resume the agent chosen in Filters. For Grok, Herdr starts a **new** session when that directory has none, and passes `--continue` only when a session already exists there. Herdr is optional: the issue list still works without it.

Plugin id: `grigorip.linear`.

## Install

```bash
omarchy plugin add https://github.com/PanchTime/linear-widget.git --enable --yes
```

Or by hand:

```bash
git clone https://github.com/PanchTime/linear-widget.git ~/.config/omarchy/plugins/grigorip.linear
omarchy-shell shell rescanPlugins
omarchy plugin enable grigorip.linear
```

Optional keybind (user Hyprland config, not this plugin):

```lua
o.bind({ super }, "I", function()
  os.execute("omarchy-shell shell toggle grigorip.linear &")
end)
```

## Tokens

Paste a Linear personal API token in the widget (`lin_api_…`). Tokens are stored only in `~/.config/omarchy/linear/accounts.json` (mode 600). They are never written to this repo, never printed, and never passed on process argv.

Filter prefs live in `~/.local/state/omarchy/settings/linear.json`.

## Linear ticket format

The widget lists any assigned/open issue. Extra actions need a few fields on the Linear issue itself.

### Worktree (Herdr + editor)

Enter (Herdr) and `e` (editor) need a directory for that ticket. The widget looks in this order:

1. A line in the Linear **description**:

   ```text
   * Worktree: ~/work/your-trees/ENG-123-short-slug
   ```

   Also accepted: `Worktree: /absolute/path` (optional leading `*`, optional backticks). `~` is the home directory.

2. If that line is missing, a folder under `~/work` or `~/personal` (one extra directory level) whose **name contains the issue id** (`ENG-123`, case-insensitive).

Rules:

- The path must be a real directory **inside** `~/work` or `~/personal` (not those roots themselves). Symlinks that resolve inside those trees are fine.
- Paths outside those trees are ignored, even if the description names them.
- Without a matching worktree the issue still lists. Herdr and the editor do nothing.

Herdr names the workspace `{identifier}` plus up to three words from the title (for example `ENG-123 short slug`).

`e` runs `omarchy launch editor <worktree>` in a new window — whatever `omarchy default editor` is set to (nvim, helix, code, zed, …).

Suggested description block (the `branch:` line is for humans / other tools; this widget does not read it):

```text
branch: feature/123-short-slug

* Worktree: `~/work/your-trees/ENG-123-short-slug`
```

A Grok skill can write that block for you — see [Ticket bootstrap skill](#ticket-bootstrap-skill-optional).

### Merge request / pull request (`p`)

`p` (and middle-click) opens an `https://` GitLab MR or GitHub PR. The widget uses the first match:

1. A Linear **attachment** whose `sourceType` is `gitlab`, `github`, or `githubenterprise` (Linear creates these when you attach an MR/PR).
2. Otherwise an `https://` URL in the **description** that contains:
   - `/merge_requests/<n>` or `/-/merge_requests/<n>` (GitLab)
   - `/pull/<n>` (GitHub)

If none of those exist, `p` does nothing and the status line says so.

`o` (and right-click) always opens the Linear issue URL. That needs no extra markup.

## Keys (panel focused)

| Key | Action |
|-----|--------|
| j / k | Move |
| Enter | Open ticket in Herdr, or toggle fold/filter |
| a | Toggle Accounts |
| [ | Toggle Filters |
| ] | Close pickers, then collapse both folds |
| e | Open the worktree in the Omarchy default editor |
| p | Open MR/PR in the browser |
| o | Open Linear issue |
| r | Refresh |
| Esc | Close picker, folds, then panel |

Left click a ticket: Herdr. Right click: Linear. Middle click: MR/PR.

## Ticket bootstrap skill (optional)

This plugin lists issues and opens an existing worktree. It does **not** create Linear tickets, branches, or git worktrees.

Pair it with a Grok skill that:

1. Creates a Linear issue assigned to you
2. Adds a git worktree under a folder you choose
3. Writes `branch:` and `* Worktree: <path>` onto the issue (the format above)

### Copy the template

The repo ships a generic skill at `skills/ticket-worktree/`. Copy it into Grok user skills, then **replace every `REPLACE_ME`** in the Defaults table (team, main checkout, base ref, worktree folder, branch scheme). Do not commit your filled-in paths back to this plugin.

```bash
mkdir -p ~/.grok/skills
cp -r /path/to/linear-widget/skills/ticket-worktree ~/.grok/skills/ticket-worktree
# edit ~/.grok/skills/ticket-worktree/SKILL.md — fill the Defaults table
chmod +x ~/.grok/skills/ticket-worktree/scripts/open-grok-worktree.sh
```

Then in Grok: `/ticket-worktree`. Duplicate the skill directory (new `name:` in frontmatter) if you have more than one repo layout.

### Or use `/create-skill`

In Grok, run `/create-skill`, pick **User** scope, and describe the same workflow. Keep the Defaults table and the Linear `Worktree:` line — the widget will not open Herdr without that line. A short prompt you can paste:

```text
Name: ticket-worktree
Scope: user
What it should do: Bootstrap a Linear ticket with a git worktree.
Create a Linear issue assigned to me, create a branch + worktree under a
folder I configure, write `branch:` and `* Worktree: <absolute-or-~/work/path>`
onto the Linear description, and later remove the worktree after merge and
mark the issue Done. Do not implement the ticket during bootstrap.

Put a Defaults table at the top with placeholders I must fill before first use:
- Linear team
- Main checkout (absolute path)
- Base ref (origin/main or origin/master)
- Worktree root (absolute folder under ~/work or ~/personal)
- Branch source: `linear` (Linear gitBranchName) or `custom` (pattern I supply)
- Optional extra symlinks from main into the worktree

If any value is still REPLACE_ME, ask — do not guess. Stop on branch/path
collision. Never push or open an MR unless I ask later.
```

Fill the placeholders in the generated `SKILL.md` (`~/.grok/skills/ticket-worktree/SKILL.md`) before the first run.

The template in this repo is the same idea, already written. Prefer copying it over generating a second copy.

## Settings

Bar widget setting `refreshIntervalSec` (15–3600, default 90).
