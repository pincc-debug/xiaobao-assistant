#!/usr/bin/env python3
"""Bundle the local FFmpeg executable and its non-system dylibs for the macOS app."""
import os
from pathlib import Path
import shutil
import subprocess
import sys

app = Path(sys.argv[1])
source = Path(os.environ.get("FFMPEG_BINARY", shutil.which("ffmpeg") or "/opt/homebrew/bin/ffmpeg")).resolve()
if not source.is_file():
    raise SystemExit("FFmpeg is required to build the live audio component")
helpers = app / "Contents/Helpers"
frameworks = app / "Contents/Frameworks"
helpers.mkdir(parents=True, exist_ok=True)
frameworks.mkdir(parents=True, exist_ok=True)

def dependencies(path):
    lines = subprocess.check_output(["otool", "-L", str(path)], text=True).splitlines()[1:]
    return [line.strip().split(" (", 1)[0] for line in lines]

seen = {}
def bundle(src, dest):
    src = src.resolve()
    if dest in seen:
        if seen[dest] != src:
            raise RuntimeError("Conflicting bundled library: " + dest.name)
        return
    seen[dest] = src
    shutil.copy2(src, dest)
    dest.chmod(dest.stat().st_mode | 0o200)
    changes = []
    for dep in dependencies(src):
        if dep.startswith(("/usr/lib/", "/System/Library/")):
            continue
        if not dep.startswith("/"):
            raise RuntimeError("Unsupported dependency path: " + dep)
        dep_source = Path(dep).resolve()
        if dep_source == src:
            continue
        dep_dest = frameworks / Path(dep).name
        bundle(dep_source, dep_dest)
        replacement = ("@loader_path/../Frameworks/" if dest.parent == helpers else "@loader_path/") + dep_dest.name
        changes += ["-change", dep, replacement]
    if dest.suffix == ".dylib":
        changes += ["-id", "@rpath/" + dest.name]
    if changes:
        subprocess.run(["install_name_tool", *changes, str(dest)], check=True, capture_output=True)
    subprocess.run(["codesign", "--force", "--sign", "-", str(dest)], check=True, capture_output=True)

bundle(source, helpers / "ffmpeg")
subprocess.run([str(helpers / "ffmpeg"), "-version"], check=True, stdout=subprocess.DEVNULL)
print("Bundled FFmpeg and", len(seen) - 1, "libraries")
