"""Offline checks for skill compilation; no model, account or GUI access."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("maie_guidance", HERE / "generate-guidance.py")
GUIDANCE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(GUIDANCE)


class SkillChecks(unittest.TestCase):
    def test_frontmatter_is_not_sent_as_guidance(self):
        with tempfile.TemporaryDirectory(prefix="maie-skill-") as temporary:
            path = Path(temporary) / "SKILL.md"
            path.write_text("---\nname: teach\ndescription: METADATA_NOT_SENT\n---\n\nOne concept.\n")
            body = GUIDANCE.load_skill(path, "teach")
            self.assertEqual(body, "One concept.")
            self.assertNotIn("METADATA_NOT_SENT", body)

    def test_invalid_or_missing_skill_does_not_replace_generated_output(self):
        with tempfile.TemporaryDirectory(prefix="maie-skill-") as temporary:
            root = Path(temporary)
            output = root / "generated.swift"
            output.write_text("previous generated output")
            for invalid in [
                "---\nname: other\ndescription: Example\n---\nBody",
                "---\nname: wait-what\ndescription: Example\n---\n ",
                "Missing frontmatter",
                "x" * 16_385,
            ]:
                path = root / "skills" / "wait-what" / "SKILL.md"
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(invalid)
                with self.assertRaises(ValueError):
                    GUIDANCE.generate(root, output)
                self.assertEqual(output.read_text(), "previous generated output")
            path.write_text("---\nname: wait-what\ndescription: Example\n---\nA real body.")
            with self.assertRaises(FileNotFoundError):
                GUIDANCE.generate(root, output)
            self.assertEqual(output.read_text(), "previous generated output")

    def test_swift_literals_preserve_text_without_executing_interpolation(self):
        # Preserve Unicode/control/quote coverage with escapes in English source.
        payload = '"quoted"\n\\(fatalError("must stay text"))\r\t\x00\b\f\u2028\u03b1\U0001fae7'
        expected = ", ".join(str(byte) for byte in payload.encode("utf-8"))
        source = "let text = " + GUIDANCE.swift_string(payload) + "\n"
        source += "precondition(Array(text.utf8) == [" + expected + "])\n"
        with tempfile.TemporaryDirectory(prefix="maie-skill-swift-") as temporary:
            root = Path(temporary)
            fixture = root / "main.swift"
            fixture.write_text(source)
            binary = root / "literal-check"
            subprocess.run(["swiftc", "-module-cache-path", str(HERE / ".build" / "module-cache"),
                            str(fixture), "-o", str(binary)], check=True, capture_output=True)
            subprocess.run([str(binary)], check=True, capture_output=True)


if __name__ == "__main__":
    unittest.main()
