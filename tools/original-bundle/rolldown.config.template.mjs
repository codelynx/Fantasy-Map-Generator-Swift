export default {
	input: "__SCRATCH__/entry.ts",
	platform: "node",
	output: { file: "__SCRATCH__/grid-bundle.mjs", format: "esm" },
	resolve: { alias: { "@/utils": "__SCRATCH__/utils-stub.ts", "@/types/GridGraph": "__SCRATCH__/utils-stub.ts", "@/types/global": "__SCRATCH__/utils-stub.ts" } },
	logLevel: "warn"
};
// __SCRATCH__/entry.ts contains one line: import "__CLONE__/src/generators/grid-generator.ts";
