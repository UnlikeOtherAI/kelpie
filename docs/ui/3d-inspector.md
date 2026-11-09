# 3D inspector

The experimental inspector is supported by macOS, iOS and Android, including
embedded browsers. Enter through the browser's 3D action or `snapshot-3d-enter`.

The left toolbar selects Rotate, Pan, Scroll or Inspect, opens Elements, and resets
the camera. Rotate changes the viewing angle; Pan translates the camera without
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
its zoom and angle. Hovering the page reveals the matching row and expands its
ancestors. Only the toolbox scrolls when a matching row needs to be shown.

Unrendered nodes and nodes beyond the existing 5,000-plane render limit remain
browsable and show an explanation instead of moving the camera. Closed shadow
roots and cross-origin frame contents are inaccessible. Branches load on demand;
the toolbox does not continuously monitor site mutations.

The card and toolbox use a scene-local shadow root, outside the transformed body,
so website CSS does not style the controls. Existing native shell controls remain
available, including Exit. Exiting removes the overlay and event listeners and
restores element styles, viewport pivot and scrolling. Re-entry cleans stale scene
state automatically. The preview is kept only in memory for the current session.

On phone widths the right card narrows and the toolbox opens below the left tools.
Landscape layouts shorten the preview and slider to keep controls reachable.
