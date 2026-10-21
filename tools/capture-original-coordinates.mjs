// Runs the ORIGINAL's own `Coordinates.generate` (bundled as described in tools/original-bundle/README.md) after the original's own
// chain that precedes it in its generation pipeline: Grid.generate, HeightmapGenerator.generate, Features.markupGrid,
// Grid.addDeepDepressionLakes and Grid.openNearSeaLakes. Usage:
//   node tools/capture-original-coordinates.mjs <bundle.mjs> <out dir>
// For every run it saves the random generator's state BEFORE `Coordinates.generate` (so the Swift port can check where the stream
// starts, rather than assume it) and AFTER it (so the number of draws is checked too), whether the map is "partial" (land
// touching the border), the geography it chose and the latitude/longitude box it calculated.
import { writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const [bundlePath, outDir] = process.argv.slice(2);
if (!bundlePath || !outDir) throw new Error("usage: capture-original-coordinates.mjs <bundle.mjs> <out dir>");

globalThis.window = globalThis;
globalThis.TIME = false;
globalThis.document = { readyState: "loading", addEventListener() {}, documentElement: {} };
globalThis.options = { map: { seed: "", graph: { width: 1280, height: 800, points: 10000 } }, generation: {} };
await import(pathToFileURL(resolve(bundlePath)).href);
const keys = Object.keys(globalThis.__heightmapTemplates);

const defaultGeography = () => ({ mapSize: 100, latitude: 50, longitude: 50, coordinates: { latT: 180, latN: 90, latS: -90, lonT: 320, lonW: -160, lonE: 160 } });

async function capture(seed, width, height, cellsDesired, heightmapKey, templateOption, requested) {
	globalThis.options.map = { seed, graph: { width, height, points: cellsDesired }, geography: defaultGeography() };
	globalThis.options.generation = { lakeElevationLimit: 20, template: templateOption, geography: { mapSize: null, latitude: null, longitude: null, ...requested } };
	const graph = globalThis.Grid.generate(seed, width, height, cellsDesired);
	await globalThis.HeightmapGenerator.generate(graph, heightmapKey);
	globalThis.grid = graph;
	globalThis.Features.markupGrid();
	globalThis.Grid.addDeepDepressionLakes();
	globalThis.Grid.openNearSeaLakes();
	const isPartial = graph.features.some(f => f.land && f.border);
	const stateBefore = Array.from(Math.random.exportState());
	globalThis.Coordinates.generate();
	const stateAfter = Array.from(Math.random.exportState());
	const g = globalThis.options.map.geography;
	return {
		seed, width, height, cellsDesired, heightmapKey, templateOption, requested: { mapSize: null, latitude: null, longitude: null, ...requested },
		isPartial, stateBefore, stateAfter,
		geography: { mapSize: g.mapSize, latitude: g.latitude, longitude: g.longitude }, coordinates: g.coordinates
	};
}

const configs = [
	["kaz-1", 1280, 800, 2000],
	["", 1280, 800, 1000],
	["日本語", 640, 400, 1000],
	["wide", 1000, 90, 300],
	["tiny", 100, 60, 24],
	["mid", 640, 400, 600]
];
const runs = [];
// every heightmap template as its own template option (the random branches differ per template)
for (const [seed, width, height, cellsDesired] of configs) {
	for (const key of keys) runs.push(await capture(seed, width, height, cellsDesired, key, key, {}));
}
// the real-world positions the original knows (a fixed table, no random draws), on one heightmap
for (const [seed, width, height, cellsDesired] of configs.slice(0, 3)) {
	for (const templateOption of ["europe", "world", "iceland", "us-centric", "world-from-pacific"]) {
		runs.push(await capture(seed, width, height, cellsDesired, "highIsland", templateOption, {}));
	}
}
// geography the caller asked for: each value is used when given, and drawn otherwise
for (const [seed, width, height, cellsDesired] of configs.slice(0, 4)) {
	for (const [key, requested] of [
		["continents", { mapSize: 50 }], ["archipelago", { latitude: 30 }], ["pangea", { longitude: 20 }],
		["shattered", { mapSize: 40, latitude: 60 }], ["highIsland", { mapSize: 12, latitude: 5, longitude: 90 }], ["atoll", { mapSize: 0 }]
	]) {
		runs.push(await capture(seed, width, height, cellsDesired, key, key, requested));
	}
}
writeFileSync(join(resolve(outDir), "coordinates-original.json"), JSON.stringify({
	about: "Captured from the original's own Coordinates.generate (coordinates.ts) after its own grid, heightmap, markupGrid and lake steps, by tools/capture-original-coordinates.mjs; see provenance.json. The stream state is the original Alea's exportState (s0, s1, s2, c) before and after the call.",
	runs
}));
console.log(`coordinates: ${runs.length} runs, ${runs.filter(r => r.isPartial).length} partial, templates ${keys.length}`);
