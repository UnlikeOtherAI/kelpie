import {test} from 'node:test';
import assert from 'node:assert/strict';
import {classifyListenerFailure} from './worker-listener-classifier.mjs';
test('maps only fixed ownership and errno categories',()=>{
 assert.equal(classifyListenerFailure(Error('ENGINE_LISTENER_NOT_OWNED')),'listener-not-owned');
 assert.equal(classifyListenerFailure(Error('ENGINE_IDENTITY_CHANGED')),'identity-changed');
 assert.equal(classifyListenerFailure({code:'EACCES',message:'private'}),'access-denied');
 assert.equal(classifyListenerFailure({code:'SECRET',message:'private'}),'other');
});
