import ts from "../../packages/shared/node_modules/typescript/lib/typescript.js";

/** Lower only native-embedded function expressions for the oldest supported WebView. */
export function lowerNativeExpression(source) {
  const emitted = ts.transpileModule("const __kelpie_native_expression = (" + source + ");", {
    compilerOptions: { target: ts.ScriptTarget.ES2019, module: ts.ModuleKind.None },
    fileName: "native-expression.js",
    reportDiagnostics: true,
  });
  const errors = (emitted.diagnostics ?? []).filter(item => item.category === ts.DiagnosticCategory.Error);
  if (errors.length) throw new Error("NATIVE_EXPRESSION_TRANSPILE_FAILED");
  const parsed = ts.createSourceFile("native-expression.js", emitted.outputText, ts.ScriptTarget.ES2019, true, ts.ScriptKind.JS);
  if (parsed.parseDiagnostics.length || parsed.statements.length !== 1 || !ts.isVariableStatement(parsed.statements[0])) {
    throw new Error("NATIVE_EXPRESSION_OUTPUT_INVALID");
  }
  const declarations = parsed.statements[0].declarationList.declarations;
  if (declarations.length !== 1 || declarations[0].name.getText(parsed) !== "__kelpie_native_expression" || !declarations[0].initializer) {
    throw new Error("NATIVE_EXPRESSION_OUTPUT_INVALID");
  }
  return declarations[0].initializer.getText(parsed);
}
