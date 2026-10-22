const projectNames = ['project_1', 'project_2'];

export function createDemoFrame() {
  return { cycle: 0, step: 0, characters: 0, phase: 'typing', cwd: null, assigned: [null, null], themeId: null, history: [] };
}

export function demoCommands(cycle, themeIds) {
  const cycleCount = Math.ceil(themeIds.length / 2);
  const firstIndex = (cycle % cycleCount) * 2;
  const secondTheme = themeIds[firstIndex + 1];
  return [
    'cd project_1', `chromaticli set ${themeIds[firstIndex]}`,
    'cd ..', 'cd project_2', ...(secondTheme ? [`chromaticli set ${secondTheme}`] : []),
    'cd ..', 'cd project_1', 'cd ../project_2', 'cd ../project_1',
    'cd ..', 'cd project_2', 'cd ..', 'clear',
  ];
}

export function currentDemoCommand(frame, themeIds) {
  return demoCommands(frame.cycle, themeIds)[frame.step];
}

export function demoPrompt(cwd) {
  return cwd ? `~/${projectNames[cwd - 1]} $` : '~ $';
}

export function nextDemoFrame(frame, themeIds) {
  const command = currentDemoCommand(frame, themeIds);
  if (frame.phase === 'pause') return { ...frame, step: frame.step + 1, characters: 0, phase: 'typing' };
  if (frame.characters < command.length) return { ...frame, characters: frame.characters + 1 };
  if (command === 'clear') return { ...frame, cycle: frame.cycle + 1, step: 0, characters: 0, phase: 'typing', history: [] };

  const history = [...frame.history, `${demoPrompt(frame.cwd)} ${command}`];
  let { cwd, themeId } = frame;
  const assigned = [...frame.assigned];
  if (command.startsWith('cd ')) {
    const target = command.startsWith('cd ../') ? command.slice(6) : command.slice(3);
    cwd = command === 'cd ..' ? null : projectNames.indexOf(target) + 1;
    themeId = cwd ? assigned[cwd - 1] : null;
  } else if (command.startsWith('chromaticli set ')) {
    themeId = command.slice('chromaticli set '.length);
    assigned[cwd - 1] = themeId;
  }
  return { ...frame, cwd, themeId, assigned, history, phase: 'pause', characters: 0 };
}
