// Runs the ORIGINAL's own `Rivers.alterHeights` and `Rivers.resolveDepressions` (src/generators/river-generator.ts; bundled as described in
// tools/original-bundle/README.md) on the original's own packed graph, after its own chain: Grid.generate, HeightmapGenerator.generate,
// Features.markupGrid, the two lake steps, Coordinates.generate, Temperature.generate, Precipitation.generate, Pack.generate and
// Features.markupPack. Usage:
//   node tools/capture-original-depressions.mjs <bundle.mjs> <out dir>
// For every map it records `alterHeights()` (a sha256 of the Float64 values, explicitly little-endian), then for four working-height
// variants (made here, listed below) and the depression step counts 250, 40 and 5 it runs `Lakes.detectCloseLakes(h)` with the limit 20 and
// `resolveDepressions(h)` and records the resulting heights, every lake's height and closed flag, and whether the bad-progress branch (which
// reassigns the function's parameter and is the only place the original calls `alterHeights` from inside `resolveDepressions`) was
// reached, found by wrapping the loaded object's `alterHeights` at run time (the clone is not edited).
import { createHash } from "node:crypto";
import { writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const [bundlePath, outDir] = process.argv.slice(2);
if (!bundlePath || !outDir) throw new Error("usage: capture-original-depressions.mjs <bundle.mjs> <out dir>");

globalThis.window = globalThis;
globalThis.TIME = false;
globalThis.DEBUG = {};
globalThis.WARN = false;
globalThis.document = { readyState: "loading", addEventListener() {}, documentElement: {} };
globalThis.options = { map: { seed: "", graph: { width: 1280, height: 800, points: 10000 } }, generation: {} };
await import(pathToFileURL(resolve(bundlePath)).href);
const keys = Object.keys(globalThis.__heightmapTemplates);
// explicitly little-endian, as the Swift side writes it
const shaDoubles = values => { const b = Buffer.alloc(values.length * 8); values.forEach((v, i) => b.writeDoubleLE(v, i * 8)); return createHash("sha256").update(b).digest("hex"); };
const defaultGeography = () => ({ mapSize: 100, latitude: 50, longitude: 50, coordinates: { latT: 180, latN: 90, latS: -90, lonT: 320, lonW: -160, lonE: 160 } });

async function build(seed, width, height, cellsDesired, key) {
	globalThis.options.map = {
		seed, graph: { width, height, points: cellsDesired }, geography: defaultGeography(),
		climate: { temperature: { equator: 27, northPole: -30, southPole: -15 }, precipitation: 100, winds: [225, 45, 225, 315, 135, 315] },
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

const Rivers = globalThis.Rivers;
const alterHeights = Rivers.alterHeights.bind(Rivers);
let alterCalls = 0;
Rivers.alterHeights = function () { alterCalls++; return alterHeights(); };

// working-height variants, each a pure function of the index and the value (the Swift tests make the same)
const variants = {
	natural: h => h,
	pits: h => h.map((v, i) => (v >= 20 && i % 3 === 0 ? Math.max(20, v - 12) : v)),
	ridges: h => h.map((v, i) => (v >= 20 && i % 5 === 0 ? Math.min(100, v + 30) : v)),
	noise: h => h.map((v, i) => (v >= 20 ? Math.min(100, Math.max(20, v + ((i * 7919) % 21) - 10)) : v))
};

const configs = [
	["kaz-1", 1280, 800, 2000],
	["", 1280, 800, 1000],
	["日本語", 640, 400, 1000],
	["mid", 640, 400, 600],
	["wide", 1000, 90, 300],
	["big", 1280, 800, 10000]
];
const runs = [];
let whole = 0;
for (const [seed, width, height, cellsDesired] of configs) {
	for (const key of keys) {
		await build(seed, width, height, cellsDesired, key);
		const saved = structuredClone(globalThis.pack.features);
		const base = alterHeights();
		const run = { seed, width, height, cellsDesired, key, cells: base.length, lakes: saved.filter(f => f && f.type === "lake").length, alterSha: shaDoubles(base), cases: [] };
		if (base.length <= 700 && run.lakes > 0) run.alterWhole = base;
		for (const [variantName, make] of Object.entries(variants)) {
			for (const steps of [250, 40, 5]) {
				globalThis.pack.features = structuredClone(saved);
				globalThis.options.generation.resolveDepressionsSteps = steps;
				const h = make(alterHeights());
				globalThis.Lakes.detectCloseLakes(h);
				const closedBefore = globalThis.pack.features.filter(f => f && f.type === "lake").map(f => f.closed);
				alterCalls = 0;
				Rivers.resolveDepressions(h);
				const lakes = globalThis.pack.features.filter(f => f && f.type === "lake").map(f => ({ height: f.height, closed: f.closed }));
				const entry = { variant: variantName, steps, bad: alterCalls > 0, hSha: shaDoubles(h), closedBefore, lakes };
				const interesting = entry.bad || lakes.some((l, k) => l.closed && !closedBefore[k]);
				if (base.length <= 700 && (interesting || (variantName === "natural" && steps === 250)) && whole < 120) { entry.hWhole = h; whole++; }
				run.cases.push(entry);
			}
		}
		globalThis.pack.features = saved;
		runs.push(run);
	}
}
writeFileSync(join(resolve(outDir), "depressions-original.json"), JSON.stringify({
	about: "Captured from the original's own Rivers.alterHeights and Rivers.resolveDepressions (river-generator.ts) on its own packed graph, by tools/capture-original-depressions.mjs; see provenance.json.",
	runs
}));
const cases = runs.flatMap(r => r.cases);
console.log(`depressions: ${runs.length} maps, ${cases.length} cases, ${cases.filter(c => c.bad).length} reach the bad-progress branch, ${cases.filter(c => c.lakes.some((l, k) => l.closed && !c.closedBefore[k])).length} close a lake by force, ${cases.filter(c => c.hWhole).length} whole`);
