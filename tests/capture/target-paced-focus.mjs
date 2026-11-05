import assert from "node:assert/strict";
import {createRequire} from "node:module";
import {writeFile} from "node:fs/promises";
import {resolveScriptTarget} from "../../packages/shared/src/script-target.ts";
const require=createRequire(new URL("../../packages/cli/package.json",import.meta.url));
const {chromium}=require("playwright-core");
const output=process.argv[2];assert.ok(output);
const browser=await chromium.launch({headless:true,chromiumSandbox:true});
const source=resolveScriptTarget.toString(),report={browser:browser.version(),cases:[]};
const timer=setTimeout(()=>{void browser.close().finally(()=>process.exit(124));},20000);
try {
 const page=await browser.newPage();
 await page.setContent('<input id="first"><input id="other">');
 const call=args=>page.evaluate("("+source+")(..."+JSON.stringify(args)+")");
 const target={selector:"#first"};
 const first=await call([target,"paced-focus"]);assert.equal(first.ok,true);
 await page.focus("#first");
 await page.evaluate(()=>{window.inputCount=0;document.querySelector("#first").addEventListener("input",()=>window.inputCount++);});
 const success=await call([target,"paced-focus",first.token,false,{action:"type",text:"\\u{1F600}",requireFocused:true}]);
 assert.equal(success.ok,true);assert.equal(await page.locator("#first").inputValue(),"\\u{1F600}");
 assert.equal(await page.evaluate(()=>window.inputCount),1);
 report.cases.push({name:"focused-astral",passed:true});
 await page.focus("#other");
 const refused=await call([target,"paced-focus",first.token,false,{action:"type",text:"X",requireFocused:true}]);
 assert.equal(refused.ok,false);assert.equal(refused.error,"INPUT_UNCERTAIN");
 assert.equal(refused.focusFailure,"target-focus");assert.equal(refused.sensitivityKnown,false);
 assert.equal(await page.locator("#first").inputValue(),"\\u{1F600}");
 assert.equal(await page.evaluate(()=>[document.activeElement.id,window.inputCount].join(":")),"other:1");
 report.cases.push({name:"focus-drift-no-refocus",passed:true});
} finally {
 clearTimeout(timer);await writeFile(output,JSON.stringify(report,null,2),{flag:"wx"});await browser.close();
}
