import test from 'node:test';
import assert from 'node:assert/strict';
import { advanceHeroLine, createHeroLine, heroLineDelay } from '../src/hero-typewriter.js';

test('hero alternates pronunciation and app name, with a three-times-longer app-name pause', () => {
  let line = createHeroLine();
  assert.equal(line.text, '');

  while (line.phase === 'typing-pronunciation') line = advanceHeroLine(line);
  assert.equal(line.text, 'Chromatically.');
  assert.equal(line.phase, 'pause-pronunciation');
  const pronunciationPause = heroLineDelay(line);

  line = advanceHeroLine(line);
  while (line.phase === 'deleting-pronunciation') line = advanceHeroLine(line);
  assert.equal(line.phase, 'typing-name');

  while (line.phase === 'typing-name') line = advanceHeroLine(line);
  assert.equal(line.text, 'chromaticli.');
  assert.equal(line.phase, 'pause-name');
  assert.equal(heroLineDelay(line), pronunciationPause * 3);

  line = advanceHeroLine(line);
  while (line.phase === 'deleting-name') line = advanceHeroLine(line);
  assert.deepEqual(line, { text: '', phase: 'typing-pronunciation' });
});
