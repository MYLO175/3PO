#!/usr/bin/env python3
"""Package the supplied artwork as a multiresolution macOS icon using sips."""
from pathlib import Path
import struct
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
source = root / "MissionControl/Resources/AppIcon.png"
target = source.with_suffix(".icns")
chunks = []
with tempfile.TemporaryDirectory(prefix="mission-control-icon-") as directory:
    for kind, size in [("icp4", 16), ("icp5", 32), ("icp6", 64),
                       ("ic07", 128), ("ic08", 256), ("ic09", 512), ("ic10", 1024),
                       ("ic11", 32), ("ic12", 64), ("ic13", 256), ("ic14", 512)]:
        output = Path(directory) / f"{kind}.png"
        subprocess.run(["/usr/bin/sips", "-z", str(size), str(size), str(source),
                        "--out", str(output)], check=True, stdout=subprocess.DEVNULL)
        png = output.read_bytes()
        chunks.append(kind.encode("ascii") + struct.pack(">I", len(png) + 8) + png)
payload = b"".join(chunks)
target.write_bytes(b"icns" + struct.pack(">I", len(payload) + 8) + payload)
