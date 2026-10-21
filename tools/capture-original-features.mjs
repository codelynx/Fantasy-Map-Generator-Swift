// Runs the ORIGINAL's own `Features.markupGrid()` (features of the grid: ocean, lake and island, and the coast-distance
// field) on heightmaps made by the original's own `HeightmapGenerator.generate`, and saves what it produces. Usage:
//   node tools/capture-original-features.mjs <bundle.mjs> <out dir>
// For each map: the feature list, SHA-256 digests of the distance field (Int8 bytes) and of the feature ids (Uint16,
// written explicitly little-endian), counts, and, for a few maps, the complete arrays.
import { createHash } from "node:crypto";
import { writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const [bundlePath, outDir] = process.argv.slice(2);
if (!bundlePath || !outDir) throw new Error("usage: capture-original-features.mjs <bundle.mjs> <out dir>");

globalThis.window = globalThis;
globalThis.TIME = false;
globalThis.document = { readyState: "loading", addEventListener() {}, documentElement: {} };
globalThis.options = { map: { seed: "", graph: { width: 1280, height: 800, points: 10000 } }, generation: {} };
await import(pathToFileURL(resolve(bundlePath)).href);

const keys = Object.keys(globalThis.__heightmapTemplates);
const sha = bytes => createHash("sha256").update(bytes).digest("hex");

async function capture(seed, width, height, cellsDesired, key, full) {
	globalThis.options.map.seed = seed;
	globalThis.options.map.graph = { width, height, points: cellsDesired };
	const graph = globalThis.Grid.generate(seed, width, height, cellsDesired);
	const heights = await globalThis.HeightmapGenerator.generate(graph, key); // also stores them on graph.cells.h
	globalThis.grid = graph; // markupGrid reads the global `grid`
	globalThis.Features.markupGrid();
	const t = Array.from(graph.cells.t);
	const f = Array.from(graph.cells.f);
	const features = graph.features.slice(1).map(x => ({ i: x.i, land: x.land, border: x.border, type: x.type }));
	const entry = {
		key, cells: heights.length, heightsSha256: sha(Buffer.from(heights)),
		distanceSha256: (() => { // signed bytes, one per cell
			const bytes = Buffer.alloc(t.length);
			t.forEach((v, i) => bytes.writeInt8(v, i));
			return sha(bytes);
		})(),
		featureIdsSha256: (() => { // explicitly little-endian, whatever the machine's own byte order
			const bytes = Buffer.alloc(f.length * 2);
			f.forEach((id, i) => bytes.writeUInt16LE(id, i * 2));
			return sha(bytes);
		})(),
		featureCount: features.length, features,
		distanceValues: [...new Set(t)].sort((a, b) => a - b)
	};
	if (full) { entry.heights = Array.from(heights); entry.distance = t; entry.featureIds = f; }
	return entry;
}

const runs = [];
for (const [seed, width, height, cellsDesired, full] of [["kaz-1", 1280, 800, 10000, ["highIsland", "archipelago"]], ["", 1280, 800, 1000, []], ["日本語", 1280, 800, 2000, ["shattered"]], ["wide", 1000, 90, 300, ["lowIsland"]], ["tiny", 100, 60, 24, keys]]) {
	const results = [];
	for (const key of keys) results.push(await capture(seed, width, height, cellsDesired, key, full.includes(key)));
	runs.push({ seed, width, height, cellsDesired, results });
}
writeFileSync(join(outDir, "features-original.json"), JSON.stringify({
	note: "Produced by running the original's own Features.markupGrid on heightmaps from its own HeightmapGenerator.generate; see tools/capture-original-features.mjs",
	runs
}));
console.log("wrote", outDir, runs.map(r => [r.seed, r.cellsDesired, r.results.map(x => x.featureCount).join(",")]));
