# 3D inspector

On phones and narrow tablet windows, open More and select the 3D inspector cube.
On wider tablets, Windows and Linux, select the cube beside the three dots. On macOS
the engine switch sits between the cube
and the three dots in builds with both WebKit and Chromium. The toolbar action
uses WebKit on macOS and Chromium on Windows and Linux. On iOS, Android and macOS
you can also enter with `snapshot-3d-enter`.

The left toolbar selects Rotate, Pan, Scroll or Inspect, opens Elements, and resets
the camera. Dedicated up/down buttons move the page by 60% of the viewport height
at its current zoom. Arrow keys also pan. In Pan mode, wheel/trackpad movement
pans the scene; Control-wheel still zooms. Rotate changes the viewing angle; Pan translates the camera without
changing rotation or zoom; Scroll moves through the source document. Inspect
highlights a plane on tap without starting a camera drag. Mouse hover highlights
planes in every mode.

The right column contains a page orientation card, zoom controls, and a vertical
layer separation slider. The orientation card uses a native viewport screenshot
captured before the DOM is transformed. Red, green and blue rings represent X, Y
and Z. Drag the card to rotate, or select Top, Side or Front. The zoom percentage
tracks button, wheel and pinch input. Layer separation ranges from 0 to 80 px.

Elements opens the complete accessible element hierarchy, rooted at HTML. It
includes hidden nodes, open shadow roots and same-origin iframe documents. Expand
branches with their disclosure arrows or Left/Right keys; move between visible
rows with Up/Down. Hovering, focusing or selecting a row highlights its plane. If
the plane is outside the visible scene, the camera translates to it while retaining
its zoom and angle. For same-origin frames, it reveals clipped content inside each
containing frame before moving the outer camera; exit restores those frame scroll
positions. Hovering the page reveals the matching row and expands its
ancestors. Only the toolbox scrolls when a matching row needs to be shown.

Unrendered nodes and nodes beyond the existing 5,000-plane render limit remain
browsable and show an explanation instead of moving the camera. Closed shadow
roots and cross-origin frame contents are inaccessible. Branches load on demand;
the toolbox does not continuously monitor site mutations.

The card and toolbox use a scene-local shadow root, outside the transformed body,
so website CSS does not style the controls. Existing native shell controls remain
available. Exiting removes the overlay and event listeners and
restores element styles, viewport pivot and scrolling. Re-entry cleans stale scene
state automatically. The preview is kept only in memory for the current session.

On phone widths the right card narrows and the toolbox opens below the left tools.
Landscape layouts shorten the preview and slider to keep controls reachable.
Short, narrow windows open the tree beside the tools so its close action remains
inside the viewport.
