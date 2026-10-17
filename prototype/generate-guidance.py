"""Compile the two repo-owned skill bodies into literal Swift strings."""
import argparse
from pathlib import Path
import re
import tempfile

ROOT = Path(__file__).resolve().parent.parent
SKILLS = (("wait-what", "explain"), ("teach", "teach"))


def load_skill(path, name):
    with Path(path).open("rb") as handle:
        data = handle.read(16_385)
    if len(data) > 16_384:
        raise ValueError(f"The {name} skill exceeds the 16 KiB build limit.")
    text = data.decode("utf-8")
    if not text.startswith("---\n") or "\n---\n" not in text[4:]:
        raise ValueError(f"The {name} skill needs YAML frontmatter.")
    metadata, body = text[4:].split("\n---\n", 1)
    if re.findall(r"^name:\s*(\S+)\s*$", metadata, re.MULTILINE) != [name]:
        raise ValueError(f"The {name} skill has a missing or mismatched name.")
    if not re.search(r"^description:\s*\S.+$", metadata, re.MULTILINE):
        raise ValueError(f"The {name} skill needs a description.")
    body = body.strip()
    if not body:
        raise ValueError(f"The {name} skill has no instructions.")
    return body


def swift_string(text):
    escaped = []
    for char in text:
        if char == "\\":
            escaped.append("\\\\")
        elif char == '"':
            escaped.append('\\"')
        elif char == "\n":
            escaped.append("\\n")
        elif char == "\r":
            escaped.append("\\r")
        elif char == "\t":
            escaped.append("\\t")
        elif ord(char) < 32 or 127 <= ord(char) < 160 or ord(char) in (0x2028, 0x2029):
            escaped.append(f"\\u{{{ord(char):x}}}")
        else:
            escaped.append(char)
    return '"' + "".join(escaped) + '"'


def generate(root, output):
    # Fixed local inputs only. Frontmatter is provenance, not model instructions.
    bodies = [(field, load_skill(Path(root) / "skills" / name / "SKILL.md", name))
              for name, field in SKILLS]
    source = "// Generated from skills/*/SKILL.md by generate-guidance.py. Do not edit.\n"
    source += "enum DiscussionSkills {\n"
    source += "".join(f"    static let {field} = {swift_string(body)}\n" for field, body in bodies)
    source += "}\n"
    output = Path(output)
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=output.parent,
                                         prefix=".maie-guidance-", delete=False) as handle:
            temporary = Path(handle.name)
            handle.write(source)
        temporary.replace(output)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path,
                        default=ROOT / "prototype" / ".build" / "DiscussionSkills.generated.swift")
    args = parser.parse_args()
    try:
        generate(ROOT, args.output)
    except (OSError, ValueError) as error:
        parser.exit(1, f"Skill build stopped: {error}\n")
    print("Compiled the wait-what and teach skill bodies.")


if __name__ == "__main__":
    main()
