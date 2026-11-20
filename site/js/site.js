// Page behaviour: mobile navigation, copy buttons, store links and direct
// download links. The page works without any of it; each function upgrades
// markup that is already complete.

const RELEASES_API = "https://api.github.com/repos/UnlikeOtherAI/kelpie/releases?per_page=30";

function setUpNavigation() {
  const header = document.querySelector(".header");
  const toggle = document.querySelector(".nav-toggle");
  if (!header || !toggle) return;

  const setOpen = (open) => {
    header.classList.toggle("is-open", open);
    toggle.setAttribute("aria-expanded", String(open));
  };
  toggle.addEventListener("click", () => setOpen(!header.classList.contains("is-open")));
  header.querySelectorAll("a").forEach((link) => link.addEventListener("click", () => setOpen(false)));
}

function setUpCopyButtons() {
  document.querySelectorAll("[data-copy]").forEach((button) => {
    button.addEventListener("click", async () => {
      try {
        await navigator.clipboard.writeText(button.dataset.copy);
      } catch {
        return;
      }
      button.classList.add("is-done");
      setTimeout(() => button.classList.remove("is-done"), 1800);
    });
  });
}

// Store buttons stay "coming soon" until js/links.js holds a listing URL.
function activateStoreLinks(links) {
  document.querySelectorAll("[data-store]").forEach((button) => {
    const url = links[button.dataset.store];
    if (!url) return;
    button.href = url;
    button.rel = "noopener";
  });
}

function newestAsset(releases, pattern) {
  for (const release of releases) {
    const asset = release.assets.find((candidate) => pattern.test(candidate.name));
    if (asset) return asset;
  }
  return null;
}

function publishedNewestFirst(releases) {
  return releases
    .filter((release) => !release.draft && !release.prerelease)
    .sort((a, b) => new Date(b.published_at) - new Date(a.published_at));
}

// Download buttons link to the releases page. Each one names the file it
// wants in data-asset; when GitHub answers, point it at the newest match.
async function linkLatestDownloads() {
  const buttons = document.querySelectorAll("[data-asset]");
  if (!buttons.length) return;

  let releases;
  try {
    const response = await fetch(RELEASES_API, { headers: { Accept: "application/vnd.github+json" } });
    if (!response.ok) return;
    releases = publishedNewestFirst(await response.json());
  } catch {
    return;
  }

  buttons.forEach((button) => {
    const asset = newestAsset(releases, new RegExp(button.dataset.asset));
    if (!asset) return;
    button.href = asset.browser_download_url;
    const version = asset.name.match(/\d+\.\d+\.\d+/);
    const label = button.querySelector("[data-version]");
    if (version && label) label.textContent = ` ${version[0]}`;
  });
}

setUpNavigation();
setUpCopyButtons();
activateStoreLinks(window.KELPIE_LINKS || {});
linkLatestDownloads();

if (location.origin === "https://kelpie.rocks") {
  import("./analytics.js");
}
