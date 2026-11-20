const measurementId = "G-Q4485DL97E";
const preferenceKey = "kelpie-website-analytics";
const disableKey = `ga-disable-${measurementId}`;

function readPreference() {
  try {
    return localStorage.getItem(preferenceKey);
  } catch {
    return null;
  }
}

function savePreference(choice) {
  try {
    localStorage.setItem(preferenceKey, choice);
  } catch {
    // The choice still applies to this page when storage is unavailable.
  }
}

function enableAnalytics() {
  window[disableKey] = false;
  if (window.gtag) return;

  window.dataLayer = window.dataLayer || [];
  window.gtag = function () {
    window.dataLayer.push(arguments);
  };
  window.gtag("js", new Date());
  window.gtag("config", measurementId, {
    allow_google_signals: false,
    allow_ad_personalization_signals: false,
    cookie_domain: "none",
  });

  const tag = document.createElement("script");
  tag.async = true;
  tag.src = `https://www.googletagmanager.com/gtag/js?id=${measurementId}`;
  document.head.append(tag);
}

function disableAnalytics() {
  window[disableKey] = true;
  for (const name of ["_ga", `_ga_${measurementId.slice(2)}`]) {
    document.cookie = `${name}=; Max-Age=0; Path=/; Secure; SameSite=Lax`;
  }
}

const settings = document.createElement("button");
settings.type = "button";
settings.className = "analytics-settings";
settings.textContent = "Analytics settings";
document.querySelector(".footer-legal nav").append(settings);

const panel = document.createElement("section");
panel.className = "analytics-panel";
panel.setAttribute("aria-labelledby", "analytics-heading");
panel.innerHTML = `
  <h2 id="analytics-heading">Website analytics</h2>
  <p>Allow Google Analytics to measure visits to kelpie.rocks?</p>
  <div class="analytics-actions">
    <button type="button" value="declined">Decline analytics</button>
    <button type="button" value="allowed">Allow analytics</button>
  </div>`;
document.body.append(panel);

function applyPreference(preference) {
  panel.hidden = preference === "allowed" || preference === "declined";
  if (preference === "allowed") enableAnalytics();
  else if (window.gtag) disableAnalytics();
}

applyPreference(readPreference());
window.addEventListener("storage", event => {
  if (event.key === preferenceKey || event.key === null) applyPreference(readPreference());
});

const choices = panel.querySelectorAll("button");
let openedFromSettings = false;
settings.addEventListener("click", () => {
  openedFromSettings = true;
  panel.hidden = false;
  choices[0].focus();
});

for (const choice of choices) {
  choice.addEventListener("click", () => {
    savePreference(choice.value);
    applyPreference(choice.value);
    if (openedFromSettings) settings.focus({ preventScroll: true });
    openedFromSettings = false;
  });
}
