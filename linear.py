#!/usr/bin/env python3
"""Linear GraphQL helper for the Omarchy Linear panel.

Tokens stay in ~/.config/omarchy/linear/accounts.json (mode 600).
Filter prefs stay in ~/.local/state/omarchy/settings/linear.json.
This process never prints tokens.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

HOME = Path.home()
ACCOUNTS_PATH = HOME / ".config/omarchy/linear/accounts.json"
PREFS_PATH = HOME / ".local/state/omarchy/settings/linear.json"
GRAPHQL = "https://api.linear.app/graphql"
ALL_ACCOUNT = "all"
RESERVED_ACCOUNT_IDS = frozenset({ALL_ACCOUNT, "both"})
ID_RE = re.compile(r"^[a-z0-9][a-z0-9_-]{0,31}$")
HYPR_ADDR_RE = re.compile(r"^0x[0-9a-fA-F]+$")
WORKTREE_RE = re.compile(r"^\s*\*?\s*Worktree:\s*`?([^\s`]+)`?\s*$", re.I | re.M)
PR_URL_RE = re.compile(
    r"https://[^\s)>\]]+?(?:/-/merge_requests/\d+|/merge_requests/\d+|/pull/\d+)",
    re.I,
)
PR_SOURCES = frozenset("gitlab github githubenterprise".split())
STOPWORDS = frozenset(
    "a an the to of for in on and or with from into over not via using by".split()
)
WORKTREE_PARENTS = (HOME / "work", HOME / "personal")
HERDR_SOCK = HOME / ".config/herdr/herdr.sock"
HERDR_AGENT_KINDS = frozenset(
    "pi claude codex gemini cursor devin agy cline omp mastracode opencode "
    "copilot kimi kiro droid amp grok hermes kilo qodercli qwen maki".split()
)
AGENT_CONTINUE_ARGS = {
    "grok": ["--continue"],
    "claude": ["--continue"],
    "codex": ["resume", "--last"],
}
MAX_JSON_BYTES = 256 * 1024
MAX_HTTP_BYTES = 2 * 1024 * 1024
_CLOEXEC = getattr(os, "O_CLOEXEC", 0)
_OPEN_NOFOLLOW = os.O_RDONLY | os.O_NOFOLLOW | _CLOEXEC
_DIR_NOFOLLOW = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | _CLOEXEC


class ResponseTooLarge(ValueError):
    pass


def fail(message: str, code: int = 1) -> None:
    emit({"ok": False, "error": message})
    raise SystemExit(code)


def emit(payload: dict) -> None:
    json.dump(payload, sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")


def read_limited(fp, limit: int) -> bytes:
    data = fp.read(limit + 1)
    if not data:
        return b""
    if len(data) > limit:
        raise ResponseTooLarge(f"response exceeds {limit} bytes")
    return data


def ensure_private_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    try:
        fd = os.open(path, _DIR_NOFOLLOW)
    except OSError as exc:
        raise OSError(f"refusing unsafe directory {path}: {exc}") from exc
    try:
        st = os.fstat(fd)
        if not stat.S_ISDIR(st.st_mode):
            raise OSError(f"not a directory: {path}")
        if st.st_uid != os.getuid():
            raise OSError(f"directory not owned by current user: {path}")
        if stat.S_IMODE(st.st_mode) & 0o077:
            os.fchmod(fd, 0o700)
    finally:
        os.close(fd)


def read_json(path: Path, fallback):
    try:
        fd = os.open(path, _OPEN_NOFOLLOW)
    except FileNotFoundError:
        return fallback
    except OSError:
        return fallback
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode):
            return fallback
        if st.st_uid != os.getuid():
            return fallback
        if st.st_size > MAX_JSON_BYTES:
            return fallback
        buf = bytearray()
        while True:
            chunk = os.read(fd, min(65536, MAX_JSON_BYTES + 1 - len(buf)))
            if not chunk:
                break
            buf.extend(chunk)
            if len(buf) > MAX_JSON_BYTES:
                return fallback
        return json.loads(buf.decode("utf-8"))
    except (OSError, json.JSONDecodeError, UnicodeDecodeError):
        return fallback
    finally:
        os.close(fd)


def write_json(path: Path, payload, mode: int = 0o600) -> None:
    parent = path.parent
    ensure_private_dir(parent)
    data = (json.dumps(payload, indent=2, ensure_ascii=False) + "\n").encode("utf-8")
    if len(data) > MAX_JSON_BYTES:
        raise OSError("JSON payload exceeds size limit")
    fd, tmp_name = tempfile.mkstemp(prefix=".linear-", suffix=".tmp", dir=str(parent))
    replaced = False
    try:
        os.fchmod(fd, mode)
        written = 0
        while written < len(data):
            written += os.write(fd, data[written:])
        os.fsync(fd)
        os.close(fd)
        fd = -1
        os.replace(tmp_name, path)
        replaced = True
    finally:
        if fd >= 0:
            os.close(fd)
        if not replaced:
            try:
                os.unlink(tmp_name)
            except OSError:
                pass


def load_accounts() -> list[dict]:
    data = read_json(ACCOUNTS_PATH, {})
    accounts = data.get("accounts") if isinstance(data, dict) else None
    if not isinstance(accounts, list):
        return []
    out = []
    for item in accounts:
        if not isinstance(item, dict):
            continue
        ident = str(item.get("id") or "").strip()
        token = str(item.get("token") or "").strip()
        name = str(item.get("name") or ident).strip() or ident
        if ident and token:
            out.append({"id": ident, "name": name, "token": token})
    return out


def save_accounts(accounts: list[dict]) -> None:
    write_json(ACCOUNTS_PATH, {"accounts": accounts})


def public_accounts(accounts: list[dict]) -> list[dict]:
    return [{"id": a["id"], "name": a["name"]} for a in accounts]


def find_account(account_id: str) -> dict:
    for account in load_accounts():
        if account["id"] == account_id:
            return account
    fail(f"Unknown account: {account_id}")
    raise AssertionError


def is_all_accounts(account_id: str) -> bool:
    return account_id in (ALL_ACCOUNT, "both", "*")


def resolve_accounts(account_ids) -> list[dict]:
    accounts = load_accounts()
    if not accounts:
        fail("No Linear account configured")
    if isinstance(account_ids, str):
        if is_all_accounts(account_ids) or not account_ids.strip():
            return accounts
        account_ids = [account_ids]
    wanted = as_id_list(account_ids)
    if not wanted:
        return []
    by_id = {a["id"]: a for a in accounts}
    return [by_id[ident] for ident in wanted if ident in by_id]


LIST_PREF_KEYS = ("accountIds", "teamIds", "projectIds", "scopes")
SCOPE_VALUES = ("assigned", "open", "active")


def as_id_list(value) -> list[str]:
    if isinstance(value, list):
        raw = value
    elif value is None or value == "":
        raw = []
    else:
        raw = [value]
    out: list[str] = []
    seen: set[str] = set()
    for item in raw:
        text = str(item).strip()
        if not text or text in seen or is_all_accounts(text):
            continue
        seen.add(text)
        out.append(text)
    return out


def default_prefs() -> dict:
    return {
        "accountIds": [],
        "teamIds": [],
        "projectIds": [],
        "scopes": ["assigned"],
        "agentKind": "grok",
    }


def normalize_agent_kind(value: str) -> str:
    kind = str(value or "").strip().lower()
    if kind in ("", "off", "none", "no"):
        return ""
    if kind in HERDR_AGENT_KINDS:
        return kind
    return "grok"


def load_prefs() -> dict:
    prefs = default_prefs()
    stored = read_json(PREFS_PATH, {})
    if not isinstance(stored, dict):
        stored = {}
    accounts = load_accounts()
    account_ids = [a["id"] for a in accounts]
    id_set = set(account_ids)
    if "accountIds" in stored:
        prefs["accountIds"] = [ident for ident in as_id_list(stored.get("accountIds")) if ident in id_set]
    else:
        old = str(stored.get("accountId") or "").strip()
        if is_all_accounts(old) or not old:
            prefs["accountIds"] = list(account_ids)
        elif old in id_set:
            prefs["accountIds"] = [old]
        else:
            prefs["accountIds"] = list(account_ids)
    if not prefs["accountIds"] and account_ids:
        prefs["accountIds"] = list(account_ids)
    if "teamIds" in stored:
        prefs["teamIds"] = as_id_list(stored.get("teamIds"))
    else:
        prefs["teamIds"] = as_id_list(stored.get("teamId"))
    if "projectIds" in stored:
        prefs["projectIds"] = as_id_list(stored.get("projectIds"))
    else:
        prefs["projectIds"] = as_id_list(stored.get("projectId"))
    if "scopes" in stored:
        prefs["scopes"] = [s for s in as_id_list(stored.get("scopes")) if s in SCOPE_VALUES]
    else:
        old_scope = str(stored.get("scope") or "assigned").strip()
        prefs["scopes"] = [old_scope] if old_scope in SCOPE_VALUES else ["assigned"]
    if stored.get("agentKind") is not None:
        prefs["agentKind"] = normalize_agent_kind(stored.get("agentKind"))
    return prefs


def save_prefs(prefs: dict) -> dict:
    merged = load_prefs()
    for key, value in (prefs or {}).items():
        if key not in merged or value is None:
            continue
        if key in LIST_PREF_KEYS:
            merged[key] = as_id_list(value)
        else:
            merged[key] = str(value).strip()
    merged["scopes"] = [s for s in merged["scopes"] if s in SCOPE_VALUES]
    merged["agentKind"] = normalize_agent_kind(merged.get("agentKind"))
    accounts = load_accounts()
    id_set = {a["id"] for a in accounts}
    merged["accountIds"] = [ident for ident in merged["accountIds"] if ident in id_set]
    write_json(PREFS_PATH, merged, mode=0o644)
    return load_prefs()


def graphql_call(token: str, query: str, variables: dict | None = None) -> tuple[dict, str]:
    body = json.dumps({"query": query, "variables": variables or {}}).encode("utf-8")
    request = urllib.request.Request(
        GRAPHQL,
        data=body,
        headers={
            "Content-Type": "application/json",
            "Authorization": token,
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            raw = read_limited(response, MAX_HTTP_BYTES)
            payload = json.loads(raw.decode("utf-8"))
    except ResponseTooLarge:
        return {}, "Linear response exceeds size limit"
    except urllib.error.HTTPError as exc:
        try:
            detail = read_limited(exc, MAX_HTTP_BYTES).decode("utf-8", "replace")
        except ResponseTooLarge:
            return {}, f"Linear HTTP {exc.code}"
        except OSError:
            return {}, f"Linear HTTP {exc.code}"
        finally:
            try:
                exc.close()
            except OSError:
                pass
        try:
            parsed = json.loads(detail)
            message = parsed.get("errors", [{}])[0].get("message") or f"Linear HTTP {exc.code}"
        except (json.JSONDecodeError, TypeError, IndexError, AttributeError):
            message = f"Linear HTTP {exc.code}"
        return {}, message
    except urllib.error.URLError as exc:
        return {}, f"Linear network error: {exc.reason}"
    except (json.JSONDecodeError, UnicodeDecodeError):
        return {}, "Linear returned invalid JSON"
    if payload.get("errors"):
        return payload.get("data") or {}, "; ".join(
            str(err.get("message") or err) for err in payload["errors"]
        )
    return payload.get("data") or {}, ""


def graphql(token: str, query: str, variables: dict | None = None) -> dict:
    data, err = graphql_call(token, query, variables)
    if err:
        fail(err)
    return data


def slug_id(name: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", name.strip().lower()).strip("-")
    return slug[:32] or "account"


def unique_account_id(ident: str, existing: set[str]) -> str:
    if ident not in existing and ident not in RESERVED_ACCOUNT_IDS:
        return ident
    n = 2
    while True:
        candidate = f"{ident}-{n}"[:32]
        if candidate not in existing and candidate not in RESERVED_ACCOUNT_IDS:
            return candidate
        n += 1


TEAMS_QUERY = """
query LinearTeams {
  viewer { id name email }
  teams(first: 50) {
    nodes { id key name }
  }
}
"""

PROJECTS_QUERY = """
query LinearProjects($filter: ProjectFilter) {
  projects(first: 50, filter: $filter) {
    nodes { id name }
  }
}
"""

ISSUES_QUERY = """
query LinearIssues($first: Int!, $filter: IssueFilter) {
  issues(first: $first, filter: $filter, orderBy: updatedAt) {
    nodes {
      id
      identifier
      title
      description
      url
      priority
      updatedAt
      state { name type color }
      assignee { name isMe }
      team { id key name }
      project { id name }
      attachments(first: 10) {
        nodes { title url sourceType }
      }
    }
  }
}
"""


def expand_path(raw: str) -> str:
    text = str(raw or "").strip().replace("`", "")
    if text.startswith("~/"):
        return str(HOME / text[2:])
    if text == "~":
        return str(HOME)
    return text


def resolved_or_none(path: Path) -> Path | None:
    try:
        return path.expanduser().resolve()
    except OSError:
        return None


def allowed_worktree_roots() -> list[Path]:
    roots: list[Path] = []
    seen: set[str] = set()
    for parent in WORKTREE_PARENTS:
        for candidate in (parent, resolved_or_none(parent)):
            if candidate is None or not candidate.is_dir():
                continue
            key = str(candidate)
            if key in seen:
                continue
            seen.add(key)
            roots.append(candidate)
    return roots


def worktree_search_roots() -> list[Path]:
    roots: list[Path] = []
    seen: set[str] = set()
    for parent in allowed_worktree_roots():
        key = str(parent)
        if key not in seen:
            seen.add(key)
            roots.append(parent)
        try:
            children = list(parent.iterdir())
        except OSError:
            continue
        for child in children:
            if not child.is_dir():
                continue
            child_key = str(child)
            if child_key in seen:
                continue
            seen.add(child_key)
            roots.append(child)
    return roots


def is_allowed_worktree(path: Path) -> bool:
    resolved = resolved_or_none(path)
    if resolved is None or not resolved.is_dir():
        return False
    for root in allowed_worktree_roots():
        try:
            rel = resolved.relative_to(root)
        except ValueError:
            continue
        if rel.parts:
            return True
    return False


def parse_worktree_line(description: str) -> str:
    match = WORKTREE_RE.search(description or "")
    if not match:
        return ""
    path = Path(expand_path(match.group(1))).expanduser()
    if is_allowed_worktree(path):
        return str(resolved_or_none(path) or path)
    return ""


def short_words(title: str, count: int = 3) -> list[str]:
    tokens = re.findall(r"[A-Za-z0-9]+", title or "")
    words = [t.lower() for t in tokens if t.lower() not in STOPWORDS and not re.fullmatch(r"\d+", t)]
    return words[:count]


def pr_url_from_issue(node: dict, description: str) -> str:
    for att in ((node.get("attachments") or {}).get("nodes")) or []:
        url = str(att.get("url") or "").strip()
        source = str(att.get("sourceType") or "").lower()
        if not url:
            continue
        if url.lower().startswith("https://") and (source in PR_SOURCES or PR_URL_RE.search(url)):
            return url
    match = PR_URL_RE.search(description or "")
    return match.group(0) if match else ""


def herdr_label(identifier: str, title: str) -> str:
    words = short_words(title, 3)
    extra = " ".join(words)
    return f"{identifier} {extra}".strip()


def needle_for(identifier: str) -> str:
    return identifier.lower().replace("_", "-")


def find_worktree_on_disk(identifier: str) -> str:
    needle = needle_for(identifier)
    if not needle:
        return ""
    for root in worktree_search_roots():
        if not root.is_dir():
            continue
        try:
            entries = list(root.iterdir())
        except OSError:
            continue
        for entry in entries:
            if entry.is_dir() and needle in entry.name.lower():
                return str(entry)
    return ""


def resolve_worktree(identifier: str, description: str) -> str:
    from_desc = parse_worktree_line(description)
    if from_desc:
        return from_desc
    found = find_worktree_on_disk(identifier)
    return found if found and is_allowed_worktree(Path(found)) else ""


def herdr_try(args: list[str], cwd: str | None = None, timeout: float = 20) -> dict:
    try:
        completed = subprocess.run(
            ["herdr", *args],
            check=False,
            capture_output=True,
            text=True,
            timeout=timeout,
            cwd=cwd or str(HOME),
        )
    except (OSError, subprocess.TimeoutExpired):
        return {}
    raw = (completed.stdout or "").strip() or (completed.stderr or "").strip()
    if not raw:
        return {}
    try:
        return json.loads(raw)
    except json.JSONDecodeError:
        return {}


def herdr_error(payload: dict) -> str:
    err = payload.get("error") if isinstance(payload, dict) else None
    if isinstance(err, dict):
        return str(err.get("message") or err.get("code") or "")
    if err:
        return str(err)
    return ""


def herdr_json(args: list[str], cwd: str | None = None, timeout: float = 20) -> dict:
    payload = herdr_try(args, cwd=cwd, timeout=timeout)
    if not payload:
        fail(f"herdr {' '.join(args)} failed")
    message = herdr_error(payload)
    if message:
        fail(message)
    return payload


def herdr_result(payload: dict) -> dict:
    return payload.get("result") if isinstance(payload, dict) else {}


def same_dir(left: str, right: str) -> bool:
    if not left or not right:
        return False
    try:
        return Path(left).expanduser().resolve() == Path(right).expanduser().resolve()
    except OSError:
        return os.path.normpath(left) == os.path.normpath(right)


def workspace_checkout(workspace: dict) -> str:
    tree = workspace.get("worktree") if isinstance(workspace, dict) else None
    if isinstance(tree, dict):
        return str(tree.get("checkout_path") or "")
    return str((workspace or {}).get("cwd") or "")


def session_running() -> bool:
    payload = herdr_try(["session", "list", "--json"])
    for session in payload.get("sessions") or []:
        if session.get("default") and session.get("running"):
            return True
    return HERDR_SOCK.exists()


def wait_for_herdr(timeout: float = 8.0) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if HERDR_SOCK.exists() and session_running():
            return True
        time.sleep(0.2)
    return session_running()


def launch_herdr_tui(cwd: str) -> None:
    directory = cwd if Path(cwd).is_dir() else str(HOME)
    cmd = ["uwsm-app", "--", "xdg-terminal-exec", "--dir=" + directory, "herdr"]
    subprocess.Popen(
        cmd,
        start_new_session=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def hypr_focus_address(address: str) -> bool:
    addr = str(address or "").strip()
    if addr.startswith("address:"):
        addr = addr[len("address:") :]
    if not HYPR_ADDR_RE.fullmatch(addr):
        return False
    window = f"address:{addr}"
    code = f"hl.dispatch(hl.dsp.focus({{ window = '{window}' }}))"
    try:
        completed = subprocess.run(
            ["hyprctl", "eval", code],
            check=False,
            capture_output=True,
            text=True,
            timeout=3,
        )
    except (OSError, subprocess.TimeoutExpired):
        return False
    text = f"{completed.stdout or ''}{completed.stderr or ''}".lower()
    return completed.returncode == 0 and "error" not in text and "not found" not in text and "warning" not in text


def hypr_clients() -> list[dict]:
    try:
        clients = json.loads(
            subprocess.check_output(["hyprctl", "-j", "clients"], text=True, timeout=3)
        )
    except (OSError, subprocess.TimeoutExpired, json.JSONDecodeError):
        return []
    return clients if isinstance(clients, list) else []


def proc_cmdline(pid: int) -> str:
    if not pid:
        return ""
    try:
        return Path(f"/proc/{pid}/cmdline").read_bytes().replace(b"\x00", b" ").decode("utf-8", "replace")
    except OSError:
        return ""


def client_is_linear(client: dict) -> bool:
    title = str(client.get("title") or "")
    klass = str(client.get("class") or "")
    blob = (title + " " + klass).lower()
    return "linear.app" in blob or klass.lower() in ("linear", "linear.exe")


def client_is_herdr(client: dict) -> bool:
    if client_is_linear(client):
        return False
    cmd = proc_cmdline(int(client.get("pid") or 0)).lower()
    return "herdr" in cmd.split()


def herdr_client_count() -> int:
    return sum(1 for client in hypr_clients() if client_is_herdr(client))


def focus_herdr_window(label: str) -> bool:
    host = os.uname().nodename.lower()
    label_l = (label or "").lower()
    ranked = []
    for client in hypr_clients():
        if not client_is_herdr(client):
            continue
        title = str(client.get("title") or "").lower()
        score = 4
        if label_l and f"{host}: {label_l}" in title:
            score += 5
        elif label_l and label_l in title:
            score += 2
        ranked.append((score, client.get("address") or ""))
    ranked.sort(reverse=True)
    for _, address in ranked:
        if not address:
            continue
        if hypr_focus_address(address):
            return True
    return False


def wait_for_herdr_window(label: str, timeout: float = 2.0) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        if focus_herdr_window(label):
            return True
        time.sleep(0.1)
    return focus_herdr_window(label)


def workspace_matches(workspace: dict, identifier: str, worktree: str) -> bool:
    label = str(workspace.get("label") or "")
    if identifier and label.upper().startswith(identifier.upper()):
        return True
    return same_dir(workspace_checkout(workspace), worktree)


def list_workspaces() -> list[dict]:
    payload = herdr_json(["workspace", "list"])
    result = herdr_result(payload)
    return result.get("workspaces") or []


def focus_workspace(workspace_id: str) -> None:
    herdr_json(["workspace", "focus", workspace_id])


def rename_workspace(workspace_id: str, label: str) -> None:
    if workspace_id and label:
        herdr_json(["workspace", "rename", workspace_id, label])


def listed_worktrees(worktree: str) -> tuple[list[dict], dict]:
    listed = herdr_json(["worktree", "list", "--cwd", worktree])
    result = herdr_result(listed)
    return result.get("worktrees") or [], result.get("source") or {}


def open_or_create_workspace(worktree: str, label: str, identifier: str) -> dict:
    for workspace in list_workspaces():
        if workspace_matches(workspace, identifier, worktree):
            focus_workspace(workspace["workspace_id"])
            if workspace.get("label") != label:
                rename_workspace(workspace["workspace_id"], label)
            return {"action": "focus", "workspaceId": workspace["workspace_id"], "label": label}

    trees, source = listed_worktrees(worktree)
    parent_ws = str(source.get("source_workspace_id") or "")
    parent_cwd = str(source.get("source_checkout_path") or source.get("repo_root") or "")
    for tree in trees:
        path = str(tree.get("path") or "")
        if not same_dir(path, worktree):
            continue
        open_id = tree.get("open_workspace_id")
        if open_id:
            focus_workspace(open_id)
            rename_workspace(open_id, label)
            return {"action": "focus", "workspaceId": open_id, "label": label}
        args = ["worktree", "open", "--path", path, "--label", label, "--focus"]
        if parent_ws:
            args.extend(["--workspace", parent_ws])
        elif parent_cwd:
            args.extend(["--cwd", parent_cwd])
        opened = herdr_json(args, cwd=parent_cwd or None)
        workspace = (herdr_result(opened).get("workspace") or {})
        workspace_id = workspace.get("workspace_id") or workspace.get("id") or ""
        if workspace_id:
            rename_workspace(workspace_id, label)
        return {"action": "open", "workspaceId": workspace_id, "label": label}

    created = herdr_json(
        ["workspace", "create", "--cwd", worktree, "--label", label, "--focus"],
        cwd=worktree,
    )
    workspace = herdr_result(created).get("workspace") or {}
    workspace_id = workspace.get("workspace_id") or workspace.get("id") or ""
    if workspace_id:
        rename_workspace(workspace_id, label)
    return {"action": "create", "workspaceId": workspace_id, "label": label}


def agent_live_name(identifier: str) -> str:
    slug = re.sub(r"[^a-z0-9-]+", "-", (identifier or "").lower()).strip("-")
    if not slug or not slug[0].isalpha():
        slug = "t" + slug
    return slug[:32] or "agent"


def list_agents() -> list[dict]:
    payload = herdr_try(["agent", "list"])
    if not payload or herdr_error(payload):
        return []
    return herdr_result(payload).get("agents") or []


def panes_in_workspace(workspace_id: str) -> list[dict]:
    if not workspace_id:
        return []
    payload = herdr_try(["pane", "list", "--workspace", workspace_id])
    if not payload or herdr_error(payload):
        return []
    return herdr_result(payload).get("panes") or []


def grok_has_session(worktree: str) -> bool:
    try:
        completed = subprocess.run(
            ["grok", "sessions", "list", "-n", "1"],
            check=False,
            capture_output=True,
            text=True,
            timeout=8,
            cwd=worktree,
        )
    except (OSError, subprocess.TimeoutExpired):
        return False
    return bool(re.search(r"[0-9a-f]{8}-[0-9a-f]{4}-", completed.stdout or "", re.I))


def continue_args_for(kind: str, worktree: str) -> list[str]:
    extra = list(AGENT_CONTINUE_ARGS.get(kind) or [])
    if not extra:
        return []
    if kind == "grok" and not grok_has_session(worktree):
        return []
    return extra


def agent_occupies(pane: dict) -> bool:
    if str(pane.get("agent") or "").strip():
        return True
    return str(pane.get("agent_status") or "") in ("idle", "working", "blocked", "done")


def free_shell_pane(workspace_id: str, worktree: str) -> str:
    for pane in panes_in_workspace(workspace_id):
        if agent_occupies(pane):
            continue
        pane_id = str(pane.get("pane_id") or "")
        if pane_id:
            return pane_id
    created = herdr_try(
        ["tab", "create", "--workspace", workspace_id, "--cwd", worktree, "--focus"]
    )
    if not created or herdr_error(created):
        return ""
    result = herdr_result(created)
    pane = result.get("root_pane") or {}
    return str(pane.get("pane_id") or "")


def start_agent(name: str, kind: str, pane_id: str, extra: list[str]) -> dict:
    args = ["agent", "start", name, "--kind", kind, "--pane", pane_id, "--timeout", "25000"]
    if extra:
        args.extend(["--", *extra])
    return herdr_try(args, timeout=40)


def ensure_agent(workspace_id: str, kind: str, identifier: str, worktree: str) -> dict:
    if not kind:
        return {"agentKind": "", "agentAction": "skip"}
    if not shutil.which(kind):
        return {"agentKind": kind, "agentAction": "error", "agentError": f"{kind} is not on PATH"}
    for agent in list_agents():
        if str(agent.get("agent") or "").lower() != kind:
            continue
        cwd = str(agent.get("foreground_cwd") or agent.get("cwd") or "")
        if agent.get("workspace_id") == workspace_id or same_dir(cwd, worktree):
            pane_id = str(agent.get("pane_id") or "")
            ws = str(agent.get("workspace_id") or "")
            if ws:
                focus_workspace(ws)
            if pane_id:
                herdr_try(["agent", "focus", pane_id])
            return {"agentKind": kind, "agentAction": "focus", "agentPaneId": pane_id}

    pane_id = free_shell_pane(workspace_id, worktree)
    if not pane_id:
        return {"agentKind": kind, "agentAction": "error", "agentError": "No Herdr pane to start the agent"}

    name = agent_live_name(identifier)
    extra = continue_args_for(kind, worktree)
    payload = start_agent(name, kind, pane_id, extra)
    message = herdr_error(payload)
    if (not payload or message) and extra:
        pane_id = free_shell_pane(workspace_id, worktree) or pane_id
        payload = start_agent(name, kind, pane_id, [])
        message = herdr_error(payload)
    if not payload or message:
        return {
            "agentKind": kind,
            "agentAction": "error",
            "agentError": message or f"herdr agent start {kind} failed",
            "agentPaneId": pane_id,
        }
    herdr_try(["agent", "focus", name])
    return {
        "agentKind": kind,
        "agentAction": "continue" if extra else "start",
        "agentPaneId": pane_id,
        "agentName": name,
    }


def issue_worktree_for(identifier: str, preferred: str = "") -> tuple[str, str, str]:
    identifier = str(identifier or "").strip()
    if not identifier:
        fail("Issue identifier required")
    prefs = load_prefs()
    accounts = load_accounts()
    if not accounts:
        fail("No Linear account configured")
    ordered: list[dict] = []
    seen: set[str] = set()
    for ident in [preferred, *prefs.get("accountIds", [])]:
        if not ident or is_all_accounts(ident) or ident in seen:
            continue
        for account in accounts:
            if account["id"] == ident:
                ordered.append(account)
                seen.add(ident)
                break
    for account in accounts:
        if account["id"] not in seen:
            ordered.append(account)
            seen.add(account["id"])
    node = None
    for account in ordered:
        node = load_issue_from_account(account, identifier)
        if node:
            break
    if not node:
        fail(f"Could not load {identifier} from Linear")
    ident = str(node.get("identifier") or identifier)
    title = str(node.get("title") or "")
    worktree = resolve_worktree(ident, node.get("description") or "")
    if not worktree or not is_allowed_worktree(Path(worktree)):
        fail(f"No worktree for {ident} under ~/work or ~/personal. Put `* Worktree: ~/work/...` on the Linear description.")
    return ident, title, worktree


def launch_editor(worktree: str) -> None:
    editor = shutil.which("omarchy-launch-editor")
    if not editor:
        fail("omarchy-launch-editor is not on PATH")
    subprocess.Popen(
        [editor, worktree],
        start_new_session=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        cwd=worktree,
    )


def cmd_edit(args: list[str]) -> None:
    identifier = args[0].strip() if args else ""
    preferred = args[1].strip() if len(args) > 1 else ""
    ident, title, worktree = issue_worktree_for(identifier, preferred)
    launch_editor(worktree)
    emit({
        "ok": True,
        "identifier": ident,
        "worktree": worktree,
        "herdrLabel": herdr_label(ident, title),
    })


def cmd_herdr(args: list[str]) -> None:
    identifier = args[0].strip() if args else ""
    preferred = args[1].strip() if len(args) > 1 else ""
    ident, title, worktree = issue_worktree_for(identifier, preferred)
    label = herdr_label(ident, title)
    prefs = load_prefs()
    if not session_running() and herdr_client_count() == 0:
        launch_herdr_tui(worktree)
        if not wait_for_herdr():
            fail("Herdr did not start")
        wait_for_herdr_window(label)
    opened = open_or_create_workspace(worktree, label, ident)
    agent_info = ensure_agent(
        str(opened.get("workspaceId") or ""),
        prefs.get("agentKind") or "",
        ident,
        worktree,
    )
    focused = focus_herdr_window(label)
    if not focused and herdr_client_count() == 0:
        launch_herdr_tui(worktree)
        focused = wait_for_herdr_window(label)
    elif not focused:
        focused = wait_for_herdr_window(label, timeout=0.8)
    emit({
        "ok": True,
        "identifier": ident,
        "worktree": worktree,
        "herdrLabel": label,
        "windowFocused": focused,
        **opened,
        **agent_info,
    })


def issue_filter(prefs: dict) -> dict:
    filt: dict = {"state": {"type": {"nin": ["completed", "canceled"]}}}
    scopes = prefs.get("scopes") or []
    if scopes == ["assigned"]:
        filt["assignee"] = {"isMe": {"eq": True}}
    elif scopes == ["active"]:
        filt["state"] = {"type": {"eq": "started"}}
    return filt


def apply_local_filters(issues: list[dict], prefs: dict) -> list[dict]:
    scopes = set(prefs.get("scopes") or [])
    if scopes and "open" not in scopes:
        out = []
        for item in issues:
            keep = False
            if "assigned" in scopes and item.get("isMe"):
                keep = True
            if "active" in scopes and item.get("stateType") == "started":
                keep = True
            if keep:
                out.append(item)
        issues = out
    return issues


def present_issue(node: dict, account: dict) -> dict:
    state = node.get("state") or {}
    team = node.get("team") or {}
    project = node.get("project") or {}
    assignee = node.get("assignee") or {}
    identifier = node.get("identifier") or ""
    title = node.get("title") or ""
    description = node.get("description") or ""
    return {
        "id": node.get("id"),
        "identifier": identifier,
        "title": title,
        "url": node.get("url") or "",
        "priority": node.get("priority") or 0,
        "updatedAt": node.get("updatedAt") or "",
        "state": state.get("name") or "",
        "stateType": state.get("type") or "",
        "stateColor": state.get("color") or "",
        "teamId": team.get("id") or "",
        "teamKey": team.get("key") or "",
        "teamName": team.get("name") or "",
        "projectId": project.get("id") or "",
        "projectName": project.get("name") or "",
        "assignee": assignee.get("name") or "",
        "isMe": bool(assignee.get("isMe")),
        "worktree": resolve_worktree(identifier, description) or "",
        "herdrLabel": herdr_label(identifier, title),
        "prUrl": pr_url_from_issue(node, description),
        "accountId": account["id"],
        "accountName": account["name"],
    }


def fetch_teams_projects(account: dict, prefs: dict, combined: bool) -> tuple[list, list, dict, str]:
    data, err = graphql_call(account["token"], TEAMS_QUERY)
    if err:
        return [], [], {}, err
    teams_out = []
    for team in (data.get("teams") or {}).get("nodes") or []:
        name = str(team.get("name") or team.get("key") or "")
        if combined:
            name = f"{account['name']} / {name}"
        teams_out.append({
            "id": team.get("id"),
            "key": team.get("key"),
            "name": name,
            "accountId": account["id"],
        })
    selected_teams = [tid for tid in prefs.get("teamIds") or [] if any(t["id"] == tid for t in teams_out)]
    team_id = selected_teams[0] if len(selected_teams) == 1 else ""
    project_filter = {"accessibleTeams": {"id": {"eq": team_id}}} if team_id else None
    projects_data, proj_err = graphql_call(account["token"], PROJECTS_QUERY, {"filter": project_filter})
    if proj_err:
        return teams_out, [], data.get("viewer") or {}, proj_err
    projects_out = []
    for project in (projects_data.get("projects") or {}).get("nodes") or []:
        name = str(project.get("name") or "")
        if combined:
            name = f"{account['name']} / {name}"
        projects_out.append({
            "id": project.get("id"),
            "name": name,
            "accountId": account["id"],
        })
    return teams_out, projects_out, data.get("viewer") or {}, ""


def fetch_issues(account: dict, prefs: dict) -> tuple[list, str]:
    data, err = graphql_call(account["token"], ISSUES_QUERY, {"first": 40, "filter": issue_filter(prefs)})
    if err:
        return [], err
    nodes = (data.get("issues") or {}).get("nodes") or []
    return [present_issue(node, account) for node in nodes], ""


def load_issue_from_account(account: dict, identifier: str) -> dict | None:
    parts = identifier.split("-")
    number = int(parts[-1]) if parts[-1].isdigit() else None
    if number is None:
        return None
    issue_filt: dict = {"number": {"eq": number}}
    if len(parts) >= 2:
        issue_filt["team"] = {"key": {"eq": parts[0]}}
    data, err = graphql_call(account["token"], ISSUES_QUERY, {"first": 5, "filter": issue_filt})
    if err:
        return None
    nodes = (data.get("issues") or {}).get("nodes") or []
    for item in nodes:
        if str(item.get("identifier") or "") == identifier or str(item.get("id") or "") == identifier:
            return item
    return nodes[0] if nodes else None


def cmd_accounts(_: list[str]) -> None:
    prefs = save_prefs(load_prefs())
    emit({"ok": True, "accounts": public_accounts(load_accounts()), "prefs": prefs})


def cmd_add(args: list[str]) -> None:
    ident = ""
    name = ""
    i = 0
    while i < len(args):
        if args[i] == "--id" and i + 1 < len(args):
            ident = args[i + 1].strip()
            i += 2
        elif args[i] == "--name" and i + 1 < len(args):
            name = args[i + 1].strip()
            i += 2
        else:
            fail(f"Unknown argument: {args[i]}")
    token = (sys.stdin.readline() or "").strip()
    if not ident:
        ident = slug_id(name or "account")
    existing = {a["id"] for a in load_accounts()}
    ident = unique_account_id(ident, existing)
    if ident in RESERVED_ACCOUNT_IDS:
        fail("That account name is reserved; use Work, Personal, or similar")
    if not ID_RE.match(ident):
        fail("Account id must be lowercase letters, numbers, _ or -")
    if not token:
        fail("Token is empty")
    if not token.startswith("lin_"):
        fail("Token should be a Linear personal API key (lin_api_…)")
    if not name:
        name = ident
    viewer = graphql(token, "query { viewer { name } }")
    viewer_name = ((viewer.get("viewer") or {}).get("name") or "").strip()
    if viewer_name and name == ident:
        name = viewer_name
    accounts = [a for a in load_accounts() if a["id"] != ident]
    accounts.append({"id": ident, "name": name, "token": token})
    save_accounts(accounts)
    prefs = load_prefs()
    selected = [i for i in prefs.get("accountIds", []) if i]
    if ident not in selected:
        selected.append(ident)
    prefs = save_prefs({
        "accountIds": selected,
        "teamIds": [],
        "projectIds": [],
    })
    emit({"ok": True, "accounts": public_accounts(accounts), "prefs": prefs, "viewer": viewer_name})


def cmd_remove(args: list[str]) -> None:
    if not args:
        fail("Account id required")
    ident = args[0].strip()
    accounts = [a for a in load_accounts() if a["id"] != ident]
    save_accounts(accounts)
    prefs = load_prefs()
    remaining = [a["id"] for a in accounts]
    selected = [i for i in prefs.get("accountIds", []) if i != ident and i in remaining]
    if not selected:
        selected = remaining
    prefs = save_prefs({
        "accountIds": selected,
        "teamIds": [],
        "projectIds": [],
    })
    emit({"ok": True, "accounts": public_accounts(accounts), "prefs": prefs})


def cmd_prefs(args: list[str]) -> None:
    if args[:1] == ["set"]:
        patch: dict = {}
        i = 1
        while i < len(args):
            token = args[i]
            if token.startswith("--") and i + 1 < len(args):
                key = token[2:]
                val = args[i + 1]
                if key in LIST_PREF_KEYS:
                    patch[key] = [part for part in val.split(",") if part.strip()]
                elif key in default_prefs():
                    patch[key] = val
                i += 2
            else:
                i += 1
        prefs = save_prefs(patch)
    else:
        prefs = load_prefs()
    emit({"ok": True, "prefs": prefs, "accounts": public_accounts(load_accounts())})


def cmd_meta(args: list[str]) -> None:
    prefs = load_prefs()
    accounts = resolve_accounts(args[0] if args else prefs.get("accountIds"))
    combined = len(accounts) > 1
    teams: list[dict] = []
    projects: list[dict] = []
    viewer = {"name": "", "email": ""}
    warnings: list[str] = []
    for account in accounts:
        acc_teams, acc_projects, acc_viewer, err = fetch_teams_projects(account, prefs, combined)
        teams.extend(acc_teams)
        projects.extend(acc_projects)
        if not viewer.get("name") and acc_viewer:
            viewer = {"name": acc_viewer.get("name") or "", "email": acc_viewer.get("email") or ""}
        if err:
            warnings.append(f"{account['name']}: {err}")
    if combined:
        viewer = {"name": " + ".join(a["name"] for a in accounts), "email": ""}
    if not teams and not projects and warnings:
        fail("; ".join(warnings))
    payload = {
        "ok": True,
        "accountIds": [a["id"] for a in accounts],
        "viewer": viewer,
        "teams": teams,
        "projects": projects,
        "prefs": prefs,
    }
    if warnings:
        payload["warning"] = "; ".join(warnings)
    emit(payload)


def cmd_issues(args: list[str]) -> None:
    prefs = load_prefs()
    accounts = resolve_accounts(args[0] if args else prefs.get("accountIds"))
    issues: list[dict] = []
    warnings: list[str] = []
    for account in accounts:
        acc_issues, err = fetch_issues(account, prefs)
        issues.extend(acc_issues)
        if err and not prefs.get("teamIds") and not prefs.get("projectIds"):
            warnings.append(f"{account['name']}: {err}")
    issues = apply_local_filters(issues, prefs)
    issues.sort(key=lambda item: str(item.get("updatedAt") or ""), reverse=True)
    if not issues and warnings:
        fail("; ".join(warnings))
    payload = {
        "ok": True,
        "accountIds": [a["id"] for a in accounts],
        "count": len(issues),
        "issues": issues,
        "prefs": prefs,
    }
    if warnings:
        payload["warning"] = "; ".join(warnings)
    emit(payload)


def main() -> None:
    if len(sys.argv) < 2:
        fail("Usage: linear.py <accounts|add|remove|prefs|meta|issues|herdr|edit|focus>")
    cmd = sys.argv[1]
    args = sys.argv[2:]
    if cmd == "accounts":
        cmd_accounts(args)
    elif cmd == "add":
        cmd_add(args)
    elif cmd == "remove":
        cmd_remove(args)
    elif cmd == "prefs":
        cmd_prefs(args)
    elif cmd == "meta":
        cmd_meta(args)
    elif cmd == "issues":
        cmd_issues(args)
    elif cmd == "herdr":
        cmd_herdr(args)
    elif cmd == "edit":
        cmd_edit(args)
    elif cmd == "focus":
        label = " ".join(args).strip()
        emit({"ok": True, "windowFocused": focus_herdr_window(label)})
    else:
        fail(f"Unknown command: {cmd}")


if __name__ == "__main__":
    main()
