// Runs the ORIGINAL's own `Rivers.generate` and then its river drawing geometry (`Rivers.addMeandering` and `Rivers.getRiverPath`, the polygon the
// original's draw-rivers.ts fills) on the
// original's own packed graph, after its own chain: Grid.generate, HeightmapGenerator.generate, Features.markupGrid, the two lake steps,
// Coordinates.generate, Temperature.generate, Precipitation.generate, Pack.generate and Features.markupPack. Usage:
//   node tools/capture-original-river-paths.mjs <bundle.mjs> <out dir>
// For some rivers of small maps it records the original's own meandered points (x, y and flux), the river's width factor and source width, and the
// SVG path string `getRiverPath` makes of them, so the Swift port of the path can be compared number for number from the SAME points.
import { writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const [bundlePath, outDir] = process.argv.slice(2);
if (!bundlePath || !outDir) throw new Error("usage: capture-original-river-paths.mjs <bundle.mjs> <out dir>");

globalThis.window = globalThis;
globalThis.TIME = false;
globalThis.DEBUG = {};
globalThis.WARN = false;
globalThis.document = { readyState: "loading", addEventListener() {}, documentElement: {} };
globalThis.options = { map: { seed: "", graph: { width: 1280, height: 800, points: 10000 } }, generation: {} };
await import(pathToFileURL(resolve(bundlePath)).href);
const keys = Object.keys(globalThis.__heightmapTemplates);
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


const configs = [["mid", 640, 400, 600], ["kaz-1", 1280, 800, 2000], ["wide", 1000, 90, 300]];
const chosenKeys = keys.slice(0, 6);
const rivers = [];
for (const [seed, width, height, cellsDesired] of configs) {
	for (const key of chosenKeys) {
		await build(seed, width, height, cellsDesired, key, 100);
		globalThis.options.generation.resolveDepressionsSteps = 250;
		globalThis.options.generation.lakeElevationLimit = 20;
		globalThis.Rivers.generate(true);
		// the longest rivers of the map, and the shortest that are kept: the first eight by length, and two short ones
		const sorted = [...globalThis.pack.rivers].sort((a, b) => b.cells.length - a.cells.length || a.i - b.i);
		for (const river of [...sorted.slice(0, 6), ...sorted.slice(-2)]) {
			const points = globalThis.Rivers.addMeandering(river.cells);
			const path = globalThis.Rivers.getRiverPath(points, river.widthFactor, river.sourceWidth);
			rivers.push({ seed, width, height, cellsDesired, key, river: river.i, cells: river.cells, widthFactor: river.widthFactor, sourceWidth: river.sourceWidth, points, path });
		}
	}
}
writeFileSync(join(resolve(outDir), "river-paths-original.json"), JSON.stringify({
	about: "Captured from the original's own Rivers.addMeandering and Rivers.getRiverPath (river-generator.ts) by tools/capture-original-river-paths.mjs; see provenance.json.",
	rivers
}));
console.log(`river paths: ${rivers.length} rivers, ${rivers.reduce((a, r) => a + r.points.length, 0)} points`);
