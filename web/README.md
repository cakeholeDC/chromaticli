# chromaticli website

The website is a separate Vite and React app. Its build tools do not affect CLI installation or use.

## Local development

Use Node.js 22.13 or newer in the 22.x LTS line and pnpm 12.10.0, pinned by `packageManager` in `package.json`. With [nvm](https://github.com/nvm-sh/nvm), from the repository root:

```sh
cd web
nvm install
nvm use
npm install --global pnpm@12.10.0
pnpm --version
```

`pnpm --version` should print `12.10.0`. For subsequent visits, `cd web && nvm use` selects the version recorded in `.nvmrc`. Then install dependencies and start the dev server:

```sh
pnpm install --frozen-lockfile
pnpm dev
```

Vite serves on localhost by default. For access over a LAN or VPN, start it
with `pnpm dev --host 0.0.0.0` and open `http://<host-ip>:5173/` from the other
device (subject to VPN routing and the host firewall). To stop the server from
another terminal, run `bash stop-dev.sh` in `web/` (or pass its displayed port).
The script stops only a Node listener running from this checkout. It tries INT,
then TERM; if the listener remains, it reports the PID for manual inspection
instead of forcing a kill.

Use `pnpm build` to create the static site in `dist/`, or `pnpm preview` to serve that build locally.

Run `pnpm test` for the small Node theme-loop and metadata checks. No test framework is required.

## Shared inputs

Build from a full repository checkout. Vite imports the root `themes.json` and unchanged `logo/chromaticli.svg`; the production output bundles both locally without runtime GitHub requests. The development server allows `web/` and only those two shared files outside it.

The homepage and `/themes/` page share the same React header and footer. The themes page reads `themes.json` directly, while `python3 scripts/generate-preview.py` writes each theme SVG once under `web/public/gallery/themes/`; the docs galleries reference those same assets. Run the generator after a theme change and include the docs and website artifacts in the change. Vite builds both pages and copies the theme SVGs into `dist/gallery/`.

The build reads `.release-please-manifest.json` at the repository root and exposes only its `.` version string to the browser. Versions must be canonical stable `X.Y.Z` values (no prefix, leading zeroes, prerelease, or build suffix). Missing or invalid metadata fails configuration loading, including builds. The website package version is unrelated to the CLI release version.

For release builds, supply the selected release tag explicitly:

<!-- x-release-please-start-version -->
```sh
CHROMATICLI_RELEASE_TAG=v0.1.0 pnpm build
```
<!-- x-release-please-end -->

Release Please updates the example tag with each release. When supplied, `CHROMATICLI_RELEASE_TAG` must equal `v` followed by the manifest version exactly; empty, malformed, or mismatched tags fail the build. Ordinary local builds may omit it. This variable is a build validation input and is not exposed to the browser. Deployment eligibility checks and workflows are handled in later tasks.

