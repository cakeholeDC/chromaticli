import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { createDemoFrame, currentDemoCommand, demoCommands, demoPrompt, nextDemoFrame } from '../src/demo-sequence.js';

const registry = JSON.parse(readFileSync(new URL('../../themes.json', import.meta.url), 'utf8'));
const themeIds = Object.keys(registry.themes).sort();

function enter(frame) {
  const command = currentDemoCommand(frame, themeIds);
  assert.equal(frame.phase, 'typing');
  for (let index = 0; index < command.length; index++) frame = nextDemoFrame(frame, themeIds);
  assert.equal(frame.characters, command.length);
  return nextDemoFrame(frame, themeIds);
}

function nextCommand(frame) {
  assert.equal(frame.phase, 'pause');
  return nextDemoFrame(frame, themeIds);
}

test('sibling project changes reset to home and restore each project theme', () => {
  let frame = createDemoFrame();
  assert.equal(demoPrompt(frame.cwd), '~ $');
  assert.equal(currentDemoCommand(frame, themeIds), 'cd project_1');
  frame = nextCommand(enter(frame)); // enter project_1
  assert.equal(frame.cwd, 1);
  assert.equal(frame.themeId, null);
  assert.equal(demoPrompt(frame.cwd), '~/project_1 $');
  frame = nextCommand(enter(frame)); // set project_1 theme
  assert.equal(frame.themeId, themeIds[0]);
  frame = nextCommand(enter(frame)); // cd .. returns home
  assert.equal(frame.cwd, null);
  assert.equal(frame.themeId, null);
  frame = nextCommand(enter(frame)); // enter project_2
  assert.equal(frame.cwd, 2);
  assert.equal(frame.themeId, null);
  assert.equal(demoPrompt(frame.cwd), '~/project_2 $');
  frame = nextCommand(enter(frame)); // set project_2 theme
  assert.equal(frame.themeId, themeIds[1]);
  frame = nextCommand(enter(frame)); // cd .. returns home
  assert.equal(frame.cwd, null);
  assert.equal(frame.themeId, null);
  frame = nextCommand(enter(frame)); // re-enter project_1
  assert.equal(frame.cwd, 1);
  assert.equal(frame.themeId, themeIds[0]);
  assert.equal(currentDemoCommand(frame, themeIds), 'cd ../project_2');
  frame = nextCommand(enter(frame)); // move directly to project_2
  assert.equal(frame.cwd, 2);
  assert.equal(frame.themeId, themeIds[1]);
  assert.equal(demoPrompt(frame.cwd), '~/project_2 $');
  assert.equal(currentDemoCommand(frame, themeIds), 'cd ../project_1');
  frame = nextCommand(enter(frame)); // move directly back to project_1
  assert.equal(frame.cwd, 1);
  assert.equal(frame.themeId, themeIds[0]);
  frame = nextCommand(enter(frame)); // cd .. returns home
  assert.equal(frame.cwd, null);
  assert.equal(frame.themeId, null);
  frame = nextCommand(enter(frame)); // re-enter project_2
  assert.equal(frame.cwd, 2);
  assert.equal(frame.themeId, themeIds[1]);
  frame = nextCommand(enter(frame)); // cd .. returns home
  assert.equal(frame.cwd, null);
  assert.equal(frame.themeId, null);
  frame = enter(frame); // clear
  assert.deepEqual(frame.history, []);
  assert.equal(frame.cycle, 1);
  assert.equal(currentDemoCommand(frame, themeIds), 'cd project_1');
});

test('all themes appear before the demo repeats, including an odd final theme', () => {
  let frame = createDemoFrame();
  const applied = [];
  for (let cycle = 0; cycle < Math.ceil(themeIds.length / 2); cycle++) {
    assert.equal(demoCommands(cycle, themeIds).some((command) => command.startsWith('mkdir ')), false);
    while (frame.cycle === cycle) {
      const command = currentDemoCommand(frame, themeIds);
      frame = enter(frame);
      if (command.startsWith('chromaticli set ')) applied.push(frame.themeId);
      if (frame.phase === 'pause') frame = nextCommand(frame);
    }
  }
  assert.deepEqual(applied, themeIds);
  assert.equal(frame.cycle, Math.ceil(themeIds.length / 2));
  assert.equal(currentDemoCommand(frame, themeIds), 'cd project_1');
  assert.deepEqual(frame.assigned, themeIds.length % 2
    ? [themeIds.at(-1), themeIds.at(-2)]
    : [themeIds.at(-2), themeIds.at(-1)]);
});
