// Runs the ORIGINAL's own `Precipitation.generate` (bundled as described in tools/original-bundle/README.md) after the original's own
// chain that precedes it in its pipeline: Grid.generate, HeightmapGenerator.generate, Features.markupGrid, Grid.addDeepDepressionLakes,
// Grid.openNearSeaLakes, Coordinates.generate and Temperature.generate. Usage:
//   node tools/capture-original-precipitation.mjs <bundle.mjs> <out dir>
// For every run it saves the bounds and temperatures' hash the original had, the winds `getWinds()` found, the precipitation of every
// grid cell (as a sha256 of the Uint8 bytes, and the whole array for small maps) and the next value of the random stream after the
// run (a checkpoint for the draws). Settings varied: the precipitation percentage, the six wind angles and the geography.
import { createHash } from "node:crypto";
import { writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const [bundlePath, outDir] = process.argv.slice(2);
if (!bundlePath || !outDir) throw new Error("usage: capture-original-precipitation.mjs <bundle.mjs> <out dir>");

globalThis.window = globalThis;
globalThis.TIME = false;
globalThis.DEBUG = {};
globalThis.document = { readyState: "loading", addEventListener() {}, documentElement: {} };
globalThis.options = { map: { seed: "", graph: { width: 1280, height: 800, points: 10000 } }, generation: {} };
await import(pathToFileURL(resolve(bundlePath)).href);
const keys = Object.keys(globalThis.__heightmapTemplates);
const sha = bytes => createHash("sha256").update(Buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength)).digest("hex");

const defaultGeography = () => ({ mapSize: 100, latitude: 50, longitude: 50, coordinates: { latT: 180, latN: 90, latS: -90, lonT: 320, lonW: -160, lonE: 160 } });
const windSets = {
	default: [225, 45, 225, 315, 135, 315],
	allWest: [90, 90, 90, 90, 90, 90],
	allEast: [270, 270, 270, 270, 270, 270],
	north: [180, 180, 180, 180, 180, 180],
	south: [0, 0, 0, 0, 0, 0],
	boundaries: [40, 140, 220, 320, 100, 260],
	boundaries2: [41, 139, 221, 319, 101, 259],
	edges: [280, 80, 281, 79, 359, 1],
	calm: [30, 150, 190, 200, 270, 330],
	mixed: [45, 135, 225, 315, 90, 270]
};
const precipitations = { p100: 100, p50: 50, p200: 200, p0: 0, p13: 13.5, p500: 500 };

async function capture(seed, width, height, cellsDesired, key, windName, precName, requested, full) {
	const winds = windSets[windName];
	const precipitation = precipitations[precName];
	globalThis.options.map = {
		seed, graph: { width, height, points: cellsDesired }, geography: defaultGeography(),
		climate: { temperature: { equator: 27, northPole: -30, southPole: -15 }, precipitation, winds: [...winds] },
		units: { height: { exponent: 2 } }
	};
	globalThis.options.generation = { lakeElevationLimit: 20, template: key, geography: { mapSize: null, latitude: null, longitude: null, ...requested } };
	const graph = globalThis.Grid.generate(seed, width, height, cellsDesired);
	await globalThis.HeightmapGenerator.generate(graph, key);
	globalThis.grid = graph;
	globalThis.Features.markupGrid();
	globalThis.Grid.addDeepDepressionLakes();
	globalThis.Grid.openNearSeaLakes();
	globalThis.Coordinates.generate();
	globalThis.Temperature.generate();
	globalThis.Precipitation.generate();
	const next = Math.random(); // the stream checkpoint: the first value after the run's draws
	const prec = graph.cells.prec;
	const entry = {
		seed, width, height, cellsDesired, key, windName, winds, precName, precipitation,
		requested: { mapSize: null, latitude: null, longitude: null, ...requested },
		coordinates: globalThis.options.map.geography.coordinates, cells: prec.length, cellsX: graph.cellsX, cellsY: graph.cellsY,
		tempSha256: sha(graph.cells.temp), precSha256: sha(prec), min: Math.min(...prec), max: Math.max(...prec),
		windsFound: globalThis.Precipitation.getWinds(), nextRandom: next
	};
	if (full) entry.prec = Array.from(prec);
	return entry;
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
for (const [seed, width, height, cellsDesired] of configs) {
	for (const key of keys) runs.push(await capture(seed, width, height, cellsDesired, key, "default", "p100", {}, cellsDesired <= 600));
}
// other winds and rain levels on the whole world (every band and every wind tier) and on slices
const slices = [{ mapSize: 100, latitude: 50, longitude: 50 }, { mapSize: 20, latitude: 0, longitude: 50 }, { mapSize: 20, latitude: 100, longitude: 50 }, { mapSize: 60, latitude: 20, longitude: 50 }, { mapSize: 30, latitude: 50, longitude: 50 }];
for (const [seed, width, height, cellsDesired] of configs.slice(0, 3)) {
	for (const windName of Object.keys(windSets)) {
		for (const requested of slices) runs.push(await capture(seed, width, height, cellsDesired, "continents", windName, "p100", requested, false));
	}
	for (const precName of Object.keys(precipitations)) {
		for (const requested of slices.slice(0, 3)) runs.push(await capture(seed, width, height, cellsDesired, "archipelago", "default", precName, requested, false));
	}
}
// a few with the whole arrays, for cell-for-cell diagnosis
for (const [seed, width, height, cellsDesired] of [["tiny", 100, 60, 24], ["mid", 640, 400, 600]]) {
	for (const [windName, precName] of [["default", "p100"], ["allWest", "p200"], ["allEast", "p50"], ["north", "p100"], ["south", "p100"], ["boundaries", "p13"]]) {
		runs.push(await capture(seed, width, height, cellsDesired, "highIsland", windName, precName, { mapSize: 100, latitude: 50, longitude: 50 }, true));
	}
}
writeFileSync(join(resolve(outDir), "precipitation-original.json"), JSON.stringify({
	about: "Captured from the original's own Precipitation.generate (precipitation-generator.ts) after its own grid, heightmap, markupGrid, lake, Coordinates and Temperature steps, by tools/capture-original-precipitation.mjs; see provenance.json. prec is the grid cells' Uint8 precipitation.",
	runs
}));
console.log(`precipitation: ${runs.length} runs, ${runs.filter(r => r.prec).length} with whole arrays`);
