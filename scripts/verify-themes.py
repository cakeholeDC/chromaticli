#!/usr/bin/env python3
# chromaticli :: verify-themes.py
# Checks every entry in themes.json against the live VSCode marketplace:
#   - extension_id resolves to a real published extension
#   - theme_id matches one of the labels the extension contributes
#   - entries with extension_id=null are validated against a hard-coded
#     list of VSCode built-in theme display names
#   - category is one of the allowed bucket values
#
# Exit codes: 0 = all clean, 1 = at least one entry needs fixing.
#
# Run after editing themes.json, before committing. Network required.
# CI runs this on every push/PR via the `verify-themes` job in
# .github/workflows/ci.yml.

from __future__ import annotations

import json
import pathlib
import sys
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
THEMES = ROOT / "themes.json"

API = "https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery"
HEADERS = {
    "Accept": "application/json;api-version=3.0-preview.1",
    "Content-Type": "application/json",
    "User-Agent": "chromaticli-verify/1.0",
}
# Marketplace gallery flags: IncludeVersions(1) | IncludeFiles(2) | IncludeAssetUri(0x80).
FLAGS = 0x83
# filterType 7 = ExtensionName (publisher.name)
FILTER_EXT_NAME = 7

# Stock VSCode color themes that ship with the editor (no extension required).
# Source: microsoft/vscode extensions/theme-*/package.json. Update as the set
# evolves; the verifier flags BUILTIN_UNKNOWN if you add a built-in theme not
# listed here so we don't silently accept typos.
BUILTINS = {
    "Default Dark Modern", "Default Light Modern",
    "Default Dark+", "Default Light+",
    "Dark (Visual Studio)", "Light (Visual Studio)",
    "Visual Studio Dark", "Visual Studio Light",
    "Dark High Contrast", "Light High Contrast",
    "Default High Contrast", "Default High Contrast Light",
    "Abyss", "Kimbie Dark", "Monokai", "Monokai Dimmed",
    "Quiet Light", "Red", "Solarized Dark", "Solarized Light",
    "Tomorrow Night Blue",
}


def query_ext(ext_id: str) -> tuple[str, str, list[str]]:
    payload = {
        "filters": [{
            "criteria": [{"filterType": FILTER_EXT_NAME, "value": ext_id}],
            "pageSize": 1,
        }],
        "flags": FLAGS,
    }
    req = urllib.request.Request(
        API, data=json.dumps(payload).encode("utf-8"),
        headers=HEADERS, method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            data = json.loads(r.read())
    except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError, OSError) as e:
        return ("ERROR", str(e), [])

    exts = data.get("results", [{}])[0].get("extensions", [])
    if not exts:
        return ("MISSING", "no marketplace match", [])

    versions = exts[0].get("versions", [])
    if not versions:
        return ("ERROR", "no versions returned (try a different API flag combo)", [])

    files = versions[0].get("files", [])
    manifest_url = next(
        (f["source"] for f in files if f.get("assetType") == "Microsoft.VisualStudio.Code.Manifest"),
        None,
    )
    if not manifest_url:
        return ("ERROR", "no manifest file in latest version", [])

    try:
        with urllib.request.urlopen(manifest_url, timeout=15) as r:
            manifest = json.loads(r.read())
    except Exception as e:
        return ("ERROR", f"manifest fetch: {e}", [])

    contributed = manifest.get("contributes", {}).get("themes", [])
    return ("OK", "", [t.get("label", "") for t in contributed])


VALID_CATEGORIES = {"dark-warm", "dark-cool", "light"}


def main() -> int:
    data = json.loads(THEMES.read_text())
    themes = data["themes"]
    failures: list[str] = []
    rows: list[tuple[str, str, str]] = []

    for tid, t in themes.items():
        # Category check (offline, cheap — do it first).
        cat = t.get("category")
        if cat not in VALID_CATEGORIES:
            rows.append((tid, "BAD_CATEGORY",
                         f"category={cat!r}; must be one of {sorted(VALID_CATEGORIES)}"))
            failures.append(tid)
            continue

        vs = t["vscode"]
        theme_id = vs["theme_id"]
        ext_id = vs.get("extension_id")

        if ext_id is None:
            if theme_id in BUILTINS:
                rows.append((tid, "BUILTIN_OK", f"'{theme_id}' is a VSCode built-in"))
            else:
                msg = (f"'{theme_id}' is marked as built-in (extension_id=null) but isn't in "
                       f"the known built-ins set. Either add it to BUILTINS in this script "
                       f"or supply a real extension_id.")
                rows.append((tid, "BUILTIN_UNKNOWN", msg))
                failures.append(tid)
            continue

        status, err, labels = query_ext(ext_id)
        if status == "OK":
            if theme_id in labels:
                rows.append((tid, "OK", f"'{theme_id}' confirmed (ext {ext_id})"))
            else:
                msg = (f"extension {ext_id} exists but doesn't provide '{theme_id}'. "
                       f"It provides: {labels}")
                rows.append((tid, "MISMATCH", msg))
                failures.append(tid)
        elif status == "MISSING":
            rows.append((tid, "MISSING", f"extension {ext_id} not found in marketplace"))
            failures.append(tid)
        else:
            rows.append((tid, "ERROR", err))
            failures.append(tid)

    print(f"{'theme-id':<22} {'status':<18} detail")
    print("-" * 110)
    for tid, status, detail in rows:
        print(f"{tid:<22} {status:<18} {detail}")

    print()
    if failures:
        print(f"FAIL: {len(failures)} entr{'y' if len(failures) == 1 else 'ies'} need attention: "
              f"{', '.join(failures)}")
        return 1
    print(f"OK: all {len(themes)} entries verified")
    return 0


if __name__ == "__main__":
    sys.exit(main())
