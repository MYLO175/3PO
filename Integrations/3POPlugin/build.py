#!/usr/bin/env python3
"""Build the two 3PO plugin distributions without accessing personal data."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import stat
import zipfile
from pathlib import Path

SOURCE = Path(__file__).resolve().parent
REPOSITORY = SOURCE.parents[1]
ICON = REPOSITORY / "MissionControl/Resources/Assets.xcassets/AppIcon.appiconset/icon_128x128@2x.png"
EXPECTED_SKILLS = {
    "setup", "status", "day", "week", "calendar", "reminders", "projects",
    "review", "find", "memory", "context", "instructions", "undo",
}


def read_catalog(source: Path) -> dict:
    catalog_path = source / "catalog.json"
    if catalog_path.is_symlink():
        raise ValueError("The catalog must be a regular source file.")
    catalog = json.loads(catalog_path.read_text())
    if catalog["name"] != "3po" or not re.fullmatch(r"\d+\.\d+\.\d+", catalog["version"]):
        raise ValueError("Invalid plugin identity or release version.")
    workflows = catalog["workflows"]
    names = [workflow["name"] for workflow in workflows]
    if len(names) != len(set(names)) or set(names) != EXPECTED_SKILLS:
        raise ValueError("The workflow catalog must name the thirteen shipped skills.")
    known = set(catalog["toolNames"])
    owned = [name for workflow in workflows for name in workflow["primaryTools"]]
    if len(known) != len(catalog["toolNames"]) or set(owned) != known or len(owned) != len(set(owned)):
        raise ValueError("Every declared tool needs exactly one responsible workflow.")
    for workflow in workflows:
        if workflow["skill"] != f"skills/{workflow['name']}/SKILL.md":
            raise ValueError("Skill paths must remain inside their canonical directories.")
        if not set(workflow["relatedTools"] + workflow["commonTools"]) <= known:
            raise ValueError("A workflow references an unknown tool.")
    if not all(len(prompt) <= 128 for prompt in catalog["defaultPrompts"]):
        raise ValueError("Starter prompts must be at most 128 characters.")
    return catalog


def source_files(source: Path, catalog: dict, include_openai: bool) -> list[Path]:
    allowed = {"README.md", "references/3po-contract.md", "scripts/launch-3po-mcp.sh"}
    for workflow in catalog["workflows"]:
        allowed.add(workflow["skill"])
        if include_openai:
            allowed.add(f"skills/{workflow['name']}/agents/openai.yaml")
    files = []
    for relative in sorted(allowed):
        path = source / relative
        if path.is_symlink() or any(parent.is_symlink() for parent in path.parents if parent != source.parent):
            raise ValueError(f"Symlinks are not distributable: {relative}")
        if not path.is_file() or not path.resolve().is_relative_to(source.resolve()):
            raise ValueError(f"Missing or escaping package source: {relative}")
        files.append(path)
    return files


def write_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n")


def manifests(catalog: dict, host: str) -> dict[str, dict]:
    identity = {
        "name": "3po", "version": catalog["version"],
        "description": catalog["description"], "author": {"name": "3PO"},
    }
    if host == "claude":
        return {
            ".claude-plugin/plugin.json": {**identity, "displayName": "3PO"},
            ".mcp.json": {"mcpServers": {"3po-workspace": {
                "command": "/bin/sh",
                "args": ["${CLAUDE_PLUGIN_ROOT}/scripts/launch-3po-mcp.sh"],
            }}},
        }
    interface = {
        "displayName": "3PO",
        "shortDescription": catalog["description"],
        "longDescription": "Calendar, Reminders, Projects, Review, memory and personal context through your local 3PO Mac app.",
        "developerName": "3PO",
        "category": "Productivity",
        "capabilities": ["Read", "Write"],
        "defaultPrompt": catalog["defaultPrompts"],
        "composerIcon": "./assets/icon.png",
        "logo": "./assets/icon.png",
    }
    return {
        "plugin.json": {
            "$schema": "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json",
            **identity,
            "extensions": {"com.openai": {
                "interface": interface,
                "requires_local_executor": True,
                "onboardingSkill": "./skills/setup/SKILL.md",
            }},
        },
        "mcp.json": {
            "$schema": "https://agent-plugins.org/schemas/1.0.0/mcp.schema.json",
            "mcpServers": {"3po-workspace": {
                "type": "stdio", "command": "./scripts/launch-3po-mcp.sh",
                "args": [], "cwd": "./",
            }},
        },
        ".codex-plugin/plugin.json": {
            **identity, "interface": interface, "requires_local_executor": True,
            "skills": "./skills/", "mcpServers": "./.mcp.json",
        },
        ".mcp.json": {"mcpServers": {"3po-workspace": {
            "command": "./scripts/launch-3po-mcp.sh", "args": [], "cwd": "./",
        }}},
    }


def validate_package(root: Path, catalog: dict, allowed: set[str]) -> None:
    actual = set()
    for path in root.rglob("*"):
        if path.is_symlink():
            raise ValueError("Package contains a symlink.")
        if path.is_file():
            actual.add(path.relative_to(root).as_posix())
    if actual != allowed:
        raise ValueError(f"Unexpected package contents: {sorted(actual ^ allowed)}")
    for relative in actual:
        path = root / relative
        if path.suffix in {".md", ".json", ".yaml", ".sh"}:
            text = path.read_text()
            if "/Users/" in text or "BEGIN PRIVATE KEY" in text:
                raise ValueError(f"Private path or key in package: {relative}")
        if path.name == "SKILL.md":
            text = path.read_text()
            if not text.startswith("---\n") or not re.search(r"^name: [a-z0-9-]+$", text, re.M):
                raise ValueError(f"Invalid skill header: {relative}")
            for target in re.findall(r"\]\(([^)]+)\)", text):
                if "://" in target:
                    continue
                linked = (path.parent / target).resolve()
                if not linked.is_relative_to(root.resolve()) or not linked.is_file():
                    raise ValueError(f"Broken or escaping skill reference: {relative}")
    names = {path.parent.name for path in root.glob("skills/*/SKILL.md")}
    if names != EXPECTED_SKILLS:
        raise ValueError("The rendered package lost a skill.")


def archive(root: Path, destination: Path) -> str:
    with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED) as output:
        for path in sorted(root.rglob("*")):
            if not path.is_file():
                continue
            info = zipfile.ZipInfo(path.relative_to(root).as_posix(), date_time=(2026, 1, 1, 0, 0, 0))
            mode = 0o755 if path.suffix == ".sh" else 0o644
            info.external_attr = (stat.S_IFREG | mode) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            output.writestr(info, path.read_bytes())
    return hashlib.sha256(destination.read_bytes()).hexdigest()


def build(output: Path, source: Path = SOURCE, icon: Path = ICON) -> dict:
    source = source.resolve()
    output = output.resolve()
    if output == source or output.is_relative_to(source) or source.is_relative_to(output):
        raise ValueError("Build output must be separate from plugin source.")
    catalog = read_catalog(source)
    if icon.is_symlink() or not icon.is_file():
        raise ValueError("The existing 3PO artwork must be a regular file.")
    output.mkdir(parents=True, exist_ok=True)
    if any(output.iterdir()):
        raise ValueError("Choose an empty build output directory to preserve other artifacts.")
    report = {"name": "3po", "version": catalog["version"], "skills": 13,
              "tools": len(catalog["toolNames"]), "hosts": {}}
    for host in ("openai", "claude"):
        marketplace = output / f"{host}-marketplace"
        package = marketplace / "plugins/3po"
        package.mkdir(parents=True)
        allowed = set()
        for path in source_files(source, catalog, host == "openai"):
            relative = path.relative_to(source)
            target = package / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, target)
            target.chmod(0o755 if target.suffix == ".sh" else 0o644)
            allowed.add(relative.as_posix())
        artwork = package / "assets/icon.png"
        artwork.parent.mkdir()
        shutil.copyfile(icon, artwork)
        allowed.add("assets/icon.png")
        for relative, data in manifests(catalog, host).items():
            write_json(package / relative, data)
            allowed.add(relative)
        validate_package(package, catalog, allowed)
        if host == "openai":
            market = {"name": "3po-local", "interface": {"displayName": "3PO"},
                      "plugins": [{"name": "3po", "source": {"source": "local", "path": "./plugins/3po"},
                                   "policy": {"installation": "AVAILABLE", "authentication": "ON_INSTALL"},
                                   "category": "Productivity"}]}
            market_path = marketplace / ".agents/plugins/marketplace.json"
        else:
            market = {"name": "3po-local", "description": "Personal 3PO workspace tools and workflows.",
                      "owner": {"name": "3PO"},
                      "plugins": [{"name": "3po", "source": "./plugins/3po",
                                   "description": catalog["description"], "version": catalog["version"]}]}
            market_path = marketplace / ".claude-plugin/marketplace.json"
        write_json(market_path, market)
        zip_path = output / f"3po-{host}-{catalog['version']}.zip"
        digest = archive(package, zip_path)
        report["hosts"][host] = {
            "marketplace": marketplace.relative_to(output).as_posix(),
            "package": package.relative_to(output).as_posix(),
            "archive": zip_path.name, "sha256": digest,
            "files": len(allowed), "bytes": zip_path.stat().st_size,
        }
    write_json(output / "release-manifest.json", report)
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=REPOSITORY / "build/plugins")
    options = parser.parse_args()
    print(json.dumps(build(options.output), indent=2))


if __name__ == "__main__":
    main()
