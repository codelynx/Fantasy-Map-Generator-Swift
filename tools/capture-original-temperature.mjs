// Runs the ORIGINAL's own `Temperature.generate` (bundled as described in tools/original-bundle/README.md) after the original's own
// chain that precedes it in its pipeline: Grid.generate, HeightmapGenerator.generate, Features.markupGrid, Grid.addDeepDepressionLakes,
// Grid.openNearSeaLakes and Coordinates.generate. Usage:
//   node tools/capture-original-temperature.mjs <bundle.mjs> <out dir>
// For every run it saves the latitude/longitude bounds the original had (so the port can be fed them directly) and the temperature of
// every grid cell (as a sha256 of the Int8 bytes, and the whole array for small maps). Settings varied: the temperatures at the equator
// and the poles and the height exponent; geography requested to cover tropics, temperate and polar bands.
import { createHash } from "node:crypto";
import { writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const [bundlePath, outDir] = process.argv.slice(2);
if (!bundlePath || !outDir) throw new Error("usage: capture-original-temperature.mjs <bundle.mjs> <out dir>");

globalThis.window = globalThis;
globalThis.TIME = false;
globalThis.DEBUG = {};
globalThis.document = { readyState: "loading", addEventListener() {}, documentElement: {} };
globalThis.options = { map: { seed: "", graph: { width: 1280, height: 800, points: 10000 } }, generation: {} };
await import(pathToFileURL(resolve(bundlePath)).href);
const keys = Object.keys(globalThis.__heightmapTemplates);
const sha = bytes => createHash("sha256").update(Buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength)).digest("hex");

const defaultGeography = () => ({ mapSize: 100, latitude: 50, longitude: 50, coordinates: { latT: 180, latN: 90, latS: -90, lonT: 320, lonW: -160, lonE: 160 } });
const climates = {
	default: { temperature: { equator: 27, northPole: -30, southPole: -15 }, exponent: 2 },
	hot: { temperature: { equator: 40, northPole: 5, southPole: 0 }, exponent: 2 },
	cold: { temperature: { equator: 5, northPole: -50, southPole: -40 }, exponent: 2 },
	extreme: { temperature: { equator: 60, northPole: -100, southPole: -100 }, exponent: 2 },
	exponent15: { temperature: { equator: 27, northPole: -30, southPole: -15 }, exponent: 1.5 },
	exponent22: { temperature: { equator: 27, northPole: -30, southPole: -15 }, exponent: 2.2 },
	exponent3: { temperature: { equator: 27, northPole: -30, southPole: -15 }, exponent: 3 }
};

async function capture(seed, width, height, cellsDesired, key, climateName, requested, full) {
	const climate = climates[climateName];
	globalThis.options.map = {
		seed, graph: { width, height, points: cellsDesired }, geography: defaultGeography(),
		climate: { temperature: { ...climate.temperature }, precipitation: 100, winds: [225, 45, 225, 315, 135, 315] },
		units: { height: { exponent: climate.exponent } }
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
	const temp = graph.cells.temp;
	const entry = {
		seed, width, height, cellsDesired, key, climateName, climate, requested: { mapSize: null, latitude: null, longitude: null, ...requested },
		coordinates: globalThis.options.map.geography.coordinates, cells: temp.length, cellsX: graph.cellsX,
		tempSha256: sha(temp), min: Math.min(...temp), max: Math.max(...temp)
	};
	if (full) entry.temp = Array.from(temp);
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
	for (const key of keys) runs.push(await capture(seed, width, height, cellsDesired, key, "default", {}, cellsDesired <= 600));
}
// other climates on the whole world (every band from pole to pole) and on a polar slice
for (const [seed, width, height, cellsDesired] of configs.slice(0, 3)) {
	for (const climateName of Object.keys(climates)) {
		for (const requested of [{ mapSize: 100, latitude: 50, longitude: 50 }, { mapSize: 20, latitude: 0, longitude: 50 }, { mapSize: 20, latitude: 100, longitude: 50 }, { mapSize: 60, latitude: 20, longitude: 50 }]) {
			runs.push(await capture(seed, width, height, cellsDesired, "continents", climateName, requested, false));
		}
	}
}
// a few with the whole arrays, for cell-for-cell diagnosis
for (const [seed, width, height, cellsDesired] of [["tiny", 100, 60, 24], ["mid", 640, 400, 600]]) {
	for (const climateName of ["default", "hot", "exponent22"]) runs.push(await capture(seed, width, height, cellsDesired, "highIsland", climateName, { mapSize: 100, latitude: 50, longitude: 50 }, true));
}
writeFileSync(join(resolve(outDir), "temperature-original.json"), JSON.stringify({
	about: "Captured from the original's own Temperature.generate (temperature-generator.ts) after its own grid, heightmap, markupGrid, lake and Coordinates steps, by tools/capture-original-temperature.mjs; see provenance.json. temp is the grid cells' Int8 temperatures.",
	runs
}));
console.log(`temperature: ${runs.length} runs, ${runs.filter(r => r.temp).length} with whole arrays`);
