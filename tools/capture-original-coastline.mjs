// Runs the ORIGINAL's own coastline generator (`Coastline`, bundled as described in tools/original-bundle/README.md) on
// explicit inputs and saves what it returns. Usage:
//   node tools/capture-original-coastline.mjs <bundle.mjs> <out dir>
// What is captured, each from the original's own code and nothing re-implemented here:
//   featureSeed       the seed of a feature's coastline, for map seeds, feature ids and variants (the original's own string form)
//   noise             its integer hash, for seeds and integer tuples including negatives and values beyond 2^31
//   roughness         roughnessAt on a grid of points for several settings
//   fractalize        the displaced outline (and where the original vertices sit in it) for explicit CLOSED outlines, seeds and
//                     settings. `fractalize` treats its input as closed, last point back to first.
//   shape             getFeatureShape, the layer that implements `enabled: false` (and the calmer lake shore)
//   localEdit         a 24-vertex ring and the same ring with one vertex moved, as the original's own test does
// Numbers are written as JSON, which prints each double so that it reads back as the same double. `simplify` is not used: the
// outlines are supplied, so the original's simplification and clipping are not exercised.
import { writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const [bundlePath, outDir] = process.argv.slice(2);
if (!bundlePath || !outDir) throw new Error("usage: capture-original-coastline.mjs <bundle.mjs> <out dir>");

globalThis.window = globalThis;
globalThis.TIME = false;
globalThis.document = { readyState: "loading", addEventListener() {}, documentElement: {} };
globalThis.options = { map: { seed: "1", graph: { width: 100, height: 100, points: 100 }, coastline: undefined }, generation: {} };
await import(pathToFileURL(resolve(bundlePath)).href);
const Coastline = globalThis.__coastline;
if (!Coastline) throw new Error("the bundle did not expose the original's Coastline");
const defaults = Coastline.getDefaultSettings();
globalThis.options.map.coastline = { ...defaults };

const named = {
	default: defaults,
	depth1: { ...defaults, maxDepth: 1 },
	depth6: { ...defaults, maxDepth: 6 },
	noAmplitude: { ...defaults, baseAmplitude: 0 },
	allRough: { ...defaults, smoothThreshold: 0 },
	longMinEdge: { ...defaults, minEdge: 5 },
	contrast1: { ...defaults, roughnessContrast: 1 },
	smallScale: { ...defaults, roughnessScale: 5 },
	tinyScale: { ...defaults, roughnessScale: 0.5 },
	noDecay: { ...defaults, amplitudeDecay: 1, baseAmplitude: 3 },
	variant3: { ...defaults, variant: 3 },
	lakeCalm: { ...defaults, lakeSmoothThreshMult: 3 }
};

// featureSeed
const featureSeeds = [];
for (const seed of ["", "1", "2", "kaz-1", "café", "café", "😀", "a b"]) {
	for (const id of [0, 1, 2, 17, 255, 100000]) {
		for (const variant of [0, 1, 7]) {
			globalThis.options.map.seed = seed;
			featureSeeds.push({ seed, id, variant, value: Coastline.featureSeed(id, { ...defaults, variant }) });
		}
	}
}
globalThis.options.map.seed = "1";

// noise
const seeds = [0, 1, -1, 12345, -987654321, 2147483647, -2147483648, 0x5bd1e995 | 0, 0x9e3779b9 | 0];
const ints = [0, 1, -1, 2, -2, 63, 64, 65, -64, 1000, -1000, 123456, 2147483647, -2147483648, 4294967295, 4294967296, 6400000];
const noises = [];
for (const seed of seeds) {
	for (let i = 0; i < ints.length; i++) {
		noises.push({ seed, values: [ints[i], ints[(i * 7 + 3) % ints.length]], value: Coastline.noise(seed, ints[i], ints[(i * 7 + 3) % ints.length]) });
	}
	const four = [ints[2], ints[5], ints[9], ints[13]];
	noises.push({ seed, values: four, value: Coastline.noise(seed, ...four) });
	const five = [ints[3], ints[6], ints[10], ints[14], ints[1]];
	noises.push({ seed, values: five, value: Coastline.noise(seed, ...five) });
	noises.push({ seed, values: [], value: Coastline.noise(seed) });
}

// roughness
const roughness = [];
for (const [name, settings] of Object.entries(named)) {
	if (!["default", "smallScale", "tinyScale", "contrast1", "variant3"].includes(name)) continue;
	for (const seed of [0, 424242, -31337]) {
		const samples = [];
		for (const x of [-12.5, 0, 0.5, 7.25, 31.9, 59.99, 60, 100, 187.3, 299.5]) {
			for (const y of [-3, 0, 0.1, 13.7, 45, 60.001, 120, 250.25]) samples.push({ x, y, value: Coastline.roughnessAt(seed, x, y, settings) });
		}
		roughness.push({ settings: name, seed, samples });
	}
}

// fractalize on explicit closed outlines
const outlines = {
	square: { width: 100, height: 100, points: [[10, 10], [90, 10], [90, 90], [10, 90]] },
	irregular: { width: 400, height: 300, points: [[50.5, 40.25], [120, 22.75], [210.125, 61], [300.5, 55], [345, 130.3], [310, 220.9], [220.4, 260], [140, 241.5], [60.75, 200], [38, 120]] },
	borderEdges: { width: 100, height: 100, points: [[0, 20], [0, 70], [30, 90.5], [100, 100], [100, 40.25], [60, 0], [20, 5]] },
	tinyEdges: { width: 100, height: 100, points: [[20, 20], [20.5, 20.2], [21, 20], [21, 20.9], [20.1, 21]] },
	triangle: { width: 100, height: 100, points: [[5.5, 5.5], [95.5, 20.25], [50, 80]] },
	// midpoints whose x (or y) times 64 is exactly a negative half (e.g. -20.0078125 * 64 = -1280.5), where JavaScript's
	// Math.round (halves toward +infinity) and Swift's default rounding (away from zero) differ
	negativeHalvesX: { width: 100, height: 100, points: [[-30.0078125, 10.0078125], [-10.0078125, 50], [20, 30.5]] },
	negativeHalvesY: { width: 100, height: 100, points: [[10.0078125, -30.0078125], [50, -10.0078125], [30.5, 20]] }
};
const fractalized = [];
for (const [outlineName, outline] of Object.entries(outlines)) {
	globalThis.options.map.graph = { width: outline.width, height: outline.height, points: 100 };
	for (const [settingsName, settings] of Object.entries(named)) {
		for (const seed of [0, 424242, -31337, 2147483647]) {
			const shape = Coastline.fractalize(outline.points.map(p => [...p]), seed, settings);
			fractalized.push({ outline: outlineName, settings: settingsName, seed, points: shape.points, origIndices: shape.origIndices });
		}
	}
}

// getFeatureShape: the bypass and the lake shore
const shapes = [];
const shapeOutline = outlines.irregular;
globalThis.options.map.graph = { width: shapeOutline.width, height: shapeOutline.height, points: 100 };
for (const [mapSeed, featureId, type, settingsName, override] of [
	["1", 1, "island", "default", false], ["1", 1, "island", "default", true], ["2", 1, "island", "default", false],
	["1", 2, "island", "default", false], ["1", 1, "lake", "default", false], ["1", 1, "lake", "lakeCalm", false],
	["1", 1, "island", "variant3", false], ["1", 1, "island", "depth1", false]
]) {
	globalThis.options.map.seed = mapSeed;
	globalThis.options.map.coastline = { ...named[settingsName] };
	for (const enabled of [true, false]) {
		globalThis.options.map.coastline.enabled = enabled;
		const feature = { i: featureId, type, vertices: [] };
		if (override) feature.coastline = { ...named.depth1, enabled };
		const shape = Coastline.getFeatureShape(feature, shapeOutline.points.map(p => [...p]));
		shapes.push({ mapSeed, featureId, type, settings: settingsName, enabled, featureOverride: override, points: shape.points, origIndices: shape.origIndices });
	}
}
globalThis.options.map.seed = "1";
globalThis.options.map.coastline = { ...defaults };

// local edit, as the original's own test: a 24-vertex ring on a 100 x 100 map, one vertex moved by (1.5, 1.5)
globalThis.options.map.graph = { width: 100, height: 100, points: 100 };
const ring = Array.from({ length: 24 }, (_, i) => { const a = (2 * Math.PI * i) / 24; return [50 + 40 * Math.cos(a), 50 + 40 * Math.sin(a)]; });
const moved = ring.map((p, i) => (i === 6 ? [p[0] + 1.5, p[1] + 1.5] : [...p]));
const seed = Coastline.featureSeed(1, defaults);
const localEdit = {
	seed,
	ring,
	moved,
	before: Coastline.fractalize(ring.map(p => [...p]), seed, defaults),
	after: Coastline.fractalize(moved, seed, defaults)
};

writeFileSync(join(resolve(outDir), "coastline-original.json"), JSON.stringify({
	about: "Captured from the original's own Coastline (coastline-generator.ts) by tools/capture-original-coastline.mjs; see provenance.json. Closed outlines only: fractalize closes its input. Numbers are JSON doubles.",
	settings: named, outlines, featureSeeds, noises, roughness, fractalized, shapes, localEdit
}));
console.log(`coastline: ${featureSeeds.length} seeds, ${noises.length} noise values, ${roughness.reduce((n, r) => n + r.samples.length, 0)} roughness samples, ${fractalized.length} fractalized outlines, ${shapes.length} shapes`);
