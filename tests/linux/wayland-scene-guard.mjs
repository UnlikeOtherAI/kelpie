import assert from "node:assert/strict";
export function ownedWaylandViews(text,pid) {
 const views=[...text.matchAll(/View \d+ \(role ([^,]+), PID (\d+), surface ID (\d+),/g)]
   .map(match=>({role:match[1],pid:Number(match[2]),surface:Number(match[3])}));
 assert.ok(views.length>0&&views.length<=32&&views.some(view=>view.pid===pid),"OWNED_VIEW_MISSING");
 assert.ok(views.every(view=>view.pid===0||view.pid===pid),"FOREIGN_VIEW");
 return views;
}
