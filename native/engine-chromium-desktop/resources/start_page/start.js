/*
 * Kelpie start page behaviour.
 *
 * Reads `data.json` from this page's own origin — the `kelpie://start` scheme is
 * registered as standard, secure, CORS- and fetch-enabled, so this is an
 * ordinary same-origin fetch rather than a native bridge.
 *
 * The DOM is built with `textContent` and `setAttribute` only. Bookmark and
 * history titles are attacker-influenced strings, so nothing here ever goes
 * through `innerHTML`.
 */
(function () {
  "use strict";

  /*
   * Tile and row colours mirror `BookmarkTileView.tileColor` and
   * `HistoryRowView.letterColor` in `apps/macos/Kelpie/Views/StartPageView.swift`:
   * a six-entry RGB palette indexed by the sum of the host's Unicode scalars.
   *
   * This is deliberately the macOS start page's palette and hash, which differ
   * from the tab strip's `LetterAvatarView` (an HSB palette indexed by a
   * multiply-by-31 hash). Both are mirrored exactly as macOS has them.
   */
  var PALETTE = [
    "rgb(102, 143, 217)", // 0.40, 0.56, 0.85
    "rgb(140, 191, 140)", // 0.55, 0.75, 0.55
    "rgb(217, 140, 102)", // 0.85, 0.55, 0.40
    "rgb(179, 128, 217)", // 0.70, 0.50, 0.85
    "rgb(217, 191, 89)", //  0.85, 0.75, 0.35
    "rgb(128, 191, 204)" //  0.50, 0.75, 0.80
  ];

  function hostOf(url) {
    try {
      var host = new URL(url).host;
      return host || url;
    } catch (error) {
      return url;
    }
  }

  function paletteColor(host) {
    // Swift folds over `unicodeScalars`, so iterate code points rather than
    // UTF-16 units to keep non-ASCII hosts on the same colour as macOS.
    var sum = 0;
    Array.from(host).forEach(function (character) {
      sum += character.codePointAt(0);
    });
    return PALETTE[Math.abs(sum) % PALETTE.length];
  }

  function domainLetter(host) {
    var characters = Array.from(host);
    return characters.length > 0 ? characters[0].toUpperCase() : "?";
  }

  function makeBadge(className, host, faviconDataUri) {
    var badge = document.createElement("div");
    badge.className = className;
    badge.style.backgroundColor = paletteColor(host);
    if (faviconDataUri) {
      var image = document.createElement("img");
      image.setAttribute("src", faviconDataUri);
      image.setAttribute("alt", "");
      badge.appendChild(image);
    } else {
      badge.textContent = domainLetter(host);
    }
    return badge;
  }

  function makeTile(bookmark) {
    var host = hostOf(bookmark.url);
    var tile = document.createElement("a");
    tile.className = "tile";
    tile.setAttribute("href", bookmark.url);
    tile.appendChild(makeBadge("tile-badge", host, bookmark.favicon));

    var label = document.createElement("span");
    label.className = "tile-label";
    label.textContent = bookmark.title ? bookmark.title : host;
    tile.appendChild(label);
    return tile;
  }

  function makeRow(entry) {
    var host = hostOf(entry.url);
    var row = document.createElement("a");
    row.className = "row";
    row.setAttribute("href", entry.url);
    row.appendChild(makeBadge("row-badge", host, entry.favicon));

    var text = document.createElement("span");
    text.className = "row-text";

    var title = document.createElement("span");
    title.className = "row-title";
    title.textContent = entry.title ? entry.title : entry.url;
    text.appendChild(title);

    var url = document.createElement("span");
    url.className = "row-url";
    url.textContent = entry.url;
    text.appendChild(url);

    row.appendChild(text);
    return row;
  }

  function render(data) {
    var bookmarks = Array.isArray(data.bookmarks) ? data.bookmarks : [];
    var recent = Array.isArray(data.recent) ? data.recent : [];

    if (bookmarks.length > 0) {
      var grid = document.getElementById("favourites-grid");
      bookmarks.forEach(function (bookmark) {
        grid.appendChild(makeTile(bookmark));
      });
      document.getElementById("favourites-section").hidden = false;
    }

    if (recent.length > 0) {
      var list = document.getElementById("recent-list");
      recent.forEach(function (entry) {
        list.appendChild(makeRow(entry));
      });
      document.getElementById("recent-section").hidden = false;
    }

    document.getElementById("empty-state").hidden = bookmarks.length > 0 || recent.length > 0;
  }

  fetch("data.json", { cache: "no-store" })
    .then(function (response) {
      return response.json();
    })
    .then(render)
    .catch(function () {
      // A failed payload is still a usable page: it falls back to the empty
      // state rather than leaving a blank document.
      render({ bookmarks: [], recent: [] });
    });
})();
