# Kelpie — Website

The website is the static `site/` folder. There is no build step: the files in
the repository are the files that get served.

It is published in two places from the same folder:

| Address | Host | How it is published |
| --- | --- | --- |
| <https://kelpie.rocks> | nginx container on the UnlikeOtherAI web host | `scripts/deploy-website.sh`, run by hand |
| <https://unlikeotherai.github.io/kelpie> | GitHub Pages | `.github/workflows/pages.yml`, on every push to `main` that touches `site/` |

The GitHub Pages copy is the apps' default home page and help link, and it also
carries the Linux `apt` and `dnf` repositories that CI builds into
`site/packages`. `kelpie.rocks` is the address to share; every page names it as
its canonical URL.

Because the Pages copy lives under `/kelpie/`, every link between site files is
relative. Do not start a path with `/`.

## Layout

```text
site/index.html          Landing page
site/privacy/index.html  Privacy policy, linked from the store listings
site/llms.txt            Short description and links for language models
site/css/                One stylesheet per part of the page
site/js/links.js         App Store and Google Play listing URLs
site/js/site.js          Navigation, copy buttons, store and download links
site/js/wall.js          The hero's animated device wall
site/assets/             Fonts, brand marks, icons and screenshots
```

The design follows the Nessie site: navy bars with a water edge, white
sections, Geist headings and pill buttons. Kelpie's accent is the pink of the K
in the Orbit icon. Colours are defined once, at the top of `site/css/base.css`.

## Store links

`site/js/links.js` holds the App Store and Google Play listing URLs. While a
value is empty, every store button on the site reads "Coming soon" and is not a
link. Paste the listing URL there when a listing goes live; nothing else needs
to change.

## Download links

Download buttons link to the GitHub releases page. Each one names the file it
wants in a `data-asset` pattern, and `site/js/site.js` points it at the newest
published release asset that matches. A new release needs no website change.

## Screenshots

`site/assets/screens/` holds captures of the real apps, resized to WebP. The
phone and tablet captures come from the store listing set (iPhone 16 Pro Max
and iPad Air simulators, Pixel 8 emulator). The device-wall photograph was
generated for the store banner and recoloured to the site's pink. When the apps
change, replace the captures with new ones of the same pixel size, check that
they show no private browsing data, and keep the `alt` text accurate.

The phones in the hero and the small demos in the "for agents" cards are drawn
in HTML and CSS. The tool names and arguments they show are real; keep them in
step with `packages/shared/src/extension-tools.ts`.

## Preview

```sh
python -m http.server 8765 --directory site
```

Open <http://127.0.0.1:8765>. Use a server rather than opening the file: the
icons are loaded from `assets/icons.svg`, which browsers refuse to read from
`file://`.

## Publish to kelpie.rocks

```sh
scripts/deploy-website.sh <ssh-target>
```

`<ssh-target>` is the SSH host or alias of the machine that serves
`kelpie.rocks`. The script uploads `site/` without `packages/`, copies the
version it replaces to `/srv/kelpie-web/previous`, and syncs the upload into
`/srv/kelpie-web/dist`. To undo the last publish:

```sh
scripts/deploy-website.sh <ssh-target> --rollback
```

After publishing, load <https://kelpie.rocks> and <https://kelpie.rocks/privacy/>
and check both.
