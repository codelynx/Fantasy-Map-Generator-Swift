// Runs the ORIGINAL's own `Pack.generate` (bundled as described in tools/original-bundle/README.md) after the original's own chain that
// precedes it in its pipeline: Grid.generate, HeightmapGenerator.generate, Features.markupGrid, Grid.addDeepDepressionLakes and
// Grid.openNearSeaLakes (the climate steps in between do not touch what the packed graph reads). Usage:
//   node tools/capture-original-pack.mjs <bundle.mjs> <out dir>
// For every run it saves the sizes of the packed graph and a sha256 of each of its arrays (binary: Float64 for points, Int32 for the rest) (the cell points, the parent grid cells, the
// heights, the areas, the cells' vertices, neighbours and border flags, and the vertices' points, neighbours and cells); small maps keep
// every array whole.
import { createHash } from "node:crypto";
import { writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const [bundlePath, outDir] = process.argv.slice(2);
if (!bundlePath || !outDir) throw new Error("usage: capture-original-pack.mjs <bundle.mjs> <out dir>");

globalThis.window = globalThis;
globalThis.TIME = false;
globalThis.DEBUG = {};
globalThis.document = { readyState: "loading", addEventListener() {}, documentElement: {} };
globalThis.options = { map: { seed: "", graph: { width: 1280, height: 800, points: 10000 } }, generation: {} };
await import(pathToFileURL(resolve(bundlePath)).href);
const keys = Object.keys(globalThis.__heightmapTemplates);
// binary hashes, so the Swift side can recompute them without formatting numbers: points as explicitly little-endian Float64 pairs, lists of lists
// as Int32 (the row's length, then its items), flat lists as Int32
// (written explicitly little-endian, not as the machine's typed-array storage)
const shaDoubles = values => { const b = Buffer.alloc(values.length * 8); values.forEach((v, i) => b.writeDoubleLE(v, i * 8)); return createHash("sha256").update(b).digest("hex"); };
const shaInt32s = values => { const b = Buffer.alloc(values.length * 4); values.forEach((v, i) => b.writeInt32LE(v, i * 4)); return createHash("sha256").update(b).digest("hex"); };
const shaPoints = points => shaDoubles(points.flat());
const shaRows = rows => shaInt32s(rows.flatMap(row => [row.length, ...row]));
const shaInts = values => shaInt32s(Array.from(values));

async function capture(seed, width, height, cellsDesired, key, full) {
	globalThis.options.map = { seed, graph: { width, height, points: cellsDesired }, units: { height: { exponent: 2 } } };
	globalThis.options.generation = { lakeElevationLimit: 20, template: key };
	const graph = globalThis.Grid.generate(seed, width, height, cellsDesired);
	await globalThis.HeightmapGenerator.generate(graph, key);
	globalThis.grid = graph;
	globalThis.Features.markupGrid();
	globalThis.Grid.addDeepDepressionLakes();
	globalThis.Grid.openNearSeaLakes();
	globalThis.pack = {};
	globalThis.Pack.generate();
	const { cells, vertices } = globalThis.pack;
	const entry = {
		seed, width, height, cellsDesired, key, gridCells: graph.cells.i.length, cells: cells.i.length, vertices: vertices.p.length,
		maxArea: Math.max(...cells.area),
		sha: {
			p: shaPoints(cells.p), g: shaInts(cells.g), h: shaInts(cells.h), area: shaInts(cells.area),
			v: shaRows(cells.v), c: shaRows(cells.c), b: shaInts(cells.b), vp: shaPoints(vertices.p), vv: shaRows(vertices.v), vc: shaRows(vertices.c)
		}
	};
	if (full) entry.whole = { p: cells.p, g: Array.from(cells.g), h: Array.from(cells.h), area: Array.from(cells.area), v: cells.v, c: cells.c, b: cells.b, vp: vertices.p, vv: vertices.v, vc: vertices.c };
	return entry;
}

const configs = [
	["kaz-1", 1280, 800, 2000],
	["", 1280, 800, 1000],
	["日本語", 640, 400, 1000],
	["wide", 1000, 90, 300],
	["tiny", 100, 60, 24],
	["mid", 640, 400, 600],
	["big", 1280, 800, 10000]
];
const runs = [];
for (const [seed, width, height, cellsDesired] of configs) {
	for (const key of keys) runs.push(await capture(seed, width, height, cellsDesired, key, cellsDesired <= 300));
}
writeFileSync(join(resolve(outDir), "pack-original.json"), JSON.stringify({
	about: "Captured from the original's own Pack.generate (pack-generator.ts) after its own grid, heightmap, markupGrid and lake steps, by tools/capture-original-pack.mjs; see provenance.json. whole holds every array of the packed graph for the small maps.",
	runs
}));
console.log(`pack: ${runs.length} runs, ${runs.filter(r => r.whole).length} with whole arrays`);
