"""Synthetic setup checks. Never read or change the user's Claude settings."""
import importlib.util
import json
from pathlib import Path
import shlex
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("maie_setup", Path(__file__).with_name("setup-hook.py"))
SETUP = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SETUP)


class SetupChecks(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="maie-setup-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.project = self.root / "fictional project"
        self.project.mkdir()
        self.helper = self.root / "Maie build" / "maie-hook"
        self.helper.parent.mkdir()
        self.helper.write_text("#!/bin/sh\nexit 0\n")
        self.helper.chmod(0o700)
        self.settings = self.project / ".claude" / "settings.local.json"

    def configure(self, apply=True):
        return SETUP.configure(self.project, self.helper, apply=apply)

    def seed(self, data):
        self.settings.parent.mkdir(exist_ok=True)
        self.settings.write_text(json.dumps(data))

    def test_fresh_preview_apply_and_repeat(self):
        self.assertTrue(self.configure(apply=False))
        self.assertFalse(self.settings.parent.exists())
        self.assertTrue(self.configure())
        data = json.loads(self.settings.read_text())
        hook = data["hooks"]["PreToolUse"][0]["hooks"][0]
        self.assertEqual(shlex.split(hook["command"]), [str(self.helper)])
        self.assertEqual((hook["timeout"], hook["onFailure"]), (1830, "block"))
        self.assertEqual(self.settings.stat().st_mode & 0o777, 0o600)
        before = self.settings.read_bytes()
        self.assertFalse(self.configure())
        self.assertEqual(self.settings.read_bytes(), before)

    def test_preserve_unrelated_settings_and_hooks(self):
        other = {"matcher": "AskUserQuestion", "hooks": [{"type": "command", "command": "other-helper"}]}
        original = {"permissions": {"allow": ["Read"]}, "hooks": {
            "PreToolUse": [other], "Stop": [{"hooks": [{"type": "command", "command": "stop-helper"}]}]}}
        self.seed(original)
        self.configure()
        updated = json.loads(self.settings.read_text())
        self.assertEqual(updated["permissions"], original["permissions"])
        self.assertEqual(updated["hooks"]["Stop"], original["hooks"]["Stop"])
        self.assertEqual(updated["hooks"]["PreToolUse"][0], other)
        self.assertEqual(len(updated["hooks"]["PreToolUse"]), 2)

    def test_conflicts_and_invalid_json_leave_file_unchanged(self):
        for data in [
            {"hooks": []},
            {"hooks": {"PreToolUse": [{"hooks": "bad"}]}},
            {"hooks": {"PreToolUse": [{"matcher": "AskUserQuestion", "hooks": [
                {"command": str(self.helper)}, {"command": str(self.helper)}]}]}},
            {"hooks": {"PreToolUse": [{"matcher": "Bash", "hooks": [{"command": str(self.helper)}]}]}},
            {"hooks": {"PreToolUse": [{"matcher": "AskUserQuestion", "hooks": [{"command": "/tmp/other/maie-hook"}]}]}},
            {"hooks": {"PreToolUse": [{"matcher": "AskUserQuestion", "hooks": [{"command": str(self.helper), "async": True}]}]}}
        ]:
            self.seed(data)
            before = self.settings.read_bytes()
            with self.assertRaises(ValueError):
                self.configure()
            self.assertEqual(self.settings.read_bytes(), before)
        self.settings.write_text("{invalid")
        with self.assertRaises(ValueError):
            self.configure()
        self.assertEqual(self.settings.read_text(), "{invalid")

    def test_parameterized_helpers_are_conflicts_without_overwriting_settings(self):
        for executable in [str(self.helper), "/tmp/other Maie/maie-hook"]:
            command = shlex.quote(executable) + " --timeout-seconds 3"
            self.seed({"hooks": {"PreToolUse": [{"matcher": "AskUserQuestion",
                "hooks": [{"type": "command", "command": command}]}]}})
            before = self.settings.read_bytes()
            for apply in [False, True]:
                with self.assertRaises(ValueError):
                    self.configure(apply=apply)
                self.assertEqual(self.settings.read_bytes(), before)

    def test_linked_settings_and_missing_helper_are_rejected(self):
        external = self.root / "external.json"
        external.write_text("{}")
        self.settings.parent.mkdir()
        self.settings.symlink_to(external)
        with self.assertRaises(ValueError):
            self.configure()
        self.assertEqual(external.read_text(), "{}")
        self.settings.unlink()
        self.settings.parent.rmdir()
        self.settings.parent.symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(ValueError):
            self.configure()
        with self.assertRaises(ValueError):
            SETUP.configure(self.project, self.root / "missing")


if __name__ == "__main__":
    unittest.main()
