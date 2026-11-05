import assert from "node:assert/strict";

// Private test evidence: native bounds/contentRect use points; visualViewport uses CSS pixels.
export function g08NativeGeometry(artifact, scene) {
  const g = artifact.geometry;
  assert.equal(g?.kind, "constant-native-content", "INSUFFICIENT_EVIDENCE native geometry");
  assert.match(g.fixtureDocumentId ?? "", /^[0-9]{13}-[a-z0-9]{1,16}$/);
  assert.equal(g.fixtureDocumentId, scene.start.documentId);
  assert.ok(typeof g.nativeDocumentId === "string" && g.nativeDocumentId.length > 0);
  assert.equal(g.nativeDocumentId, artifact.documentId);
  assert.equal(g.stableNativeDocument, true);
  assert.ok(Number.isSafeInteger(g.observedFrames) && Number.isSafeInteger(g.encodedFrames));
  assert.equal(g.encodedFrames, artifact.timestamps.length);
  assert.ok(g.observedFrames >= g.encodedFrames);
  const b = g.nativeBounds, r = g.contentRect, v = g.visualViewport;
  assert.ok([b?.width,b?.height,r?.x,r?.y,r?.width,r?.height,
    v?.offsetLeft,v?.offsetTop,v?.width,v?.height,v?.scale].every(Number.isFinite));
  assert.ok(b.width > 0 && b.height > 0 && r.x >= 0 && r.y >= 0 &&
    r.width > 0 && r.height > 0 && r.x+r.width <= b.width && r.y+r.height <= b.height &&
    v.width > 0 && v.height > 0 && v.scale > 0);
  for (const event of [scene.warmup,scene.calibration,scene.start,scene.finish]) {
    assert.ok(event, "INSUFFICIENT_EVIDENCE fixture event");
    assert.equal(event.documentId,g.fixtureDocumentId);
    assert.deepEqual(event.visualViewport,v);
  }
  const sx=r.width/v.width, sy=r.height/v.height;
  assert.ok(Math.abs(sx-sy)<0.01,"INSUFFICIENT_EVIDENCE nonuniform content transform");
  const scale={x:artifact.width/b.width,y:artifact.height/b.height};
  assert.ok(Math.abs(scale.x-scale.y)<0.01,"INSUFFICIENT_EVIDENCE nonuniform frame transform");
  const point=p=>({x:r.x+(p.x-v.offsetLeft)*sx,y:r.y+(p.y-v.offsetTop)*sy});
  return {from:point(scene.start.center),to:point(scene.finish.center),scale,radius:48*sx};
}
