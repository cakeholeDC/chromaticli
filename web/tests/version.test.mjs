import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { readVersion } from '../build-version.js';

test('build version requires valid metadata and an exactly matching optional release tag', () => {
  const directory = mkdtempSync(join(tmpdir(), 'chromaticli-version-'));
  const manifest = join(directory, 'manifest.json');
  try {
    assert.throws(() => readVersion(manifest), { code: 'ENOENT' });
    for (const invalid of ['{', 'null', '{}', '{".":12}', '{".":""}', '{".":"01.2.3"}', '{".":"1.2"}', '{".":"1.2.3-beta"}', '{".":"1.2.3+build"}', '{".":"1.2.3\\n"}']) {
      writeFileSync(manifest, invalid);
      assert.throws(() => readVersion(manifest));
    }
    for (const version of ['0.0.0', '0.1.0', '12.34.56']) {
      writeFileSync(manifest, JSON.stringify({ '.': version, privateMetadata: 'never exposed' }));
      assert.equal(readVersion(manifest), version);
      assert.equal(readVersion(manifest, `v${version}`), version);
      for (const tag of ['', version, `refs/tags/v${version}`, 'v99.99.99']) {
        assert.throws(() => readVersion(manifest, tag), /Release tag must match/);
      }
    }
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});
