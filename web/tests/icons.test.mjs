import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import { inflateSync } from 'node:zlib';

const root = new URL('../', import.meta.url);
const publicDir = join(root.pathname, 'public');
const readPublic = (path) => readFileSync(join(publicDir, path));

function pngSize(path) {
  const data = readPublic(path);
  assert.equal(data.toString('hex', 0, 8), '89504e470d0a1a0a');
  return [data.readUInt32BE(16), data.readUInt32BE(20)];
}

function pngIsFullyOpaque(path) {
  const data = readPublic(path);
  const width = data.readUInt32BE(16);
  const height = data.readUInt32BE(20);
  assert.equal(data[25], 6, `${path} must use RGBA pixels`);
  const compressed = [];
  for (let offset = 8; offset < data.length;) {
    const length = data.readUInt32BE(offset);
    const type = data.toString('ascii', offset + 4, offset + 8);
    if (type === 'IDAT') compressed.push(data.subarray(offset + 8, offset + 8 + length));
    offset += length + 12;
    if (type === 'IEND') break;
  }

  const raw = inflateSync(Buffer.concat(compressed));
  const stride = width * 4;
  let prior = Buffer.alloc(stride);
  let cursor = 0;
  for (let y = 0; y < height; y += 1) {
    const filter = raw[cursor++];
    const row = Buffer.from(raw.subarray(cursor, cursor + stride));
    cursor += stride;
    for (let i = 0; i < stride; i += 1) {
      const left = i >= 4 ? row[i - 4] : 0;
      const up = prior[i];
      const upLeft = i >= 4 ? prior[i - 4] : 0;
      let predictor = 0;
      if (filter === 1) predictor = left;
      else if (filter === 2) predictor = up;
      else if (filter === 3) predictor = Math.floor((left + up) / 2);
      else if (filter === 4) {
        const p = left + up - upLeft;
        const pa = Math.abs(p - left);
        const pb = Math.abs(p - up);
        const pc = Math.abs(p - upLeft);
        predictor = pa <= pb && pa <= pc ? left : pb <= pc ? up : upLeft;
      } else assert.equal(filter, 0, `${path} uses an unsupported PNG filter`);
      row[i] = (row[i] + predictor) & 0xff;
    }
    for (let i = 3; i < stride; i += 4) assert.equal(row[i], 255, `${path} contains transparent pixels`);
    prior = row;
  }
  return true;
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

test('Apple touch icon fills its square canvas for the iOS mask', () => {
  const source = readPublic('apple-touch-icon.svg').toString('utf8');
  assert.match(source, /<rect x="0" y="0" width="64" height="64" fill="#1a1a2e"\/>/);
  assert.match(source, /<rect x="0" y="0" width="64" height="23" fill="#2a2a3e"\/>/);
  assert.match(source, /<rect x="0" y="23" width="64" height="41" fill="url\(#rainbow\)" opacity="\.58"\/>/);
  assert.doesNotMatch(source, /rx=/);
  assert.equal(pngIsFullyOpaque('apple-touch-icon.png'), true);
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
