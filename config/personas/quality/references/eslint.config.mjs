// Quality gates for TypeScript/JavaScript — spread `quality` into the
// project's flat config (eslint.config.mjs). The turn-end hook and CI run:
// eslint, tsc --noEmit, depcruise, and the related tests.
//
//   import quality from "./eslint.quality.mjs";
//   export default [...existing, ...quality];

export default [
  {
    files: ["**/*.{ts,tsx,js,jsx,mjs,cjs}"],
    rules: {
      complexity: ["error", 10],
      "max-depth": ["error", 3],
      "max-params": ["error", 4],
      "max-lines-per-function": ["error", { max: 60, skipBlankLines: true, skipComments: true }],
      "max-lines": ["error", { max: 500, skipBlankLines: true, skipComments: true }],
    },
  },
  {
    // Test files are long tables of cases; keep complexity, relax size.
    files: ["**/*.{test,spec}.{ts,tsx,js,jsx}", "**/__tests__/**"],
    rules: {
      "max-lines-per-function": "off",
      "max-lines": "off",
    },
  },
];
