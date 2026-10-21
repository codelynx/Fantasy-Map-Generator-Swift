// Runs the ORIGINAL's own `Rivers.generate` (src/generators/river-generator.ts; bundled as described in tools/original-bundle/README.md) on the
// original's own packed graph, after its own chain: Grid.generate, HeightmapGenerator.generate, Features.markupGrid, the two lake steps,
// Coordinates.generate, Temperature.generate, Precipitation.generate, Pack.generate and Features.markupPack. Usage:
//   node tools/capture-original-rivers.mjs <bundle.mjs> <out dir>
// The drainage, the flow and the river definition are closures inside `generate`, so only the END STATE can be observed, and that is what is
// recorded: the flux, river and confluence arrays and the heights (as sha256 of the exact values, explicitly little-endian; whole for small
// maps), every river record (as one sha256 of its numbers and ids, and one of all the cell lists; whole for small maps), every lake's fields after the cleanup, and the
// next value of the random stream. Run for each map with `allowErosion` true and false, at two rain levels, and with other depression steps and
// lake elevation limits.
import { createHash } from "node:crypto";
import { writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const [bundlePath, outDir] = process.argv.slice(2);
if (!bundlePath || !outDir) throw new Error("usage: capture-original-rivers.mjs <bundle.mjs> <out dir>");

globalThis.window = globalThis;
globalThis.TIME = false;
globalThis.DEBUG = {};
globalThis.WARN = false;
globalThis.document = { readyState: "loading", addEventListener() {}, documentElement: {} };
globalThis.options = { map: { seed: "", graph: { width: 1280, height: 800, points: 10000 } }, generation: {} };
await import(pathToFileURL(resolve(bundlePath)).href);
const keys = Object.keys(globalThis.__heightmapTemplates);
const shaBuffer = b => createHash("sha256").update(b).digest("hex");
const sha16 = values => { const b = Buffer.alloc(values.length * 2); Array.from(values).forEach((v, i) => b.writeUInt16LE(v, i * 2)); return shaBuffer(b); };
const sha8 = values => shaBuffer(Buffer.from(Uint8Array.from(values)));
const sha32 = values => { const b = Buffer.alloc(values.length * 4); Array.from(values).forEach((v, i) => b.writeInt32LE(v, i * 4)); return shaBuffer(b); };
// the river records as one hash: per river the integers (id, source, mouth, parent) as little-endian Int32 and the five numbers (discharge, length, width,
// width factor, source width) as little-endian Float64; the cell lists are hashed apart (each preceded by its length)
const shaRivers = rivers => {
	const b = Buffer.alloc(rivers.length * (4 * 4 + 5 * 8));
	rivers.forEach((r, k) => {
		let at = k * 56;
		for (const v of [r.i, r.source, r.mouth, r.parent]) { b.writeInt32LE(v, at); at += 4; }
		for (const v of [r.discharge, r.length, r.width, r.widthFactor, r.sourceWidth]) { b.writeDoubleLE(v, at); at += 8; }
	});
	return shaBuffer(b);
};
const defaultGeography = () => ({ mapSize: 100, latitude: 50, longitude: 50, coordinates: { latT: 180, latN: 90, latS: -90, lonT: 320, lonW: -160, lonE: 160 } });

async function build(seed, width, height, cellsDesired, key, rain) {
	globalThis.options.map = {
		seed, graph: { width, height, points: cellsDesired }, geography: defaultGeography(),
		climate: { temperature: { equator: 27, northPole: -30, southPole: -15 }, precipitation: rain, winds: [225, 45, 225, 315, 135, 315] },
		units: { height: { exponent: 2 } }
	};
	globalThis.options.generation = { lakeElevationLimit: 20, resolveDepressionsSteps: 250, template: key, geography: { mapSize: null, latitude: null, longitude: null } };
	const graph = globalThis.Grid.generate(seed, width, height, cellsDesired);
	await globalThis.HeightmapGenerator.generate(graph, key);
	globalThis.grid = graph;
	globalThis.Features.markupGrid();
	globalThis.Grid.addDeepDepressionLakes();
	globalThis.Grid.openNearSeaLakes();
	globalThis.Coordinates.generate();
	globalThis.Temperature.generate();
	globalThis.Precipitation.generate();
	globalThis.pack = {};
	globalThis.Pack.generate();
	globalThis.Features.markupPack();
}

const variants = [
	{ rain: 100, steps: 250, limit: 20, erosion: true },
	{ rain: 100, steps: 250, limit: 20, erosion: false },
	{ rain: 300, steps: 250, limit: 20, erosion: true },
	{ rain: 100, steps: 40, limit: 5, erosion: true }
];
const configs = [
	["kaz-1", 1280, 800, 2000],
	["", 1280, 800, 1000],
	["日本語", 640, 400, 1000],
	["mid", 640, 400, 600],
	["wide", 1000, 90, 300],
	["big", 1280, 800, 10000]
];
const runs = [];
let mouthMinusOne = 0, whole = 0;
for (const [seed, width, height, cellsDesired] of configs) {
	for (const key of keys) {
		for (const rain of [100, 300]) {
			await build(seed, width, height, cellsDesired, key, rain);
			const saved = structuredClone(globalThis.pack);
			for (const v of variants.filter(x => x.rain === rain)) {
				globalThis.pack = structuredClone(saved);
				globalThis.options.generation.resolveDepressionsSteps = v.steps;
				globalThis.options.generation.lakeElevationLimit = v.limit;
				globalThis.Rivers.generate(v.erosion);
				const next = Math.random();
				const { cells, features, rivers } = globalThis.pack;
				const entry = {
					seed, width, height, cellsDesired, key, rain: v.rain, steps: v.steps, limit: v.limit, erosion: v.erosion, cells: cells.i.length, nextRandom: next,
					sha: { fl: sha16(cells.fl), r: sha16(cells.r), conf: sha16(cells.conf), h: sha8(cells.h) },
					maxFlux: Math.max(...cells.fl), riverCount: rivers.length, riversSha: shaRivers(rivers), riverCellsSha: sha32(rivers.flatMap(r => [r.cells.length, ...r.cells])),
					lakes: features.filter(f => f && f.type === "lake").map(f => ({
						i: f.i, height: f.height, flux: f.flux, temp: f.temp, evaporation: f.evaporation,
						inlets: f.inlets === undefined ? null : f.inlets, outlet: f.outlet === undefined ? null : f.outlet,
						leftover: ["river", "enteringFlux", "outCell", "closed"].filter(k => k in f)
					}))
				};
				mouthMinusOne += rivers.filter(r => r.mouth === -1 || r.source === -1).length;
				if (cells.i.length <= 700 && whole < 100) {
					entry.whole = { fl: Array.from(cells.fl), r: Array.from(cells.r), conf: Array.from(cells.conf), h: Array.from(cells.h), rivers: rivers.map(r => ({ i: r.i, source: r.source, mouth: r.mouth, discharge: r.discharge, length: r.length, width: r.width, widthFactor: r.widthFactor, sourceWidth: r.sourceWidth, parent: r.parent, cells: r.cells })) };
					whole++;
				}
				runs.push(entry);
			}
		}
	}
}
writeFileSync(join(resolve(outDir), "rivers-original.json"), JSON.stringify({
	about: "Captured from the original's own Rivers.generate (river-generator.ts) on its own packed graph, by tools/capture-original-rivers.mjs; see provenance.json. Only the end state of generate is observable.",
	runs
}));
const count = runs.reduce((a, r) => a + r.riverCount, 0);
console.log(`rivers: ${runs.length} runs, ${count} rivers, ${runs.filter(r => r.erosion).length} with erosion, max flux ${Math.max(...runs.map(r => r.maxFlux))}, ${mouthMinusOne} rivers with a border exit as source or mouth, ${whole} whole`);
