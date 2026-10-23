import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';

const root = new URL('../', import.meta.url);
const publicDir = join(root.pathname, 'public');
const readPublic = (path) => readFileSync(join(publicDir, path));

function pngSize(path) {
  const data = readPublic(path);
  assert.equal(data.toString('hex', 0, 8), '89504e470d0a1a0a');
  return [data.readUInt32BE(16), data.readUInt32BE(20)];
}

test('web app icon files have the declared PNG dimensions', () => {
  for (const [path, size] of [
    ['apple-touch-icon.png', 180],
    ['favicon-16x16.png', 16],
    ['favicon-32x32.png', 32],
    ['android-chrome-192x192.png', 192],
    ['android-chrome-512x512.png', 512],
  ]) {
    assert.deepEqual(pngSize(path), [size, size], path);
  }
});

test('ICO includes 16px and 32px PNG entries', () => {
  const ico = readPublic('favicon.ico');
  assert.deepEqual([...ico.subarray(0, 6)], [0, 0, 1, 0, 2, 0]);
  assert.deepEqual([...ico.subarray(6, 10)], [16, 16, 0, 0]);
  assert.deepEqual([...ico.subarray(22, 26)], [32, 32, 0, 0]);
});

test('both site entry points link the Apple touch icon and web app manifest', () => {
  for (const path of ['../index.html', '../themes/index.html']) {
    const html = readFileSync(new URL(path, import.meta.url), 'utf8');
    assert.match(html, /rel="apple-touch-icon"[^>]+href="\/apple-touch-icon\.png"/);
    assert.match(html, /rel="manifest"[^>]+href="\/site\.webmanifest"/);
  }
});

test('web app manifest icons exist and match their declared sizes', () => {
  const manifest = JSON.parse(readPublic('site.webmanifest').toString('utf8'));
  assert.equal(manifest.name, 'chromaticli');
  for (const icon of manifest.icons) {
    const size = Number(icon.sizes.split('x')[0]);
    assert.deepEqual(pngSize(icon.src.slice(1)), [size, size]);
  }
});
