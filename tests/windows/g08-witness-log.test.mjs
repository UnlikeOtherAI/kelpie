import {test} from "node:test";
import assert from "node:assert/strict";
import {createG08WitnessLog} from "./g08-witness-log.mjs";
const row=(index,pts=0)=>`KELPIE_TEST_G08_ROI_ROW ${index} ${pts} ${"a".repeat(64)}`;
test("requires an ordered bounded hash-only stream and exact completion",()=>{
 const good=createG08WitnessLog();good.accept(row(0));good.accept(row(1,500000));good.accept("KELPIE_TEST_G08_ROI_DONE 2");
 assert.equal(good.finish()?.length,2);
 for(const lines of [[row(0)],[row(1),"KELPIE_TEST_G08_ROI_DONE 1"],[row(0),"KELPIE_TEST_G08_ROI_DONE 2"],
  [row(0),"KELPIE_TEST_G08_ROI_DONE 1","KELPIE_TEST_G08_ROI_DONE 1"],[row(0)+" private","KELPIE_TEST_G08_ROI_DONE 1"]]){
  const log=createG08WitnessLog();for(const line of lines)log.accept(line);assert.equal(log.finish(),null);
 }
});
