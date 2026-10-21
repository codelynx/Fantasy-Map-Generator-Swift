// Runs the ORIGINAL's own lake routines (`Grid.findDeepDepressionLakes`, `Grid.addDeepDepressionLakes` and
// `Grid.openNearSeaLakes`) after `Features.markupGrid()` on heightmaps from its own `HeightmapGenerator.generate`, and
// saves what each step leaves: digests of the heights, the coast-distance field and the feature ids (bytes written
// explicitly: heights and distances one byte per cell, ids as little-endian 16-bit numbers) and the feature list.
//   node tools/capture-original-lakes.mjs <bundle.mjs> <out dir>
// Settings varied: the lake elevation limit (including 80, which switches depression lakes off) and the template option
// (the original returns early from `openNearSeaLakes` only if it equals the string "Atoll", which is not a template key).
import { createHash } from "node:crypto";
import { writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const [bundlePath, outDir] = process.argv.slice(2);
if (!bundlePath || !outDir) throw new Error("usage: capture-original-lakes.mjs <bundle.mjs> <out dir>");

globalThis.window = globalThis;
globalThis.TIME = false;
globalThis.document = { readyState: "loading", addEventListener() {}, documentElement: {} };
globalThis.options = { map: { seed: "", graph: { width: 1280, height: 800, points: 10000 } }, generation: {} };
await import(pathToFileURL(resolve(bundlePath)).href);

const keys = Object.keys(globalThis.__heightmapTemplates);
const sha = bytes => createHash("sha256").update(bytes).digest("hex");
const bytes8 = (array, signed) => { const b = Buffer.alloc(array.length); array.forEach((v, i) => signed ? b.writeInt8(v, i) : b.writeUInt8(v, i)); return b; };
const bytes16 = array => { const b = Buffer.alloc(array.length * 2); array.forEach((v, i) => b.writeUInt16LE(v, i * 2)); return b; };

function snapshot(graph) {
	return {
		heightsSha256: sha(bytes8(graph.cells.h, false)),
		distanceSha256: sha(bytes8(graph.cells.t, true)),
		featureIdsSha256: sha(bytes16(graph.cells.f)),
		features: graph.features.slice(1).map(x => ({ i: x.i, land: x.land, border: x.border, type: x.type })),
		land: graph.cells.h.reduce((n, h) => n + (h >= 20 ? 1 : 0), 0)
	};
}

async function capture(seed, width, height, cellsDesired, key, limit, templateOption, full) {
	globalThis.options.map.seed = seed;
	globalThis.options.map.graph = { width, height, points: cellsDesired };
	globalThis.options.generation = { lakeElevationLimit: limit, template: templateOption };
	const graph = globalThis.Grid.generate(seed, width, height, cellsDesired);
	await globalThis.HeightmapGenerator.generate(graph, key);
	globalThis.grid = graph;
	globalThis.Features.markupGrid();
	const before = snapshot(graph);
	const found = globalThis.Grid.findDeepDepressionLakes(graph.cells, limit).map(cells => Array.from(cells));
	globalThis.Grid.addDeepDepressionLakes();
	const afterDepressions = snapshot(graph);
	globalThis.Grid.openNearSeaLakes();
	const afterOpening = snapshot(graph);
	const entry = { key, limit, templateOption, before, lakesFound: found, afterDepressions, afterOpening };
	if (full) {
		entry.heights = Array.from(graph.cells.h);
		entry.distance = Array.from(graph.cells.t);
		entry.featureIds = Array.from(graph.cells.f);
	}
	return entry;
}

const runs = [];
const configs = [
	["kaz-1", 1280, 800, 10000],
	["", 1280, 800, 1000],
	["日本語", 1280, 800, 2000],
	["wide", 1000, 90, 300],
	["tiny", 100, 60, 24],
	["mid", 640, 400, 1000]
];
for (const [seed, width, height, cellsDesired] of configs) {
	const results = [];
	for (const key of keys) {
		for (const [limit, templateOption] of [[20, key], [5, key], [35, key], [80, key], [0, key]]) {
			results.push(await capture(seed, width, height, cellsDesired, key, limit, templateOption, false));
		}
	}
	runs.push({ seed, width, height, cellsDesired, results });
}
// the original's "Atoll" early return: only the exact string "Atoll" matches, and no template key does
const atoll = [];
for (const [seed, width, height, cellsDesired] of configs.slice(0, 4)) {
	for (const key of ["atoll", "highIsland", "shattered"]) {
		atoll.push({ seed, width, height, cellsDesired, ...await capture(seed, width, height, cellsDesired, key, 35, "Atoll", true) });
	}
}
// maps with full arrays, for cell-for-cell diagnosis
const fulls = [];
for (const [seed, width, height, cellsDesired, key, limit] of [["tiny", 100, 60, 24, "highIsland", 20], ["mid", 640, 400, 1000, "shattered", 35]]) {
	fulls.push({ seed, width, height, cellsDesired, ...await capture(seed, width, height, cellsDesired, key, limit, key, true) });
}
writeFileSync(join(outDir, "lakes-original.json"), JSON.stringify({
	note: "Produced by running the original's own lake routines after markupGrid; see tools/capture-original-lakes.mjs",
	runs, atoll, fulls
}));
const stats = { maps: 0, withDepressionLakes: 0, withOpenedLakes: 0 };
for (const r of runs) for (const e of r.results) {
	stats.maps++;
	if (e.afterDepressions.features.length > e.before.features.length) stats.withDepressionLakes++;
	if (JSON.stringify(e.afterOpening.features) !== JSON.stringify(e.afterDepressions.features)) stats.withOpenedLakes++;
}
console.log("wrote", outDir, stats);
