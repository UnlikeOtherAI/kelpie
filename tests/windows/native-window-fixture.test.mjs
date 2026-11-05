import test from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import {nativeWindowFixtureExpression} from "./native-window-fixture.mjs";
test("native fixture creates stable identity without page crypto",()=>{
 const id="11111111-2222-4333-8444-555555555555";
 const rect={left:150,top:150,width:160,height:60,toJSON(){return {left:this.left,top:this.top,width:this.width,height:this.height};}};
 const button={getBoundingClientRect:()=>rect};
 const document={body:{style:{}},getElementById:()=>button};
 const window={};const context={document,window,innerWidth:1042,innerHeight:662,devicePixelRatio:1,visualViewport:{scale:1}};
 const result=vm.runInNewContext(nativeWindowFixtureExpression(id),context);
 assert.equal(result.documentId,id);assert.equal(result.target.x,230);assert.equal(result.target.y,180);
 button.onclick({isTrusted:true,clientX:230,clientY:180});
 assert.equal(window.__nativeCaptureClick.documentId,id);assert.equal(window.__nativeCaptureClick.trusted,true);
 assert.equal(Object.hasOwn(context,"crypto"),false);
});
test("fixture identity rejects authored executable syntax",()=>{
 assert.throws(()=>nativeWindowFixtureExpression("';throw Error('inject');//"));
});
