import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createNoHistoryProbe} from './no-history-probe.mjs';
test('requires one beacon with the exact run binding and one-entry result',()=>{
 const id='a'.repeat(64),p=createNoHistoryProbe(id);
 assert.equal(p.result().status,'insufficient');p.record(id+':one');assert.equal(p.result().status,'one-entry');
 p.record(id+':one');assert.equal(p.result().status,'insufficient');
 const q=createNoHistoryProbe(id);q.record('b'.repeat(64)+':one');assert.equal(q.result().status,'insufficient');
 const r=createNoHistoryProbe(id);r.record(id+':other');assert.equal(r.result().status,'insufficient');
});
