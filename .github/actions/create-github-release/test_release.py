#!/usr/bin/env python3

from __future__ import annotations

import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import textwrap
import unittest


ACTION_PATH = Path(__file__).resolve().parent


class CreateGitHubReleaseTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        self.bin_dir = self.root / "bin"
        self.bin_dir.mkdir()
        self.calls_path = self.root / "calls.jsonl"
        self.output_path = self.root / "github-output"

        fake_command = textwrap.dedent(
            """\
            #!/usr/bin/env python3
            import json
            import os
            from pathlib import Path
            import sys

            argv = [Path(sys.argv[0]).name, *sys.argv[1:]]
            with Path(os.environ["CALLS_PATH"]).open("a", encoding="utf-8") as calls:
                calls.write(json.dumps(argv) + "\\n")

            if argv[0] == "gh" and argv[1:3] == ["release", "view"]:
                if "--json" in argv:
                    print("https://github.test/example/releases/tag/v1.2.3")
                elif os.environ.get("RELEASE_EXISTS") != "true":
                    raise SystemExit(1)
            """
        )
        for name in ("gh", "git"):
            path = self.bin_dir / name
            path.write_text(fake_command, encoding="utf-8")
            path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def run_release(self, **overrides: str) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        env.update(
            {
                "ACTION_PATH": str(ACTION_PATH),
                "CALLS_PATH": str(self.calls_path),
                "FAIL_ON_UNMATCHED_FILES": "true",
                "FILES": "",
                "GH_TOKEN": "test-token",
                "GITHUB_OUTPUT": str(self.output_path),
                "PATH": f"{self.bin_dir}{os.pathsep}{env['PATH']}",
                "PRERELEASE": "false",
                "RELEASE_EXISTS": "false",
                "RELEASE_NAME": "",
                "REMOTE": "origin",
                "TAG": "v1.2.3",
                "TAG_EXISTS": "false",
            }
        )
        env.update(overrides)
        return subprocess.run(
            ["bash", str(ACTION_PATH / "release.sh")],
            cwd=self.root,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )

    def calls(self) -> list[list[str]]:
        return [json.loads(line) for line in self.calls_path.read_text().splitlines()]

    def test_creates_tag_and_release_with_recursive_assets(self) -> None:
        (self.root / "web asset.tar").write_text("web", encoding="utf-8")
        nested = self.root / "egui-artifacts" / "linux" / "nested"
        nested.mkdir(parents=True)
        (nested / "tuner binary").write_text("bin", encoding="utf-8")

        result = self.run_release(
            FILES="web asset.tar\negui-artifacts/**/*",
            PRERELEASE="true",
            RELEASE_NAME="Tuner 1.2.3",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls()
        self.assertIn(
            ["git", "tag", "-a", "-m", "Release v1.2.3", "--", "v1.2.3"],
            calls,
        )
        self.assertIn(
            ["git", "push", "--", "origin", "refs/tags/v1.2.3"], calls
        )
        self.assertIn(
            [
                "gh",
                "release",
                "create",
                "--verify-tag",
                "--generate-notes",
                "--title",
                "Tuner 1.2.3",
                "--prerelease",
                "--",
                "v1.2.3",
                "web asset.tar",
                os.path.join("egui-artifacts", "linux", "nested", "tuner binary"),
            ],
            calls,
        )
        self.assertEqual(
            self.output_path.read_text(),
            "url=https://github.test/example/releases/tag/v1.2.3\n",
        )

    def test_existing_release_uploads_assets_with_clobber(self) -> None:
        (self.root / "artifact.zip").write_text("zip", encoding="utf-8")

        result = self.run_release(
            FILES="artifact.zip",
            RELEASE_EXISTS="true",
            TAG_EXISTS="true",
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls()
        self.assertFalse(any(call[0:2] == ["git", "tag"] for call in calls))
        self.assertFalse(any(call[0:2] == ["git", "push"] for call in calls))
        self.assertIn(
            [
                "gh",
                "release",
                "upload",
                "--clobber",
                "--",
                "v1.2.3",
                "artifact.zip",
            ],
            calls,
        )

    def test_unmatched_pattern_fails_before_tag_creation(self) -> None:
        result = self.run_release(FILES="missing/**/*.zip")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("matched no files", result.stderr)
        self.assertFalse(self.calls_path.exists())

    def test_unmatched_pattern_can_be_ignored(self) -> None:
        result = self.run_release(
            FAIL_ON_UNMATCHED_FILES="false", FILES="missing/**/*.zip"
        )

        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Warning: release asset pattern matched no files", result.stderr)

    def test_rejects_invalid_boolean_before_running_commands(self) -> None:
        result = self.run_release(PRERELEASE="yes")

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("prerelease must be 'true' or 'false'", result.stderr)
        self.assertFalse(self.calls_path.exists())


if __name__ == "__main__":
    unittest.main()
