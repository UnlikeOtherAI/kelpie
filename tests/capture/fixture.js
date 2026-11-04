// Synthetic fixture data only. Never enter real credentials here.
(() => {
  const documentId = crypto.randomUUID();
  document.querySelector("#document-marker").textContent = "document:" + documentId.slice(0, 8);
  let sequence = 0;
  let motion = null;
  const pending = new Set();
  const send = value => {
    const promise = fetch("/events", {
      method: "POST", headers: { "content-type": "application/json" },
      body: JSON.stringify({ documentId, sequence: ++sequence, ...value }),
    }).finally(() => pending.delete(promise));
    pending.add(promise);
  };
  for (const type of ["pointermove", "pointerdown", "pointerup", "click"]) {
    document.addEventListener(type, event => {
      const target = event.target.closest("button,a");
      const rect = target?.getBoundingClientRect();
      const value = {
        type, target: target?.id ?? null, trusted: event.isTrusted,
        x: event.clientX, y: event.clientY, time: performance.now(),
        visible: rect ? { left: Math.max(0, rect.left), top: Math.max(0, rect.top),
          right: Math.min(innerWidth, rect.right), bottom: Math.min(innerHeight, rect.bottom) } : null,
        dpr: devicePixelRatio, scrollX, scrollY,
        viewport: { width: innerWidth, height: innerHeight, scale: visualViewport?.scale ?? 1 },
        hit: document.elementFromPoint(event.clientX, event.clientY)?.closest("button,a")?.id ?? null,
      };
      if (type === "click") document.querySelector("#events").textContent = JSON.stringify(value);
      send(value);
    }, true);
  }
  document.querySelector("#uncover").onclick = () => { document.querySelector("#cover").hidden = true; };
  document.querySelector("#start-moving").onclick = () => {
    if (!motion) motion = document.querySelector("#moving").animate(
      [{ transform: "translateX(0px)" }, { transform: "translateX(120px)" }],
      { duration: 800, iterations: Infinity, direction: "alternate" });
  };
  document.querySelector("#stop-moving").onclick = () => { motion?.cancel(); motion = null; };
  document.querySelector("#replace").onclick = () => {
    const button = document.querySelector("#unique"); button.replaceWith(button.cloneNode(true));
  };
  const startTask = failed => {
    const status = document.querySelector("#task-status");
    status.textContent = "loading"; status.dataset.ready = "false";
    setTimeout(() => {
      status.textContent = failed ? "failed" : "complete"; status.dataset.ready = failed ? "false" : "true";
      send({ type: "task", state: status.textContent });
    }, 700);
  };
  document.querySelector("#start-task").onclick = () => startTask(false);
  document.querySelector("#fail-task").onclick = () => startTask(true);
  send({ type: "document", url: location.href });
  window.captureFixture = { documentId, flush: () => Promise.all([...pending]) };
})();
