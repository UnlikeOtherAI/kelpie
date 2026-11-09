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
   * Tile tones mirror `SiteTone` in
   * `core/apple/macos/Views/StartPageView.swift`: six tones indexed by the sum
   * of the host's Unicode scalars. The colours themselves live in `start.css`
   * as `.tone-0` … `.tone-5`.
   */
  var PALETTE_SIZE = 6;

  function hostOf(url) {
    try {
      var host = new URL(url).host;
      return host || url;
    } catch (error) {
      return url;
    }
  }

  // The card caption: the host without a leading `www.`.
  function displayDomain(host) {
    return host.replace(/^www\./i, "");
  }

  function toneClass(host) {
    // Swift folds over `unicodeScalars`, so iterate code points rather than
    // UTF-16 units to keep non-ASCII hosts on the same colour as macOS.
    var sum = 0;
    Array.from(host).forEach(function (character) {
      sum += character.codePointAt(0);
    });
    return "tone-" + (Math.abs(sum) % PALETTE_SIZE);
  }

  // The engine already drops anything that is not an http(s) URL. This repeats
  // the check so a link in this origin can never be built from another scheme,
  // whatever produced the payload.
  function isWebUrl(url) {
    return /^https?:\/\//i.test(String(url));
  }

  // Images may only come from this origin's own preview route or an inline PNG
  // favicon; anything else in the payload is ignored.
  function isFavicon(value) {
    return typeof value === "string" && value.indexOf("data:image/png;base64,") === 0;
  }

  function isPreview(value) {
    return typeof value === "string" && /^preview\/[0-9a-f]{1,512}\.jpg(\?v=[0-9]{1,20})?$/.test(value);
  }

  function initialOf(host) {
    var characters = Array.from(displayDomain(host));
    return characters.length > 0 ? characters[0].toUpperCase() : "?";
  }

  function makeImage(className, source) {
    var image = document.createElement("img");
    if (className) {
      image.className = className;
    }
    image.setAttribute("src", source);
    image.setAttribute("alt", "");
    image.setAttribute("decoding", "async");
    image.setAttribute("draggable", "false");
    return image;
  }

  // The favicon, or the site's initial when there is none.
  function fillIcon(element, host, favicon) {
    if (isFavicon(favicon)) {
      element.appendChild(makeImage("", favicon));
    } else {
      element.classList.add("is-letter");
      element.textContent = initialOf(host);
    }
  }

  // The tile shown until Kelpie has a screenshot of the site.
  function showPlaceholder(shot, host, favicon) {
    while (shot.firstChild) {
      shot.removeChild(shot.firstChild);
    }
    shot.classList.add("is-placeholder");
    var glyph = document.createElement("span");
    glyph.className = "site-glyph";
    fillIcon(glyph, host, favicon);
    shot.appendChild(glyph);
  }

  function makeShot(host, entry) {
    var shot = document.createElement("span");
    shot.className = "site-shot " + toneClass(host);
    if (!isPreview(entry.thumbnail)) {
      showPlaceholder(shot, host, entry.favicon);
      return shot;
    }
    var thumbnail = makeImage("site-thumb", entry.thumbnail);
    thumbnail.setAttribute("loading", "lazy");
    // A preview that disappeared between the payload and the request falls
    // back to the tile rather than a broken image.
    thumbnail.addEventListener("error", function () {
      showPlaceholder(shot, host, entry.favicon);
    });
    shot.appendChild(thumbnail);

    var badge = document.createElement("span");
    badge.className = "site-icon";
    fillIcon(badge, host, entry.favicon);
    shot.appendChild(badge);
    return shot;
  }

  function makeCard(entry, order) {
    var host = hostOf(entry.url);
    var card = document.createElement("a");
    card.className = "site";
    card.setAttribute("href", entry.url);
    card.setAttribute("rel", "noreferrer");
    card.setAttribute("title", entry.title ? entry.title : entry.url);
    card.setAttribute("draggable", "false");
    // Staggers the entrance animation. CSSOM writes are not inline styles, so
    // the page's Content-Security-Policy allows them.
    card.style.setProperty("--order", String(Math.min(order, 24)));
    card.appendChild(makeShot(host, entry));

    var domain = document.createElement("span");
    domain.className = "site-domain";
    domain.textContent = displayDomain(host);
    card.appendChild(domain);
    return card;
  }

  function webEntries(list) {
    return (Array.isArray(list) ? list : []).filter(function (entry) {
      return entry && isWebUrl(entry.url);
    });
  }

  function fill(sectionId, gridId, entries, firstOrder) {
    if (entries.length === 0) {
      return;
    }
    var grid = document.getElementById(gridId);
    entries.forEach(function (entry, index) {
      grid.appendChild(makeCard(entry, firstOrder + index));
    });
    document.getElementById(sectionId).hidden = false;
  }

  function render(data) {
    var bookmarks = webEntries(data.bookmarks);
    var recent = webEntries(data.recent);
    fill("favourites-section", "favourites-grid", bookmarks, 0);
    fill("recent-section", "recent-grid", recent, bookmarks.length);
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
