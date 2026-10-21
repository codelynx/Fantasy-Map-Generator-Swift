// Runs the ORIGINAL's own `HeightmapGenerator.generate(graph, key)` for each of its fourteen templates (the whole path:
// the PRNG reset from the map's seed, the template's steps, the result stored on the graph) and saves what it returns,
// together with the original's own template table. Usage:
//   node tools/capture-original-templates.mjs <bundle.mjs> <out dir>
// For the default map every height is saved; for the other configurations a SHA-256 of the height bytes and a few counts.
import { createHash } from "node:crypto";
import { writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const [bundlePath, outDir] = process.argv.slice(2);
if (!bundlePath || !outDir) throw new Error("usage: capture-original-templates.mjs <bundle.mjs> <out dir>");

globalThis.window = globalThis;
globalThis.TIME = false;
globalThis.document = { readyState: "loading", addEventListener() {}, documentElement: {} };
globalThis.options = { map: { seed: "", graph: { width: 1280, height: 800, points: 10000 } }, generation: {} };
await import(pathToFileURL(resolve(bundlePath)).href);

const table = globalThis.__heightmapTemplates;
const keys = Object.keys(table);
if (keys.length !== 14) throw new Error("expected 14 templates");

async function capture(seed, width, height, cellsDesired, full) {
	const results = [];
	for (const key of keys) {
		globalThis.options.map.seed = seed;
		globalThis.options.map.graph = { width, height, points: cellsDesired };
		const graph = globalThis.Grid.generate(seed, width, height, cellsDesired);
		const heights = await globalThis.HeightmapGenerator.generate(graph, key);
		const bytes = Buffer.from(heights);
		const entry = {
			key,
			heightsSha256: createHash("sha256").update(bytes).digest("hex"),
			cells: heights.length,
			landCells: heights.filter(h => h >= 20).length,
			randomState: Math.random.exportState()
		};
		if (full) entry.heights = Array.from(heights);
		results.push(entry);
	}
	return { seed, width, height, cellsDesired, results };
}

const runs = [
	await capture("kaz-1", 1280, 800, 10000, true),
	await capture("", 1280, 800, 1000, false),
	await capture("日本語", 1280, 800, 2000, false),
	await capture("wide", 1000, 90, 300, false)
];
writeFileSync(join(outDir, "templates-original.json"), JSON.stringify({
	note: "Produced by running the original's own HeightmapGenerator.generate for each template; see tools/capture-original-templates.mjs",
	templates: keys.map(key => ({ key, ...table[key] })),
	runs
}));
console.log("wrote", outDir, runs.map(r => [r.seed, r.cellsDesired, r.results.map(x => x.landCells).join(",")]));
