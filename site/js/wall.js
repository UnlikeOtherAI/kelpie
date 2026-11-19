// The hero's device wall. One agent session plays in a loop: each step adds a
// state class to .wall (css/wall.css draws the result on every phone) and
// prints the matching MCP call in the console underneath.
//
// The page holds an empty shelf and a finished still frame of the console.
// This script builds the phones and then replays the session.

// What every phone shows: a page with a Sign up button, and the form behind it.
const PHONE_SCREEN = `
  <div class="phone-screen">
    <i class="mini-progress"></i>
    <div class="mini">
      <div class="mini-view mini-view--home">
        <div class="mini-nav"><i></i><i></i></div>
        <b></b><b class="s"></b>
        <i class="mini-art"></i>
        <i class="mini-text"></i><i class="mini-text s"></i>
        <span class="mini-cta">Sign up</span>
      </div>
      <div class="mini-view mini-view--form">
        <div class="mini-nav"><i></i><i></i></div>
        <b class="s"></b>
        <i class="mini-text"></i>
        <span class="mini-field"><span>ada@example.com</span></span>
        <span class="mini-cta">Continue</span>
      </div>
    </div>
    <div class="mini-bar"><i></i><i></i></div>
    <i class="mini-flash"></i>
  </div>`;

const STEPS = [
  { at: 0, state: "is-nav", call: ["kelpie_group_navigate", '{ url: "https://staging.example.com" }'] },
  { at: 1300, state: "is-loaded", ok: "loaded on 4 devices" },
  { at: 2700, state: "is-found", call: ["kelpie_group_find_button", '{ text: "Sign up" }'] },
  { at: 3500, ok: "found on 4 of 4" },
  { at: 4900, state: "is-tapped", call: ["kelpie_group_click", '{ selector: "#sign-up" }'] },
  { at: 5500, state: "is-form" },
  { at: 6500, state: "is-filled", call: ["kelpie_group_fill", '{ selector: "#email", value: "ada@example.com" }'] },
  { at: 7700, ok: "filled on 4 of 4" },
  { at: 8900, state: "is-shot", call: ["kelpie_group_screenshot", "{}"] },
  { at: 9800, ok: "4 screenshots returned" },
];
const LOOP_MS = 12600;
const START_DELAY_MS = 400;
const VISIBLE_LINES = 5;
const STATES = STEPS.map((step) => step.state).filter(Boolean);

// One phone per name in data-phones, oldest outline first.
function buildPhones(wall) {
  const shelf = wall.querySelector(".wall-shelf");
  if (!shelf) return;

  shelf.dataset.phones.split(" ").forEach((kind) => {
    const phone = document.createElement("div");
    phone.className = `phone phone--${kind}`;
    phone.innerHTML = PHONE_SCREEN;
    shelf.append(phone);
  });
}

function logLine(log, step) {
  const line = document.createElement("li");
  if (step.call) {
    line.className = "log-call";
    const name = document.createElement("b");
    name.textContent = step.call[0];
    line.append(name, ` ${step.call[1]}`);
  } else {
    line.className = "log-ok";
    line.textContent = step.ok;
  }
  log.append(line);
  while (log.children.length > VISIBLE_LINES) log.firstElementChild.remove();
}

function applyStep(wall, log, step) {
  if (step.state) wall.classList.add(step.state);
  if (step.call || step.ok) logLine(log, step);
}

function reset(wall, log) {
  wall.classList.remove(...STATES);
  log.replaceChildren();
}

function startLoop(wall, log) {
  let timers = [];
  const playOnce = () => {
    reset(wall, log);
    timers = STEPS.map((step) => setTimeout(() => applyStep(wall, log, step), step.at + START_DELAY_MS));
    timers.push(setTimeout(playOnce, LOOP_MS));
  };
  const stop = () => {
    timers.forEach(clearTimeout);
    timers = [];
  };

  // Play only while the wall is on screen.
  new IntersectionObserver(([entry]) => {
    stop();
    if (entry.isIntersecting) playOnce();
  }, { threshold: 0.25 }).observe(wall);
}

function setUpWall() {
  const wall = document.querySelector(".wall");
  const log = wall?.querySelector(".console-log");
  if (!wall || !log) return;

  buildPhones(wall);
  // With reduced motion the still frame in the markup stays as it is.
  if (!window.matchMedia("(prefers-reduced-motion: reduce)").matches) startLoop(wall, log);
}

setUpWall();
