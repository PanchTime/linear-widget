# Linear widget

Omarchy bar widget for [Linear](https://linear.app) issues: multi-account filters, Herdr worktrees, the default editor, and GitLab/GitHub merge-request links.

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

## Settings

Bar widget setting `refreshIntervalSec` (15–3600, default 90).
