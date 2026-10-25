#!/usr/bin/env python3
"""Reject incomplete app bundles before a build is reported as successful."""
from pathlib import Path
import argparse
import os
import plistlib
import subprocess


def verify(app: Path) -> None:
    contents = app / "Contents"
    with (contents / "Info.plist").open("rb") as source:
        info = plistlib.load(source)
    if info.get("CFBundleIdentifier") != "com.mylomichael.missioncontrol":
        raise ValueError("Unexpected app bundle identity")

    resources = contents / "Resources"
    required = [
        contents / "MacOS" / info["CFBundleExecutable"],
        resources / "MCPBridge/run.sh",
        resources / "MCPBridge/server.mjs",
        resources / "MCPBridge/package.json",
        resources / "WhatsAppBridge/Runtime/node",
        resources / "Graphiti/helper.py",
    ]
    missing = [str(path.relative_to(app)) for path in required if not path.is_file()]
    if missing:
        raise ValueError("App bundle is incomplete: " + ", ".join(missing))

    node = resources / "WhatsAppBridge/Runtime/node"
    if not os.access(node, os.X_OK):
        raise ValueError("The bundled Node runtime is not executable")
    subprocess.run(
        [str(node), "--input-type=module", "--eval",
         "await import('@modelcontextprotocol/sdk/server/index.js'); "
         "await import('@modelcontextprotocol/sdk/server/stdio.js'); "
         "await import('@modelcontextprotocol/sdk/types.js');"],
        cwd=resources / "MCPBridge", check=True, timeout=20,
    )
    print("App bundle verified: MCP bridge, SDK, bundled Node and Graphiti helper present.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    args = parser.parse_args()
    try:
        verify(args.app.resolve())
    except (OSError, KeyError, ValueError, subprocess.SubprocessError) as error:
        parser.exit(1, f"Bundle verification failed: {error}\n")
