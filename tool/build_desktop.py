#!/usr/bin/env python3
"""Build and package the native desktop app. Requires Python 3.9+ and Flutter."""

import argparse
import hashlib
import platform
import re
import shutil
import subprocess
import sys
import tarfile
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HOSTS = {"Linux": "linux", "Windows": "windows", "Darwin": "macos"}


def package(target, arch, version):
    destination = ROOT / "dist"
    destination.mkdir(exist_ok=True)

    if target == "macos":
        bundle = ROOT / "build/macos/Build/Products/Release/wow_butler.app"
        executable = bundle / "Contents/MacOS/wow_butler"
    elif target == "windows":
        bundle = ROOT / f"build/windows/{arch}/runner/Release"
        executable = bundle / "wow_butler.exe"
    else:
        bundle = ROOT / f"build/linux/{arch}/release/bundle"
        executable = bundle / "wow_butler"

    if not executable.is_file():
        raise RuntimeError(f"Release executable missing: {executable}")

    if target == "macos":
        architectures = set(subprocess.check_output(["lipo", "-archs", str(executable)], text=True).split())
        if architectures == {"arm64", "x86_64"}:
            arch = "universal"
        elif architectures == {"arm64"}:
            arch = "arm64"
        elif architectures == {"x86_64"}:
            arch = "x64"
        else:
            raise RuntimeError(f"Unexpected macOS architectures: {architectures}")

    name = f"wow-butler-{version}-{target}-{arch}"
    if target == "linux":
        output = destination / f"{name}.tar.gz"
        with tarfile.open(output, "w:gz") as archive:
            archive.add(bundle, arcname="wow-butler")
    elif target == "macos":
        # ditto preserves framework symlinks, executable modes and app metadata.
        output = destination / f"{name}.zip"
        subprocess.run(
            ["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(bundle), str(output)],
            check=True,
        )
    else:
        output = destination / f"{name}.zip"
        with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED) as archive:
            for file in sorted(bundle.rglob("*")):
                if file.is_file():
                    archive.write(file, Path("wow-butler") / file.relative_to(bundle))

    digest = hashlib.sha256()
    with output.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    output.with_name(output.name + ".sha256").write_text(
        f"{digest.hexdigest()}  {output.name}\n", encoding="utf-8"
    )
    print(f"Packaged: {output}")
    return output


def main():
    host = HOSTS.get(platform.system())
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", nargs="?", choices=HOSTS.values(), default=host)
    parser.add_argument("--skip-build", action="store_true", help="Package an existing release build")
    args = parser.parse_args()
    if host is None or args.target != host:
        parser.error("Run this command on the target operating system; Flutter cannot cross-build desktop apps.")

    machine = platform.machine().lower()
    if machine in ("amd64", "x86_64"):
        arch = "x64"
    elif machine in ("arm64", "aarch64"):
        arch = "arm64"
    else:
        parser.error(f"Unsupported host architecture: {machine}")
    version = re.search(r"^version:\s*([^\s#]+)", (ROOT / "pubspec.yaml").read_text(encoding="utf-8"), re.MULTILINE)
    if version is None:
        parser.error("pubspec.yaml is missing its version")

    if not args.skip_build:
        flutter = shutil.which("flutter")
        if flutter is None:
            parser.error("Flutter is missing from PATH. Install the version specified in mise.toml.")
        subprocess.run([flutter, "pub", "get", "--enforce-lockfile"], cwd=ROOT, check=True)
        subprocess.run([flutter, "build", args.target, "--release", "--no-pub"], cwd=ROOT, check=True)
    package(args.target, arch, version.group(1))


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"Build failed: {error}", file=sys.stderr)
        sys.exit(1)
