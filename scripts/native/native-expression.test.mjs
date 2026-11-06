import assert from "node:assert/strict";
import test from "node:test";
import vm from "node:vm";
import ts from "../../packages/shared/node_modules/typescript/lib/typescript.js";
import { fixedObservationReaderSource } from "../../packages/shared/dist/browser-control/observation-source.js";
import { rememberNativeSnapshot, resolveNativeReference, actOnNativeReference } from "../../packages/shared/dist/browser-control/native-reference.js";
import { resolveScriptTarget } from "../../packages/shared/dist/script-target.js";
import { lowerNativeExpression } from "./native-expression.mjs";

const families = {
  readiness_reader: fixedObservationReaderSource("ready"),
  status_reader: fixedObservationReaderSource("status"),
  extractor: fixedObservationReaderSource("extract"),
  reader: fixedObservationReaderSource("snapshot"),
  script_target: resolveScriptTarget.toString(),
  remember: rememberNativeSnapshot.toString(),
  resolve: resolveNativeReference.toString(),
  action: actOnNativeReference.toString(),
};

function forbiddenSyntax(source) {
  const file = ts.createSourceFile("native.js", "(" + source + ")", ts.ScriptTarget.ES2019, true, ts.ScriptKind.JS);
  assert.equal(file.parseDiagnostics.length, 0);
  const found = [];
  function visit(node) {
    if (node.questionDotToken || node.kind === ts.SyntaxKind.QuestionQuestionToken ||
        node.kind === ts.SyntaxKind.QuestionQuestionEqualsToken ||
        node.kind === ts.SyntaxKind.BarBarEqualsToken || node.kind === ts.SyntaxKind.AmpersandAmpersandEqualsToken) {
      found.push(node.kind);
    }
    ts.forEachChild(node, visit);
  }
  visit(file);
  return found;
}

function evaluate(source, invocation) {
  const document = { readyState: "complete" };
  const window = { addEventListener() {}, removeEventListener() {} };
  const context = { document, window, location: { href: "https://fixture.invalid/" } };
  return JSON.stringify(vm.runInNewContext("(" + source + ")" + invocation, context));
}

test("all native expression families lower to ES2019 without changing public source", () => {
  assert.ok(forbiddenSyntax(families.readiness_reader).length > 0);
  assert.ok(forbiddenSyntax(families.script_target).length > 0);
  for (const [name, source] of Object.entries(families)) {
    const lowered = lowerNativeExpression(source);
    assert.deepEqual(forbiddenSyntax(lowered), [], name);
    assert.equal(typeof vm.runInNewContext("(" + lowered + ")"), "function", name);
  }
});

test("lowering preserves false, zero, empty, null and undefined semantics", () => {
  const source = "(value) => ({ field: value?.field ?? 'fallback' })";
  const lowered = lowerNativeExpression(source);
  for (const value of [undefined, null, { field: false }, { field: 0 }, { field: "" }, { field: null }]) {
    const original = vm.runInNewContext("(" + source + ")")(value);
    const actual = vm.runInNewContext("(" + lowered + ")")(value);
    assert.deepEqual(JSON.parse(JSON.stringify(actual)), JSON.parse(JSON.stringify(original)));
  }
});

test("readiness, target and reference fixed responses remain equivalent", () => {
  const checks = [
    ["readiness_reader", '({state:"complete"})'],
    ["script_target", '({},"__test","missing",false,undefined,false,undefined,true,false)'],
    ["remember", '({targets:{},snapshot:{text:"fixture"}},"__test")'],
    ["resolve", '("missing","__test")'],
    ["action", '("missing","__test","tab.click","")'],
  ];
  for (const [name, invocation] of checks) {
    assert.equal(evaluate(lowerNativeExpression(families[name]), invocation), evaluate(families[name], invocation), name);
  }
});

test("malformed inputs fail closed", () => {
  assert.throws(() => lowerNativeExpression("function("), /NATIVE_EXPRESSION_/);
});
