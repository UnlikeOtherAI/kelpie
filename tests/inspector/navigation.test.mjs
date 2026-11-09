import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';
import { readFile, mkdir } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(new URL('../../packages/shared/package.json', import.meta.url));
const { chromium, webkit } = require('playwright-core');
const root = fileURLToPath(new URL('../../', import.meta.url));
const resources = 'core/apple/shared/Resources/Snapshot3D';
const phases = ['enter-setup', 'enter-collect', 'enter-apply', 'enter-scene', 'enter-tree', 'enter-tools', 'enter-input'];
const enter = (await Promise.all(phases.map(name => readFile(path.join(root, resources, name + '.js'), 'utf8')))).join('\n');
const exit = await readFile(path.join(root, resources, 'exit.js'), 'utf8');
const fixture = await readFile(new URL('fixture.html', import.meta.url), 'utf8');
let browser;
before(async () => {
    const engine = process.env.KELPIE_TEST_ENGINE === 'webkit' ? webkit : chromium;
    browser = await engine.launch({ headless: true, ...(process.env.KELPIE_TEST_EXECUTABLE ? {executablePath: process.env.KELPIE_TEST_EXECUTABLE} : {}) });
});
after(async () => { await browser?.close(); });

async function scene(viewport = {width: 1280, height: 900}, source = enter) {
    const page = await browser.newPage({viewport});
    await page.setContent(fixture);
    const image = (await page.screenshot()).toString('base64');
    await page.evaluate(source);
    await page.evaluate(image => window.__m3d.setPreview?.('data:image/png;base64,' + image), image);
    return page;
}
async function drag(page, x, y, dx, dy) {
    await page.mouse.move(x, y); await page.mouse.down();
    await page.mouse.move(x + dx, y + dy, {steps: 8}); await page.mouse.up();
}
const transform = page => page.locator('body').evaluate(el => el.style.transform);

test('Apple and Android bundle identical scene and tool sources', async () => {
    for (const name of [...phases, 'exit']) {
        assert.equal(await readFile(path.join(root, 'core/android/src/main/assets/snapshot3d', name + '.js'), 'utf8'),
            await readFile(path.join(root, resources, name + '.js'), 'utf8'), name);
    }
});

test('navigation, zoom, separation and orientation work through visible controls', async () => {
    const page = await scene();
    try {
        await page.getByRole('button', {name: 'Pan 3D view', exact: true}).click();
        const initial = await transform(page);
        await drag(page, 650, 700, 75, -40);
        assert.notEqual(await transform(page), initial);
        assert.match(await transform(page), /scale\(0.85\).*rotateX\(15deg\).*rotateY\(-25deg\)/);
        const panned = await transform(page);
        await page.mouse.wheel(0, 420);
        await page.waitForFunction(previous => document.body.style.transform !== previous, panned);
        assert.match(await transform(page), /scale\(0.85\).*rotateX\(15deg\).*rotateY\(-25deg\)/);
        await page.getByRole('button', {name: 'Move page down without zooming', exact: true}).click();
        assert.match(await transform(page), /scale\(0.85\)/);

        await page.getByRole('button', {name: 'Rotate 3D view', exact: true}).click();
        await drag(page, 650, 700, 50, 30);
        assert.notEqual(await transform(page), initial);
        await page.getByLabel('3D zoom level', {exact: true}).selectOption('125');
        assert.match(await transform(page), /scale\(1.25\)/);
        await page.getByRole('slider', {name: 'Layer separation'}).focus();
        await page.keyboard.press('Home');
        assert.equal(await page.evaluate(() => window.__m3d.spacing), 0);
        assert.equal(await page.locator('#intro').evaluate(el => el.style.transform), 'translateZ(0px)');
        await page.keyboard.press('End');
        assert.equal(await page.evaluate(() => window.__m3d.spacing), 80);
        await page.getByRole('button', {name: 'Front view (Z axis)', exact: true}).click();
        assert.match(await transform(page), /rotateX\(0deg\) rotateY\(0deg\)/);
        const orbit = await page.getByLabel('Drag to rotate page orientation').boundingBox();
        await drag(page, orbit.x + 60, orbit.y + 70, 20, 15);
        assert.doesNotMatch(await transform(page), /rotateX\(0deg\) rotateY\(0deg\)/);
        assert.equal(await page.getByAltText('Snapshot of the inspected website').evaluate(el => el.complete && el.naturalWidth > 0), true);
        assert.equal(await page.evaluate(() => !!window.fixtureClicked), false);
    } finally { await page.close(); }
});

test('tree hover reveals off-screen planes without changing zoom or rotation', async () => {
    const page = await scene();
    try {
        await page.getByRole('button', {name: 'Front view (Z axis)', exact: true}).click();
        await page.getByLabel('3D zoom level', {exact: true}).selectOption('75');
        await page.getByRole('button', {name: 'Open element toolbox', exact: true}).click();
        await page.getByRole('treeitem', {name: '<main#main>', exact: true}).locator('.disclosure').click();
        const far = page.getByRole('treeitem', {name: '<section#far.card>', exact: true});
        await far.hover();
        assert.match(await transform(page), /scale\(0.75\) rotateX\(0deg\) rotateY\(0deg\)/);
        const rect = await page.locator('#far').boundingBox();
        assert.ok(rect.y < 820 && rect.y + rect.height > 24, JSON.stringify(rect));
        assert.match(await page.locator('#far').evaluate(el => el.style.outline), /3px/);
        assert.equal(await far.getAttribute('aria-selected'), 'true');
        // Return from the footer to the header without zooming out or resetting.
        await page.getByRole('treeitem', {name: '<header>', exact: true}).hover();
        const header = await page.locator('body > header').boundingBox();
        assert.ok(header.y < 820 && header.y + header.height > 24, JSON.stringify(header));
        assert.match(await transform(page), /scale\(0.75\) rotateX\(0deg\) rotateY\(0deg\)/);
        const hidden = page.getByRole('treeitem', {name: '<div#hidden-node>', exact: true});
        await hidden.hover();
        assert.match(await page.locator('#__m3d_info').textContent(), /no rendered plane/);
    } finally { await page.close(); }
});

test('page hover expands and highlights matching tree rows, including shadow DOM', async () => {
    const page = await scene();
    try {
        await page.getByRole('button', {name: 'Pan 3D view', exact: true}).click();
        await drag(page, 750, 740, 300, 0);
        await page.getByRole('button', {name: 'Open element toolbox', exact: true}).click();
        await page.getByRole('button', {name: 'Front view (Z axis)', exact: true}).click();
        // Use the rendered plane coordinates; the capture layer must not win the hit test.
        const box = await page.locator('#action').boundingBox();
        await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
        assert.equal(await page.getByRole('treeitem', {name: '<button#action>', exact: true}).getAttribute('aria-selected'), 'true');
        const shadow = await page.locator('#shadow-action').boundingBox();
        await page.mouse.move(shadow.x + shadow.width / 2, shadow.y + shadow.height / 2);
        assert.equal(await page.getByRole('treeitem', {name: '<button#shadow-action>', exact: true}).getAttribute('aria-selected'), 'true');
    } finally { await page.close(); }
});

test('phone tools remain reachable and touch drags preserve pan semantics', async () => {
    const context = await browser.newContext({viewport: {width: 390, height: 844}, hasTouch: true, isMobile: true});
    const page = await context.newPage();
    try {
        await page.setContent(fixture);
        await page.evaluate(enter);
        await page.getByRole('button', {name: 'Pan 3D view', exact: true}).tap();
        const initial = await transform(page);
        await page.evaluate(() => {
            const capture = document.querySelector('#__m3d_input');
            const touch = (x, y) => new Touch({identifier: 1, target: capture, clientX: x, clientY: y});
            capture.dispatchEvent(new TouchEvent('touchstart', {bubbles: true, cancelable: true, touches: [touch(180, 600)]}));
            capture.dispatchEvent(new TouchEvent('touchmove', {bubbles: true, cancelable: true, touches: [touch(210, 570)]}));
            capture.dispatchEvent(new TouchEvent('touchend', {bubbles: true, changedTouches: [touch(210, 570)], touches: []}));
        });
        assert.notEqual(await transform(page), initial);
        assert.match(await transform(page), /scale\(0.85\).*rotateX\(15deg\).*rotateY\(-25deg\)/);
        await page.getByRole('button', {name: 'Open element toolbox', exact: true}).tap();
        await page.getByRole('button', {name: 'Close element toolbox', exact: true}).tap();
        assert.equal(await page.getByRole('tree', {name: 'Page elements'}).isVisible(), false);
    } finally { await context.close(); }
});

test('exit and re-entry restore source styles and remove scene listeners', async () => {
    const page = await scene();
    try {
        await page.getByRole('button', {name: 'Open element toolbox', exact: true}).click();
        await page.evaluate(enter); // stale state must self-heal, without duplicate UI
        assert.equal(await page.getByRole('navigation', {name: '3D navigation'}).count(), 1);
        await page.evaluate(exit);
        assert.equal(await page.locator('#__m3d_overlay').count(), 0);
        assert.equal(await page.locator('[data-m3d-depth]').count(), 0);
        assert.equal(await transform(page), '');
        await page.locator('#action').click();
        assert.equal(await page.evaluate(() => window.fixtureClicked), true);
    } finally { await page.close(); }
});

test('desktop and phone screenshot pairs use matching base and final scenes', {skip: !process.env.KELPIE_SCREENSHOTS}, async () => {
    const dir = path.resolve(process.env.KELPIE_SCREENSHOTS);
    await mkdir(dir, {recursive: true});
    const base = process.env.KELPIE_BASE_REVISION || 'ae744915';
    const baseline = ['enter-setup', 'enter-collect', 'enter-apply', 'enter-input'].map(name =>
        execFileSync('git', ['show', `${base}:${resources}/${name}.js`], {cwd: root, encoding: 'utf8'})).join('\n');
    for (const [name, viewport] of [['desktop', {width: 1280, height: 900}], ['phone', {width: 390, height: 844}]]) {
        for (const [revision, script] of [['before', baseline], ['after', enter]]) {
            const page = await scene(viewport, script);
            try {
                await page.screenshot({path: path.join(dir, `${name}-${revision}.png`)});
                if (revision === 'after') {
                    await page.getByRole('button', {name: 'Open element toolbox', exact: true}).click();
                    await page.screenshot({path: path.join(dir, `${name}-toolbox-after.png`)});
                }
            } finally { await page.close(); }
        }
    }
});
