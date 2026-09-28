// Layer rules for TypeScript (dependency-cruiser). Save as
// .dependency-cruiser.cjs at the repo root. Rule comments are shown to the
// agent when a rule breaks, so write them as the fix instruction. Approve
// existing breaks with a baseline instead of loosening a rule:
//   npx depcruise --output-type baseline src > .dependency-cruiser-known-violations.json
/** @type {import('dependency-cruiser').IConfiguration} */
module.exports = {
  forbidden: [
    {
      name: "no-feature-internals",
      comment:
        "Import another feature only through its index.ts. Fix: export what you need from src/features/<name>/index.ts, or move shared code into src/shared/. See docs/architecture.md#features",
      severity: "error",
      from: { path: "^src/features/([^/]+)/" },
      to: {
        path: "^src/features/[^/]+/",
        pathNot: ["^src/features/$1/", "^src/features/[^/]+/index\\.tsx?$"],
      },
    },
    {
      name: "shared-stays-generic",
      comment:
        "src/shared must not depend on a feature. Fix: move the code into the feature, or pass the feature-specific part in as an argument.",
      severity: "error",
      from: { path: "^src/shared/" },
      to: { path: "^src/features/" },
    },
    {
      name: "no-circular",
      comment: "Circular import. Fix: extract the shared piece into a module both can import.",
      severity: "error",
      from: {},
      to: { circular: true },
    },
  ],
  options: {
    doNotFollow: { path: "node_modules" },
    tsPreCompilationDeps: true,
    tsConfig: { fileName: "tsconfig.json" },
  },
};
