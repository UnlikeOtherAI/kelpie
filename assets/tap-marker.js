(function (x, y, rgb, style, durationMs) {
    if (!document.body) return;

    const position = 'position:fixed;left:' + x + 'px;top:' + y + 'px;' +
        'pointer-events:none;z-index:2147483647;';
    const color = 'rgba(' + rgb + ',0.7)';
    if (style === 'crosshair-coordinates') {
        const marker = document.createElement('div');
        marker.setAttribute('aria-hidden', 'true');
        marker.style.cssText = position + 'width:0;height:0;opacity:1;transition:opacity 0.5s ease-out;';

        for (const size of ['24px;height:2px', '2px;height:24px']) {
            const line = document.createElement('div');
            line.style.cssText = 'position:absolute;left:0;top:0;transform:translate(-50%,-50%);' +
                'pointer-events:none;width:' + size + ';background:' + color + ';';
            marker.appendChild(line);
        }

        const format = (value) => String(Math.round(value * 100) / 100);
        const pair = (px, py) => format(px) + ', ' + format(py);
        const label = document.createElement('div');
        label.textContent = 'Viewport: ' + pair(x, y) + '\nPage: ' + pair(x + window.scrollX, y + window.scrollY);
        label.style.cssText = 'position:absolute;pointer-events:none;box-sizing:border-box;padding:4px 6px;' +
            'max-width:calc(100vw - 8px);width:max-content;white-space:pre-wrap;overflow-wrap:anywhere;' +
            'font:12px/1.4 monospace;text-align:left;color:#fff;background:#172033;border-radius:4px;';
        marker.appendChild(label);
        document.body.appendChild(marker);

        // Keep the label readable near viewport edges without moving the crosshair.
        const {width, height} = label.getBoundingClientRect();
        const left = x + 16 + width <= window.innerWidth - 4 ? x + 16 : x - 16 - width;
        const top = y + 16 + height <= window.innerHeight - 4 ? y + 16 : y - 16 - height;
        label.style.left = Math.max(4, Math.min(left, window.innerWidth - width - 4)) - x + 'px';
        label.style.top = Math.max(4, Math.min(top, window.innerHeight - height - 4)) - y + 'px';
        setTimeout(() => {
            marker.style.opacity = '0';
            setTimeout(() => marker.remove(), 550);
        }, durationMs);
        return;
    }

    const circle = position + 'width:36px;height:36px;margin-left:-18px;margin-top:-18px;' +
        'border-radius:50%;transform:scale(1);opacity:1;';
    const dot = document.createElement('div');
    dot.style.cssText = circle + 'background:' + color + ';' +
        'transition:transform 0.5s ease-out, opacity 0.5s ease-out;';
    document.body.appendChild(dot);
    const ripple = document.createElement('div');
    ripple.style.cssText = circle + 'border:2px solid ' + color + ';' +
        'transition:transform 0.6s ease-out, opacity 0.6s ease-out;';
    document.body.appendChild(ripple);
    requestAnimationFrame(() => {
        ripple.style.transform = 'scale(3)';
        ripple.style.opacity = '0';
    });
    setTimeout(() => ripple.remove(), 1100);
    // Establish the initial style even if an immediate fade starts before the next paint.
    if (durationMs === 0) dot.getBoundingClientRect();
    setTimeout(() => {
        dot.style.transform = 'scale(0.5)';
        dot.style.opacity = '0';
        setTimeout(() => dot.remove(), 550);
    }, durationMs);
})
