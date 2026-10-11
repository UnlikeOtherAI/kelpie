import { defineConfig } from "tsup";

export default defineConfig({
  entry: { index: "src/index.ts", auth: "src/auth/index.ts" },
  format: ["esm"],
  target: "node20",
  dts: true,
  clean: true,
  sourcemap: true,
  noExternal: ["@unlikeotherai/kelpie-shared"],
});
