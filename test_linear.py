#!/usr/bin/env python3
import os
import tempfile
import unittest
import urllib.parse
from pathlib import Path
from unittest import mock

import linear


class GrokSessionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.grok = self.root / "grok-home"
        self.sessions = self.grok / "sessions"
        self.worktree = self.root / "ticket-tree"
        self.worktree.mkdir()
        self.env = mock.patch.dict(os.environ, {"GROK_HOME": str(self.grok)})
        self.env.start()

    def tearDown(self):
        self.env.stop()
        self.tmp.cleanup()

    def group_for(self, cwd: str) -> Path:
        return self.sessions / urllib.parse.quote(cwd, safe="")

    def add_session(self, cwd: str, sid: str = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee") -> Path:
        folder = self.group_for(cwd) / sid
        folder.mkdir(parents=True)
        return folder

    def test_new_worktree_starts_fresh(self):
        self.sessions.mkdir(parents=True)
        self.assertFalse(linear.grok_has_session(str(self.worktree)))
        self.assertEqual(linear.continue_args_for("grok", str(self.worktree)), [])

    def test_existing_session_continues(self):
        cwd = str(self.worktree.resolve())
        self.add_session(cwd)
        self.assertTrue(linear.grok_has_session(str(self.worktree)))
        self.assertEqual(linear.continue_args_for("grok", str(self.worktree)), ["--continue"])

    def test_sibling_cwd_is_ignored(self):
        other = self.root / "other-tree"
        other.mkdir()
        self.add_session(str(other.resolve()))
        self.assertFalse(linear.grok_has_session(str(self.worktree)))
        self.assertEqual(linear.continue_args_for("grok", str(self.worktree)), [])

    def test_empty_group_is_not_a_session(self):
        group = self.group_for(str(self.worktree.resolve()))
        group.mkdir(parents=True)
        (group / "prompt_history.jsonl").write_text("{}\n")
        self.assertFalse(linear.grok_has_session(str(self.worktree)))

    def test_hashed_cwd_file(self):
        cwd = str(self.worktree.resolve())
        group = self.sessions / "slug-plus-hash"
        (group / "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee").mkdir(parents=True)
        (group / ".cwd").write_text(cwd + "\n")
        self.assertTrue(linear.grok_has_session(str(self.worktree)))

    def test_missing_sessions_root(self):
        self.assertFalse(linear.grok_has_session(str(self.worktree)))

    def test_other_agents_keep_continue_args(self):
        self.assertEqual(linear.continue_args_for("claude", str(self.worktree)), ["--continue"])
        self.assertEqual(linear.continue_args_for("codex", str(self.worktree)), ["resume", "--last"])
        self.assertEqual(linear.continue_args_for("gemini", str(self.worktree)), [])


if __name__ == "__main__":
    unittest.main()
