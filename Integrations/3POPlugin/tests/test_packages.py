import importlib.util
import json
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

SOURCE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("threepo_plugin_build", SOURCE / "build.py")
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class PackageChecks(unittest.TestCase):
    def test_portable_launcher_is_an_executable_inside_the_package(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            report = builder.build(base)
            root = base / report["hosts"]["openai"]["package"]
            config = json.loads((root / "mcp.json").read_text())["mcpServers"]["3po-workspace"]
            self.assertTrue(config["command"].startswith("./"))
            executable = (root / config["command"]).resolve()
            self.assertTrue(executable.is_relative_to(root.resolve()))
            self.assertTrue(executable.is_file())
            self.assertTrue(os.access(executable, os.X_OK))
            self.assertTrue(config["cwd"].startswith("./"))
            self.assertEqual((root / config["cwd"]).resolve(), root.resolve())

    def test_archives_are_reproducible_and_have_one_skill_source(self):
        with tempfile.TemporaryDirectory(prefix="3po package checks ") as temporary:
            base = Path(temporary)
            first = builder.build(base / "first")
            second = builder.build(base / "second")
            for host in ("openai", "claude"):
                self.assertEqual(first["hosts"][host]["sha256"], second["hosts"][host]["sha256"])
                archive = base / "first" / first["hosts"][host]["archive"]
                with zipfile.ZipFile(archive) as package:
                    skills = [name for name in package.namelist() if name.endswith("/SKILL.md")]
                    self.assertEqual(len(skills), 13)
                    for name in skills:
                        self.assertEqual(package.read(name), (SOURCE / name).read_bytes())
                    self.assertFalse(any(name.startswith("commands/") for name in package.namelist()))
                    launcher = package.getinfo("scripts/launch-3po-mcp.sh")
                    self.assertEqual((launcher.external_attr >> 16) & 0o777, 0o755)
                    if host == "claude":
                        self.assertIn(".claude-plugin/plugin.json", package.namelist())
                        self.assertNotIn("plugin.json", package.namelist())
                    else:
                        self.assertIn("plugin.json", package.namelist())

    def test_private_source_files_are_not_packaged(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            source = base / "source"
            shutil.copytree(SOURCE, source)
            (source / "connection.json").write_text('{"token":"fixture-private-value"}')
            (source / ".env").write_text("FIXTURE_SECRET=do-not-package")
            (source / "personal-notes.md").write_text("Private fixture note.")
            report = builder.build(base / "output", source)
            for host in report["hosts"].values():
                with zipfile.ZipFile(base / "output" / host["archive"]) as package:
                    joined = b"".join(package.read(name) for name in package.namelist())
                    self.assertNotIn(b"fixture-private-value", joined)
                    self.assertNotIn(b"do-not-package", joined)
                    self.assertNotIn("personal-notes.md", package.namelist())

    def test_symlinked_skill_is_rejected(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            source = base / "source"
            shutil.copytree(SOURCE, source)
            original = source / "skills/day/SKILL.md"
            outside = base / "outside.md"
            outside.write_text(original.read_text())
            original.unlink()
            original.symlink_to(outside)
            with self.assertRaisesRegex(ValueError, "Symlink"):
                builder.build(base / "output", source)

    def test_existing_output_is_preserved(self):
        with tempfile.TemporaryDirectory() as temporary:
            output = Path(temporary)
            protected = output / "other-artifact.txt"
            protected.write_text("Keep this.")
            with self.assertRaisesRegex(ValueError, "empty build output"):
                builder.build(output)
            self.assertEqual(protected.read_text(), "Keep this.")

    def test_tool_catalog_rejects_an_unowned_tool(self):
        with tempfile.TemporaryDirectory() as temporary:
            source = Path(temporary) / "source"
            shutil.copytree(SOURCE, source)
            catalog = json.loads((source / "catalog.json").read_text())
            catalog["toolNames"].append("unexpected_write")
            (source / "catalog.json").write_text(json.dumps(catalog))
            with self.assertRaisesRegex(ValueError, "responsible workflow"):
                builder.read_catalog(source)


@unittest.skipUnless(sys.platform == "darwin", "The launch target is macOS.")
class LauncherChecks(unittest.TestCase):
    def fixture(self, root, name="3PO with spaces.app", bundle_id="com.mylomichael.missioncontrol"):
        app = root / name
        resources = app / "Contents/Resources/MCPBridge"
        resources.mkdir(parents=True)
        (app / "Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleIdentifier": bundle_id}))
        (resources / "run.sh").write_text("#!/bin/zsh\nprintf 'fixture-launch-ok\\n'\n")
        return app

    def run_launcher(self, app):
        environment = {**os.environ, "THREEPO_APP_PATH": str(app)}
        return subprocess.run(
            ["/bin/sh", str(SOURCE / "scripts/launch-3po-mcp.sh")],
            env=environment, capture_output=True, text=True, timeout=10,
        )

    def test_app_path_is_literal_even_with_shell_characters(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            app = self.fixture(root, "3PO $(touch injected) ; literal.app")
            result = self.run_launcher(app)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.strip(), "fixture-launch-ok")
            self.assertFalse((root / "injected").exists())

    def test_explicit_missing_app_does_not_fall_back(self):
        with tempfile.TemporaryDirectory() as temporary:
            result = self.run_launcher(Path(temporary) / "Missing.app")
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("configured 3PO application", result.stderr)

    def test_another_bundle_cannot_be_launched(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = self.fixture(Path(temporary), bundle_id="com.example.other")
            result = self.run_launcher(app)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn("fixture-launch-ok", result.stdout)

    def test_missing_bridge_has_a_specific_failure(self):
        with tempfile.TemporaryDirectory() as temporary:
            app = self.fixture(Path(temporary))
            (app / "Contents/Resources/MCPBridge/run.sh").unlink()
            result = self.run_launcher(app)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("bridge is missing", result.stderr)


if __name__ == "__main__":
    unittest.main()
