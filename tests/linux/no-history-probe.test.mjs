import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createNoHistoryProbe} from './no-history-probe.mjs';
test('requires one beacon with the exact run binding and one-entry result',()=>{
 const id='a'.repeat(64),p=createNoHistoryProbe(id);
 assert.deepEqual(p.result(),{status:'insufficient',beacon:'missing'});p.record(id+':one');assert.deepEqual(p.result(),{status:'one-entry',beacon:'one'});
 p.record(id+':one');assert.deepEqual(p.result(),{status:'insufficient',beacon:'duplicate'});
 const q=createNoHistoryProbe(id);q.record('b'.repeat(64)+':one');assert.deepEqual(q.result(),{status:'insufficient',beacon:'mismatch'});
 const r=createNoHistoryProbe(id);r.record(id+':other');assert.deepEqual(r.result(),{status:'insufficient',beacon:'other'});
});
