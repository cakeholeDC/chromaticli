import registry from '../../themes.json';
import { SiteFooter, SiteHeader } from './SiteChrome.jsx';

const categories = [
  ['core', 'Core'],
  ['light', 'Light'],
  ['dark', 'Dark'],
  ['defaults', 'Defaults'],
];

const hueOrder = ['red', 'orange', 'yellow', 'green', 'blue', 'indigo', 'violet', 'light', 'dark'];

function hueIndex(id) {
  const hue = id.replace(/^(light|dark)-/, '');
  return hueOrder.indexOf(hue);
}

export default function Gallery() {
  return (
    <div className="page gallery-page">
      <SiteHeader currentPage="themes" />
      <main className="gallery-main">
        <h1>Full spectrum</h1>
        <p className="gallery-intro">{Object.keys(registry.themes).length} built-in themes; light and dark variants.</p>
        {categories.map(([category, label]) => {
          const ids = Object.keys(registry.themes)
            .filter((id) => registry.themes[id].category === category)
            .sort((a, b) => hueIndex(a) - hueIndex(b));
          if (!ids.length) return null;
          return (
            <section className="gallery-section" aria-labelledby={category} key={category}>
              <h2 id={category}>{label}</h2>
              <div className="gallery-grid">
                {ids.map((id) => (
                  <figure className="gallery-card" key={id}>
                    <img src={`/gallery/themes/${id}.svg`} alt={`Preview of ${id} terminal theme`} loading="lazy" width="280" height="170" />
                    <figcaption><code>{id}</code></figcaption>
                  </figure>
                ))}
              </div>
            </section>
          );
        })}
        {Object.keys(registry.pairs || {}).length > 0 && (
          <p className="gallery-pairs">Auto light/dark pairs: {Object.keys(registry.pairs).map((id, index) => <span key={id}>{index > 0 ? ', ' : ''}<code>{id}</code></span>)}. Set one with <code>chromaticli set --pair &lt;id&gt;</code>.</p>
        )}
      </main>
      <SiteFooter />
    </div>
  );
}
