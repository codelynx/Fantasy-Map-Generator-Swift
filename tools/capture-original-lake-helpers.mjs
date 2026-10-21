// Runs the ORIGINAL's own lake helpers (`Lakes.detectCloseLakes`, `Lakes.defineClimateData`, `Lakes.cleanupLakeData`, src/generators/lakes.ts;
// bundled as described in tools/original-bundle/README.md) on the original's own packed graph, after its own chain: Grid.generate,
// HeightmapGenerator.generate, Features.markupGrid, the two lake steps, Coordinates.generate, Temperature.generate, Precipitation.generate,
// Pack.generate and Features.markupPack. Usage:
//   node tools/capture-original-lake-helpers.mjs <bundle.mjs> <out dir>
// For every map it runs the helpers on the packed heights, on a raised copy (every land cell 15 higher, at most 100) and on two fractional working copies (as the river generator's), with the lake
// elevation limits 0, 5, 20, 60 and 90, and records per lake what `detectCloseLakes` decided; after the limit-20 pass of each it runs
// `defineClimateData` with the height exponents 2 and 1.5 and records the lakes' flux, temperature, evaporation and outlet cell and the
// out-cell list; finally it gives each lake synthetic river fields and records what `cleanupLakeData` keeps.
import { createHash } from "node:crypto";
import { writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const [bundlePath, outDir] = process.argv.slice(2);
if (!bundlePath || !outDir) throw new Error("usage: capture-original-lake-helpers.mjs <bundle.mjs> <out dir>");

globalThis.window = globalThis;
globalThis.TIME = false;
globalThis.DEBUG = {};
globalThis.document = { readyState: "loading", addEventListener() {}, documentElement: {} };
globalThis.options = { map: { seed: "", graph: { width: 1280, height: 800, points: 10000 } }, generation: {} };
await import(pathToFileURL(resolve(bundlePath)).href);
const keys = Object.keys(globalThis.__heightmapTemplates);
// explicitly little-endian, as the Swift side writes it
const sha16 = values => { const b = Buffer.alloc(values.length * 2); values.forEach((v, i) => b.writeUInt16LE(v, i * 2)); return createHash("sha256").update(b).digest("hex"); };
const defaultGeography = () => ({ mapSize: 100, latitude: 50, longitude: 50, coordinates: { latT: 180, latN: 90, latS: -90, lonT: 320, lonW: -160, lonE: 160 } });

const lakes = () => globalThis.pack.features.filter(f => f && f.type === "lake");
const pick = (f, names) => Object.fromEntries(names.map(n => [n, f[n] === undefined ? null : f[n]]));

async function capture(seed, width, height, cellsDesired, key) {
	globalThis.options.map = {
		seed, graph: { width, height, points: cellsDesired }, geography: defaultGeography(),
		climate: { temperature: { equator: 27, northPole: -30, southPole: -15 }, precipitation: 100, winds: [225, 45, 225, 315, 135, 315] },
		units: { height: { exponent: 2 } }
	};
	globalThis.options.generation = { lakeElevationLimit: 20, template: key, geography: { mapSize: null, latitude: null, longitude: null } };
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
	const entry = { seed, width, height, cellsDesired, key, coordinates: globalThis.options.map.geography.coordinates, lakes: lakes().length, variants: [] };
	if (!entry.lakes) return entry;
	const base = globalThis.pack.cells.h;
	const raised = Uint8Array.from(base, v => (v >= 20 ? Math.min(100, v + 15) : v));
	// the river generator's working copy is a plain list of fractional heights: a small gradient on every cell, and a lowering of the land
	// cells by up to 0.8 (never under 20.05), which move cells across the flood threshold and change which shore cell is lowest
	const fracA = Array.from(base, (v, i) => v + (i % 7) * 0.15);
	const fracB = Array.from(base, (v, i) => (v >= 21 ? Math.max(20.05, v - (i % 5) * 0.2) : v));
	for (const [heightsName, h] of [["same", base], ["raised", raised], ["fracA", fracA], ["fracB", fracB]]) {
		for (const limit of [0, 5, 20, 60, 90]) {
			globalThis.options.generation.lakeElevationLimit = limit;
			globalThis.Lakes.detectCloseLakes(h);
			const variant = { heights: heightsName, limit, closed: lakes().map(f => (f.closed === undefined ? null : f.closed)) };
			if (limit === 20) {
				variant.climate = [];
				for (const exponent of [2, 1.5]) {
					globalThis.options.map.units.height.exponent = exponent;
					const outCells = globalThis.Lakes.defineClimateData(h);
					variant.climate.push({ exponent, lakes: lakes().map(f => pick(f, ["i", "flux", "temp", "evaporation", "outCell", "closed"])), outCellsSha: sha16(outCells), outCellsCount: outCells.filter(Boolean).length });
				}
				globalThis.options.map.units.height.exponent = 2;
			}
			entry.variants.push(variant);
		}
	}
	// cleanup: synthetic river fields on every lake, and a river list with ids 1, 3 and 0
	lakes().forEach((f, n) => {
		f.river = 7; f.enteringFlux = 9; f.outCell = 5; f.closed = n % 2 === 0;
		f.inlets = [1, 2, 3, 0].slice(0, n % 5);
		f.outlet = [0, 1, 2, 3, 5][n % 5];
		f.height += 0.12345;
	});
	const before = lakes().map(f => ({ inlets: f.inlets, outlet: f.outlet, height: f.height }));
	globalThis.pack.rivers = [{ i: 1 }, { i: 3 }, { i: 0 }];
	globalThis.Lakes.cleanupLakeData();
	entry.cleanup = {
		rivers: [1, 3, 0], before,
		after: lakes().map(f => ({ ...pick(f, ["inlets", "outlet", "height"]), has: ["river", "enteringFlux", "outCell", "closed"].map(k => k in f) }))
	};
	return entry;
}

const configs = [
	["kaz-1", 1280, 800, 2000],
	["", 1280, 800, 1000],
	["日本語", 640, 400, 1000],
	["wide", 1000, 90, 300],
	["mid", 640, 400, 600],
	["big", 1280, 800, 10000]
];
const runs = [];
for (const [seed, width, height, cellsDesired] of configs) {
	for (const key of keys) runs.push(await capture(seed, width, height, cellsDesired, key));
}
writeFileSync(join(resolve(outDir), "lake-helpers-original.json"), JSON.stringify({
	about: "Captured from the original's own Lakes.detectCloseLakes, defineClimateData and cleanupLakeData (lakes.ts) on its own packed graph, by tools/capture-original-lake-helpers.mjs; see provenance.json.",
	runs
}));
const withLakes = runs.filter(r => r.lakes);
console.log(`lake helpers: ${runs.length} runs, ${withLakes.length} with lakes, ${withLakes.reduce((a, r) => a + r.lakes, 0)} lakes`);
