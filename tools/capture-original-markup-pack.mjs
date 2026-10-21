// Runs the ORIGINAL's own `Features.markupPack` (bundled as described in tools/original-bundle/README.md) after the original's own chain
// that precedes it: Grid.generate, HeightmapGenerator.generate, Features.markupGrid, Grid.addDeepDepressionLakes, Grid.openNearSeaLakes and
// Pack.generate. Usage:
//   node tools/capture-original-markup-pack.mjs <bundle.mjs> <out dir>
// For every run it saves the sizes, a sha256 of the packed cells' coast distance, feature numbers, havens and harbours (explicitly
// little-endian Int32), and every feature record: its scalar fields, a sha256 of its vertex ring and shoreline, and (small maps) both lists.
import { createHash } from "node:crypto";
import { writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const [bundlePath, outDir] = process.argv.slice(2);
if (!bundlePath || !outDir) throw new Error("usage: capture-original-markup-pack.mjs <bundle.mjs> <out dir>");

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
	globalThis.Features.markupPack();
	const { cells } = globalThis.pack;
	const empty = cells.t === undefined;
	const entry = { seed, width, height, cellsDesired, key, cells: cells.i.length, empty };
	if (empty) return entry;
	const features = globalThis.pack.features.slice(1).map(f => {
		const r = {
			i: f.i, type: f.type, land: f.land, border: f.border, cells: f.cells, firstCell: f.firstCell, area: f.area, height: f.height,
			vertices: f.vertices.length, shoreline: f.shoreline.length, verticesSha: shaInts(f.vertices), shorelineSha: shaInts(f.shoreline)
		};
		if (full) { r.verticesWhole = f.vertices; r.shorelineWhole = f.shoreline; }
		return r;
	});
	Object.assign(entry, {
		sha: { t: shaInts(cells.t), f: shaInts(cells.f), haven: shaInts(cells.haven), harbor: shaInts(cells.harbor) },
		maxHarbor: Math.max(...cells.harbor), features
	});
	if (full) entry.whole = { t: Array.from(cells.t), f: Array.from(cells.f), haven: Array.from(cells.haven), harbor: Array.from(cells.harbor) };
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
writeFileSync(join(resolve(outDir), "markup-pack-original.json"), JSON.stringify({
	about: "Captured from the original's own Features.markupPack (features-generator.ts) after its own grid, heightmap, markupGrid, lake and Pack.generate steps, by tools/capture-original-markup-pack.mjs; see provenance.json. whole holds the four cell arrays and the features keep their vertex rings and shorelines whole, for the small maps.",
	runs
}));
console.log(`markupPack: ${runs.length} runs, ${runs.filter(r => r.whole).length} with whole arrays`);
