import {test} from "node:test";
import assert from "node:assert/strict";
import {ownedWaylandViews} from "./wayland-scene-guard.mjs";
const own="View 1 (role xdg_toplevel, PID 42, surface ID 9, visible)\n";
const background="View 2 (role background, PID 0, surface ID 0, visible)\n";
test("only owned app and compositor background are accepted",()=>{
 assert.equal(ownedWaylandViews(own+background,42).length,2);
 assert.throws(()=>ownedWaylandViews(background,42),/OWNED_VIEW_MISSING/);
 assert.throws(()=>ownedWaylandViews(own+"View 4 (role xdg_toplevel, PID unknown, surface ID 8, visible)\n",42),/UNPARSED_VIEW/);
 assert.throws(()=>ownedWaylandViews(own+"View 3 (role xdg_toplevel, PID 99, surface ID 7, visible)\n",42),/FOREIGN_VIEW/);
});
