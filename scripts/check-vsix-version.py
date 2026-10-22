#!/usr/bin/env python3
"""Check that a proposed VS Code theme bundle follows the manual version rule.

Compare the current commit with a base commit. If packaged extension files
changed, the version in vscode-extension/package.json must increase and the
newly named VSIX must be committed. The previous VSIX must be removed.

If packaged files did not change, the extension version and VSIX must stay the
same. In every case, exactly one tracked VSIX must exist, and its filename must
match the manifest version. A first-time bundle is allowed when the base has
no extension manifest.
"""

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys


MANIFEST = "vscode-extension/package.json"
VSIX_DIR = "vscode-extension/"
SEMVER = re.compile(
    r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)"
    r"(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$"
)


def git(*args):
    return subprocess.run(
        ["git", *args], check=True, capture_output=True, text=True
    ).stdout


def git_file(revision, path):
    result = subprocess.run(
        ["git", "show", f"{revision}:{path}"], capture_output=True, text=True
    )
    if result.returncode:
        if "does not exist in" in result.stderr or "exists on disk, but not in" in result.stderr:
            return None
        raise RuntimeError(result.stderr.strip())
    return result.stdout


def version_key(version):
    match = SEMVER.fullmatch(version)
    if not match:
        raise ValueError(f"invalid extension version: {version!r}")
    major, minor, patch, prerelease = match.groups()
    if prerelease is None:
        prekey = (1,)
    else:
        parts = prerelease.split(".")
        if any(part.isdigit() and len(part) > 1 and part.startswith("0") for part in parts):
            raise ValueError(f"invalid numeric prerelease in {version!r}")
        prekey = (0, tuple((0, int(part)) if part.isdigit() else (1, part) for part in parts))
    return (int(major), int(minor), int(patch), prekey)


def packaged_source_changed(paths, old_manifest, new_manifest):
    # The first bundle has no older extension to compare, so treat it as a change.
    if old_manifest is None:
        return True
    # Ignore the version field here; it is the response to a source change.
    old_payload = {key: value for key, value in old_manifest.items() if key != "version"}
    new_payload = {key: value for key, value in new_manifest.items() if key != "version"}
    return old_payload != new_payload or any(
        path.startswith(VSIX_DIR)
        and path != MANIFEST
        and path != f"{VSIX_DIR}.gitignore"
        and not path.endswith(".vsix")
        for path in paths
    )


def validate(old_manifest, new_manifest, changed, tracked_vsix, vsix_exists):
    version = new_manifest["version"]
    new_key = version_key(version)
    expected_vsix = f"{VSIX_DIR}chromaticli-themes-{version}.vsix"
    # Ship exactly the VSIX named by the current manifest, with no old bundle.
    if tracked_vsix != [expected_vsix] or not vsix_exists:
        raise ValueError(f"expected one tracked VSIX: {expected_vsix}; found {tracked_vsix}")

    sources_changed = packaged_source_changed(changed, old_manifest, new_manifest)
    vsix_changed = expected_vsix in changed

    if old_manifest is not None:
        old_version = old_manifest["version"]
        old_key = version_key(old_version)
        # Changed extension content needs a manual version increase.
        if sources_changed and new_key <= old_key:
            raise ValueError(
                f"packaged extension sources changed; increase version above {old_version}"
            )
        if not sources_changed and new_key != old_key:
            raise ValueError("extension version changed without packaged source changes")
    # The committed VSIX must change together with its packaged sources.
    if sources_changed and not vsix_changed:
        raise ValueError(f"packaged extension sources changed; add {expected_vsix}")
    if not sources_changed and vsix_changed:
        raise ValueError("VSIX changed without packaged source changes")
    print(f"OK: extension {version}; packaged sources {'changed' if sources_changed else 'unchanged'}")


def check(base):
    new_manifest = json.loads(git_file("HEAD", MANIFEST))
    tracked = git("ls-tree", "-r", "--name-only", "HEAD", "--", VSIX_DIR).splitlines()
    tracked_vsix = [path for path in tracked if path.endswith(".vsix")]
    changed = set(git("diff", "--name-only", base, "HEAD", "--", VSIX_DIR).splitlines())
    old_text = git_file(base, MANIFEST)
    old_manifest = json.loads(old_text) if old_text is not None else None
    expected_vsix = f"{VSIX_DIR}chromaticli-themes-{new_manifest['version']}.vsix"
    validate(old_manifest, new_manifest, changed, tracked_vsix, Path(expected_vsix).is_file())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("base", help="base commit to compare with HEAD")
    args = parser.parse_args()
    try:
        check(args.base)
    except (KeyError, TypeError, ValueError, RuntimeError, subprocess.CalledProcessError) as exc:
        parser.exit(1, f"check-vsix-version: {exc}\n")


if __name__ == "__main__":
    main()
