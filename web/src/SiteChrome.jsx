export const brandColors = ['#ff8a8a', '#ffb066', '#ffe066', '#a3ff8a', '#8affd0', '#66d4ff', '#8aa3ff', '#b08aff', '#e08aff', '#ff8ad0', '#ff8a9b'];

const repositoryUrl = 'https://github.com/cakeholeDC/chromaticli';
const docsUrl = `${repositoryUrl}#readme`;

export function SiteHeader({ currentPage = 'home' }) {
  const sectionLink = (section) => currentPage === 'home' ? `#${section}` : `/#${section}`;

  return (
    <header className="site-header">
      <div className="brand-block">
        <a className="site-brand" href="/" aria-label="chromaticli home">
          <span aria-hidden="true">{'chromaticli'.split('').map((letter, index) => (
            <span key={index} style={{ color: brandColors[index % brandColors.length] }}>{letter}</span>
          ))}</span>
        </a>
        <span className="pronunciation">pronounced <em>chromatically</em> <span className="pronunciation-phonetics">(/kroʊˈmæ.tɪ.kli/)</span></span>
      </div>
      <nav className="site-nav" aria-label="Site navigation">
        <a href={sectionLink('about')}>About</a>
        <a href={sectionLink('install')}>Install</a>
        <a href="/themes/" aria-current={currentPage === 'themes' ? 'page' : undefined}>Themes</a>
        <a href={repositoryUrl} target="_blank" rel="noopener noreferrer">GitHub</a>
      </nav>
    </header>
  );
}

export function SiteFooter() {
  return (
    <footer className="site-footer">
      <nav aria-label="Project links">
        <a href={repositoryUrl} target="_blank" rel="noopener noreferrer">GitHub repository</a>
        <a href={docsUrl} target="_blank" rel="noopener noreferrer">Documentation</a>
        <a href={`${repositoryUrl}/blob/main/LICENSE`} target="_blank" rel="noopener noreferrer">MIT license</a>
      </nav>
      <a href={`${repositoryUrl}/releases/tag/v${__CHROMATICLI_VERSION__}`} target="_blank" rel="noopener noreferrer">chromaticli v{__CHROMATICLI_VERSION__}</a>
    </footer>
  );
}
