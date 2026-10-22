export function createHeroLine(reducedMotion = false) {
  return reducedMotion
    ? { text: 'chromaticli.', phase: 'done' }
    : { text: '', phase: 'typing-pronunciation' };
}

export function advanceHeroLine(line) {
  if (line.phase === 'pause-pronunciation') return { ...line, phase: 'deleting-pronunciation' };
  if (line.phase === 'pause-name') return { ...line, phase: 'deleting-name' };
  if (line.phase === 'deleting-pronunciation' || line.phase === 'deleting-name') {
    return line.text
      ? { ...line, text: line.text.slice(0, -1) }
      : { ...line, phase: line.phase === 'deleting-pronunciation' ? 'typing-name' : 'typing-pronunciation' };
  }

  const target = line.phase === 'typing-pronunciation' ? 'Chromatically.' : 'chromaticli.';
  if (line.text.length < target.length) return { ...line, text: target.slice(0, line.text.length + 1) };
  return { ...line, phase: line.phase === 'typing-pronunciation' ? 'pause-pronunciation' : 'pause-name' };
}

export function heroLineDelay(line) {
  if (line.phase === 'pause-pronunciation') return 2000;
  if (line.phase === 'pause-name') return 16000;
  if (line.phase.startsWith('deleting-')) return 65;
  return 115;
}
