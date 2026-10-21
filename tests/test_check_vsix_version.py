#!/usr/bin/env python3
"""Unit and repository-fixture tests for the VSIX version gate."""

import importlib.util
from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parent.parent
CHECKER = ROOT / "scripts/check-vsix-version.py"
SPEC = importlib.util.spec_from_file_location("check_vsix_version", CHECKER)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class VersionTests(unittest.TestCase):
    def test_semver_precedence(self):
        key = MODULE.version_key
        self.assertLess(key("0.0.1-rc.2"), key("0.0.1-rc.10"))
        self.assertLess(key("0.0.1-rc.10"), key("0.0.1"))
        self.assertLess(key("0.0.1"), key("0.1.0"))
        self.assertEqual(key("0.0.1+build.2"), key("0.0.1"))
        with self.assertRaises(ValueError):
            key("0.0.1-rc.01")

    def test_manifest_version_alone_is_not_a_source_change(self):
        old = {"name": "chromaticli-themes", "version": "0.0.1"}
        new = {**old, "version": "0.0.2"}
        self.assertFalse(MODULE.packaged_source_changed({MODULE.MANIFEST}, old, new))
        self.assertTrue(MODULE.packaged_source_changed({"vscode-extension/themes/blue.json"}, old, new))
        self.assertTrue(MODULE.packaged_source_changed({MODULE.MANIFEST}, old, {**new, "displayName": "New"}))


class ChangeGateTests(unittest.TestCase):
    default = object()
    old = {"name": "chromaticli-themes", "version": "0.0.1"}
    old_vsix = "vscode-extension/chromaticli-themes-0.0.1.vsix"
    new_vsix = "vscode-extension/chromaticli-themes-0.0.2.vsix"
    source = "vscode-extension/themes/blue.json"

    def validate(self, old=default, new=None, changed=None, tracked=None, exists=True):
        MODULE.validate(
            self.old if old is self.default else old,
            self.old if new is None else new,
            set() if changed is None else changed,
            [self.old_vsix] if tracked is None else tracked,
            exists,
        )

    def test_first_bundle_and_unchanged_bundle(self):
        self.validate(old=None, changed={MODULE.MANIFEST, self.old_vsix})
        self.validate()

    def test_changed_source_requires_higher_version(self):
        with self.assertRaisesRegex(ValueError, "increase version"):
            self.validate(changed={self.source})

    def test_changed_source_requires_new_vsix_and_removes_old(self):
        new = {**self.old, "version": "0.0.2"}
        with self.assertRaisesRegex(ValueError, "expected one tracked VSIX"):
            self.validate(new=new, changed={self.source, self.new_vsix},
                          tracked=[self.old_vsix, self.new_vsix])
        with self.assertRaisesRegex(ValueError, "add .*vsix"):
            self.validate(new=new, changed={self.source}, tracked=[self.new_vsix])
        self.validate(new=new, changed={self.source, self.new_vsix}, tracked=[self.new_vsix])

    def test_version_only_or_vsix_only_change_fails(self):
        new = {**self.old, "version": "0.0.2"}
        with self.assertRaisesRegex(ValueError, "without packaged source changes"):
            self.validate(new=new, changed={MODULE.MANIFEST, self.new_vsix},
                          tracked=[self.new_vsix])
        with self.assertRaisesRegex(ValueError, "VSIX changed without"):
            self.validate(changed={self.old_vsix})


if __name__ == "__main__":
    unittest.main()
