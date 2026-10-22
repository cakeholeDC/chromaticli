import { useEffect, useRef, useState } from 'react';
import registry from '../../themes.json';
import { createDemoFrame, currentDemoCommand, demoPrompt, nextDemoFrame } from './demo-sequence.js';
import { brandColors, SiteFooter, SiteHeader } from './SiteChrome.jsx';
import { advanceHeroLine, createHeroLine, heroLineDelay } from './hero-typewriter.js';

const repositoryUrl = 'https://github.com/cakeholeDC/chromaticli';
const docsUrl = `${repositoryUrl}#readme`;
const themeIds = Object.keys(registry.themes).sort();
const installCommands = {
  macos: 'brew install cakeholeDC/tap/chromaticli\nchromaticli install',
  linux: `git clone --branch v${__CHROMATICLI_VERSION__} https://github.com/cakeholeDC/chromaticli.git\ncd chromaticli\n./chromaticli install`,
};

export default function App() {
  const [demo, setDemo] = useState(createDemoFrame);
  const [reducedMotion, setReducedMotion] = useState(() => typeof window !== 'undefined' && window.matchMedia('(prefers-reduced-motion: reduce)').matches);
  const [heroLine, setHeroLine] = useState(() => createHeroLine(reducedMotion));
  const [installOs, setInstallOs] = useState('macos');
  const [copyStatus, setCopyStatus] = useState('');
  const copyTimer = useRef(null);
  const command = currentDemoCommand(demo, themeIds);
  const editorCwd = reducedMotion ? 2 : demo.cwd;
  const installCommand = installCommands[installOs];
  const themeId = reducedMotion ? themeIds[1] : demo.themeId;
  const theme = themeId ? registry.themes[themeId] : null;
  const palette = theme?.palette;
  const paletteStyle = palette ? {
    '--theme-background': palette.background,
    '--terminal-text': palette.foreground,
  } : undefined;
  const editorPaletteStyle = palette ? {
    '--editor-background': palette.background,
    '--editor-foreground': palette.foreground,
    '--editor-muted': palette.ansi[8],
    '--editor-keyword': palette.ansi[4],
    '--editor-string': palette.ansi[2],
    '--editor-function': palette.ansi[3],
    '--editor-number': palette.ansi[5],
    '--editor-type': palette.ansi[6],
  } : undefined;

  useEffect(() => {
    const preference = window.matchMedia('(prefers-reduced-motion: reduce)');
    const updatePreference = () => setReducedMotion(preference.matches);
    updatePreference();
    preference.addEventListener('change', updatePreference);
    return () => preference.removeEventListener('change', updatePreference);
  }, []);

  useEffect(() => {
    if (reducedMotion) setHeroLine(createHeroLine(true));
  }, [reducedMotion]);

  useEffect(() => {
    if (reducedMotion || heroLine.phase === 'done') return;
    const timer = window.setTimeout(() => setHeroLine(advanceHeroLine), heroLineDelay(heroLine));
    return () => window.clearTimeout(timer);
  }, [heroLine, reducedMotion]);

  useEffect(() => {
    if (reducedMotion) return;
    const previous = demo.history.at(-1) || '';
    const delay = demo.phase === 'pause' ? (previous.includes('chromaticli set ') ? 2000 : 1100) : demo.characters < command.length ? 65 : 350;
    const timer = window.setTimeout(() => setDemo((frame) => nextDemoFrame(frame, themeIds)), delay);
    return () => window.clearTimeout(timer);
  }, [command, demo, reducedMotion]);

  useEffect(() => () => window.clearTimeout(copyTimer.current), []);

  async function copyInstallCommands() {
    try {
      if (!navigator.clipboard?.writeText) throw new Error('Clipboard unavailable');
      await navigator.clipboard.writeText(installCommand);
      setCopyStatus('success');
      window.clearTimeout(copyTimer.current);
      copyTimer.current = window.setTimeout(() => setCopyStatus(''), 2500);
    } catch {
      window.clearTimeout(copyTimer.current);
      setCopyStatus('Copy failed. Select the commands to copy them.');
    }
  }

  function selectInstallOs(os) {
    setInstallOs(os);
    setCopyStatus('');
    window.clearTimeout(copyTimer.current);
  }

  function renderInstallTabLabel(label) {
    return [...label].map((letter, index) => (
      <span key={index} style={{ '--brand-color': brandColors[index % brandColors.length] }}>{letter}</span>
    ));
  }

  return (
    <div className="page">
      <SiteHeader />

      <main>
        <section className="hero" id="top" aria-labelledby="hero-heading">
          {/* <p className="hero-eyebrow">sync your terminal colors with your editor.</p> */}
          <h1 id="hero-heading">Your terminal.<br />Your editor.<br /><span className="sr-only">chromaticli.</span><span className={'hero-type-line' + (heroLine.phase.startsWith('pause-') ? ' waiting' : '')} aria-hidden="true">{heroLine.text.split('').map((letter, index) => (
              <span key={index} style={{ color: brandColors[index % brandColors.length] }}>{letter}</span>
            ))}<span className="hero-type-cursor" /></span></h1>
            {/* <span className="pronunciation">pronounced <em>chromatically</em> (/kroʊˈmæ.tɪ.kli/).</span> */}
          <div className="hero-actions">
            <a className="primary-link" href="#install"><span>Install chromaticli</span></a>
            <p className="compatibility-note">macOS · Linux &nbsp;//&nbsp; zsh · bash · fish</p>
          </div>
        </section>

        <section className="landing-section about-section" id="about" aria-labelledby="about-heading">
          <div className="about-copy">
            <p className="section-kicker">How it works</p>
            <h2 id="about-heading">Sync themes with your editor</h2>
            <p><em><strong>chromaticli</strong></em> applies matching themes to your editor and your terminal.</p>
            <p>Change directories and your terminal follows automatically.</p>
            <pre className="code-block" tabIndex="0" aria-label="Local project example"><code>{'cd ~/my-project\nchromaticli set blue'}</code></pre>
          </div>
          <section className="demo-preview" aria-labelledby="demo-heading">
            <p className="section-kicker">See it in action</p>
            <div className="demo-stage">
              <div className="terminal">
                <header className="title-bar">
                  <span className="traffic-lights" aria-hidden="true"><i /><i /><i /></span>
                  <span className="terminal-title">
                    <span className="sr-only">Terminal</span>
                    <span aria-hidden="true">{'terminal'.split('').map((letter, index) => (
                      <span key={index} style={{ color: brandColors[index % brandColors.length] }}>{letter}</span>
                    ))}</span>
                  </span>
                  <span aria-hidden="true" />
                </header>

                <div className={'terminal-body' + (theme ? ' themed' : '')} style={paletteStyle} aria-hidden="true">
                  <div className="terminal-output">
                    {reducedMotion ? (
                      <><p className="terminal-command">~ $ cd project_1</p><p className="terminal-command">~/project_1 $ chromaticli set {themeIds[0]}</p><p className="terminal-command">~/project_1 $ cd ..</p><p className="terminal-command">~ $ cd project_2</p><p className="terminal-command">~/project_2 $ chromaticli set {themeIds[1]}</p><p className="terminal-command">~/project_2 $ cd ../project_1</p><p className="terminal-command">~/project_1 $ cd ../project_2</p><p className="terminal-command">~/project_2 $ <span className="terminal-cursor">▌</span></p></>
                    ) : (
                      <>
                        {demo.history.slice(-3).map((line, index) => <p className="terminal-command" key={demo.cycle + ':' + demo.step + ':' + index}>{line}</p>)}
                        <p className="terminal-command">{demoPrompt(demo.cwd)} {demo.phase === 'typing' && command.slice(0, demo.characters)}<span className="terminal-cursor">▌</span></p>
                      </>
                    )}
                  </div>
                </div>
              </div>
              <div className={'editor-window' + (theme ? ' themed' : '')} style={editorPaletteStyle} aria-hidden="true">
                <header className="title-bar">
                  <span className="traffic-lights" aria-hidden="true"><i /><i /><i /></span>
                  <span className="terminal-title" aria-hidden="true">{'editor'.split('').map((letter, index) => (
                    <span key={index} style={{ color: brandColors[index % brandColors.length] }}>{letter}</span>
                  ))}</span>
                  <span aria-hidden="true" />
                </header>
                <div className="editor-content">
                  <div className="editor-activity" aria-hidden="true"><i /><i /><i /><i /><i /></div>
                  <aside className="editor-sidebar">
                    <span className="editor-sidebar-heading">EXPLORER</span>
                    <span className={'editor-project' + (editorCwd === null ? ' active' : '')}><i />~</span>
                    <span className={'editor-project child' + (editorCwd === 1 ? ' active' : '')}><b aria-hidden="true">└</b><i />project_1</span>
                    <span className={'editor-project child' + (editorCwd === 2 ? ' active' : '')}><b aria-hidden="true">└</b><i />project_2</span>
                  </aside>
                  <div className="editor-workspace">
                    <div className="editor-tab"><i />Theme preview</div>
                    <div className="editor-code">
                      <div><span>1</span><code><b>const</b> project = {'{'}</code></div>
                      <div><span>2</span><code>  theme: <em>'{themeId || 'chromaticli'}'</em>,</code></div>
                      <div><span>3</span><code>  terminal: <em>'in sync'</em>,</code></div>
                      <div><span>4</span><code>  colors: <strong>[</strong></code></div>
                      <div><span>5</span><code>    <i style={{ color: palette?.ansi[1] || '#ff8a8a' }}>{palette?.ansi[1] || '#ff8a8a'}</i>, <i style={{ color: palette?.ansi[6] || '#66d4ff' }}>{palette?.ansi[6] || '#66d4ff'}</i>, <i style={{ color: palette?.ansi[5] || '#b08aff' }}>{palette?.ansi[5] || '#b08aff'}</i></code></div>
                      <div><span>6</span><code>  <strong>]</strong></code></div>
                      <div><span>7</span><code>{'}'}</code></div>
                      <div className="editor-caret-line"><span>8</span><code><i className="editor-caret" /></code></div>
                    </div>
                    <div className="editor-panel"><i /><i /><i /></div>
                  </div>
                </div>
              </div>
            </div>
            <p className="sr-only">Animated example: the home directory contains project_1 and project_2. Each project has its own editor and terminal theme; cd .. returns to home. The animation eventually shows every available theme.</p>
          </section>
        </section>

        <section className="landing-section install-section" id="install" aria-labelledby="install-heading">
          <p className="section-kicker">Get started</p>
          <h2 id="install-heading">Install chromaticli</h2>
          {/* <p>Run these commands in your own terminal. Start a new shell session afterward to activate automatic theme syncing.</p> */}
          <div className="install-tabs" role="group" aria-label="Choose your operating system">
            <button className="install-tab" type="button" aria-pressed={installOs === 'macos'} onClick={() => selectInstallOs('macos')}>{renderInstallTabLabel('MACOS')}</button>
            <button className="install-tab" type="button" aria-pressed={installOs === 'linux'} onClick={() => selectInstallOs('linux')}>{renderInstallTabLabel('LINUX')}</button>
          </div>
          <div className="install-code">
            <pre className="code-block" tabIndex="0" aria-label={installOs === 'macos' ? 'Homebrew installation commands' : 'Linux source installation commands'}><code>{installCommand}</code></pre>
            <button className="copy-button" type="button" onClick={copyInstallCommands} aria-label={copyStatus === 'success' ? 'Installation commands copied' : `Copy ${installOs === 'macos' ? 'macOS' : 'Linux'} installation commands`} title={copyStatus === 'success' ? 'Copied' : `Copy ${installOs === 'macos' ? 'macOS' : 'Linux'} installation commands`}>
              {copyStatus === 'success' ? <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" focusable="false"><path d="m4 12 5 5L20 6" /></svg> : <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" focusable="false"><rect x="8" y="8" width="12" height="12" rx="2" /><path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2" /></svg>}
            </button>
            <p className="copy-status" role="status">{copyStatus === 'success' ? <span className="sr-only">Installation commands copied.</span> : copyStatus}</p>
          </div>
          <h3>Before you start</h3>
          <ul className="requirements">
            {installOs === 'macos'
              ? <li><a href="https://brew.sh/" target="_blank" rel="noopener noreferrer">Homebrew</a> already installed. The tap installs <code>jq</code>, the CLI’s required dependency.</li>
              : <li><a href="https://git-scm.com/install/linux.html" target="_blank" rel="noopener noreferrer">git</a> and <a href="https://jqlang.org/download/" target="_blank" rel="noopener noreferrer">jq</a> installed. <code>jq</code> is the CLI’s only required dependency; get both from your distribution’s package manager.</li>}
            <li>
              A terminal with OSC color support, such as macOS <a href="https://support.apple.com/guide/terminal/welcome/mac" target="_blank" rel="noopener noreferrer">Terminal</a>, Debian’s <a href="https://apps.gnome.org/en-GB/Console/" target="_blank" rel="noopener noreferrer">GNOME Console</a>, <a href="https://iterm2.com/" target="_blank" rel="noopener noreferrer">iTerm2</a>, <a href="https://sw.kovidgoyal.net/kitty/" target="_blank" rel="noopener noreferrer">Kitty</a>, or <a href="https://alacritty.org/" target="_blank" rel="noopener noreferrer">Alacritty</a>
              <span className="requirement-note"> (Read more about <a href={docsUrl} target="_blank" rel="noopener noreferrer">terminal compatibility</a> and <a href={`${repositoryUrl}#troubleshooting`} target="_blank" rel="noopener noreferrer">troubleshooting</a>)</span>
            </li>
            <li>zsh, bash, or fish.</li>
            <li>Supports <a href="https://code.visualstudio.com/" target="_blank" rel="noopener noreferrer">VS Code</a>.</li>
          </ul>
        </section>
      </main>

      <SiteFooter />
    </div>
  );
}
