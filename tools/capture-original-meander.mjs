// Runs the ORIGINAL's own river geometry (`meander` and `projectToNearestEdge` in src/utils/pathUtils.ts, and `Rivers.addMeandering`,
// `getOffset`, `getSourceWidth`, `getWidth` and `getApproximateLength` in src/generators/river-generator.ts; bundled as described in
// tools/original-bundle/README.md). Usage:
//   node tools/capture-original-meander.mjs <bundle.mjs> <out dir>
// Four parts, each saved exactly (numbers round-trip through JSON):
//   meander    random cell lists on made-up positions (steps of every size around the original's distance thresholds, border exits, custom
//              anchors, water flags, every start step and cell count): the points and the anchor indices, through `relaxAcuteAngles`
//   edge       `projectToNearestEdge` on random points and on ties
//   widths     `getOffset`, `getSourceWidth`, `getWidth` and `getApproximateLength` on a grid of inputs
//   rivers     `addMeandering` on river-like cell lists walked downhill over real packed maps, with a made-up flux array
import { createHash } from "node:crypto";
import { writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const [bundlePath, outDir] = process.argv.slice(2);
if (!bundlePath || !outDir) throw new Error("usage: capture-original-meander.mjs <bundle.mjs> <out dir>");

globalThis.window = globalThis;
globalThis.TIME = false;
globalThis.DEBUG = {};
globalThis.WARN = false;
globalThis.document = { readyState: "loading", addEventListener() {}, documentElement: {} };
globalThis.options = { map: { seed: "", graph: { width: 1280, height: 800, points: 10000 } }, generation: {} };
await import(pathToFileURL(resolve(bundlePath)).href);
const meander = globalThis.__meander, projectToNearestEdge = globalThis.__projectToNearestEdge, Rivers = globalThis.Rivers;
const keys = Object.keys(globalThis.__heightmapTemplates);

// this file's own small generator, so the cases do not depend on anything else
let state = 987654321;
const next = () => { state = (Math.imul(state, 1664525) + 1013904223) >>> 0; return state / 4294967296; };
const pick = list => list[Math.floor(next() * list.length)];

// ---- meander
const meanderCases = [];
const startSteps = [1, 2, 5, 10, 18, 19, 25];
const lengths = [0, 2, 3.5, 5, 5.5, 6, 6.5, 8, 8.5, 12, 15];
for (let k = 0; k < 600; k++) {
	const n = 2 + Math.floor(next() * 13);
	const cells = [], positions = [];
	let x = 10 + next() * 80, y = 10 + next() * 80;
	for (let i = 0; i < n; i++) {
		const isBorder = i > 0 && i === n - 1 && next() < 0.2;
		cells.push(isBorder ? -1 : i);
		positions.push([x, y]);
		const length = pick(lengths), angle = next() < 0.3 ? pick([0, Math.PI / 2, Math.PI, -Math.PI / 2]) : next() * 2 * Math.PI;
		x = Math.min(100, Math.max(0, x + Math.cos(angle) * length));
		y = Math.min(100, Math.max(0, y + Math.sin(angle) * length));
	}
	if (next() < 0.1) cells[0] = -1;
	const options = { meandering: pick([0.5, 0.5, 0.2, 1]), startStep: pick(startSteps) };
	if (next() < 0.4) options.cellCount = pick([3, 4, 5, 6, 8]);
	if (next() < 0.5) options.isWaterCell = cells.map(() => next() < 0.3);
	if (next() < 0.7) options.bounds = { width: 100, height: 100 };
	if (next() < 0.1) options.anchors = cells.map(() => [next() * 100, next() * 100]);
	const { points, anchorIndices } = meander(cells, positions, options);
	meanderCases.push({ cells, positions, options, points, anchorIndices });
}

// ---- projectToNearestEdge
const edgeCases = [];
for (const [w, h] of [[100, 60], [60, 100], [100, 100]]) {
	for (let k = 0; k < 150; k++) {
		let point = [Math.round(next() * w * 10) / 10, Math.round(next() * h * 10) / 10];
		if (k % 5 === 0) point = [w / 2, h / 2];
		if (k % 5 === 1) point = [Math.min(w, h) / 2, Math.min(w, h) / 2];
		if (k % 5 === 2) point = [0, 0];
		if (k % 5 === 3) point = [w, h];
		edgeCases.push({ width: w, height: h, point, edge: projectToNearestEdge(point, w, h) });
	}
}

// ---- widths
const widthCases = [];
for (const flux of [0, 1, 5, 30, 100, 500, 1000, 5000, 65535]) {
	for (const pointIndex of [0, 1, 2, 3, 5, 8, 9, 10, 20, 50]) {
		for (const [widthFactor, startingWidth] of [[1, 0], [1.2, 0.05], [0.7, 0.3], [2.4, 0]]) {
			widthCases.push({ flux, pointIndex, widthFactor, startingWidth, offset: Rivers.getOffset({ flux, pointIndex, widthFactor, startingWidth }) });
		}
	}
}
const sourceWidths = [0, 1, 7, 30, 100, 1000, 65535].map(flux => ({ flux, width: Rivers.getSourceWidth(flux) }));
const widths = [0, 0.01, 0.5, 1, 1.5, 2, 3.7, 10].map(offset => ({ offset, width: Rivers.getWidth(offset) }));
const lengthCases = [];
for (let k = 0; k < 60; k++) {
	const n = Math.floor(next() * 12);
	const points = Array.from({ length: n }, () => [next() * 100, next() * 100]);
	lengthCases.push({ points, length: Rivers.getApproximateLength(points) });
}
lengthCases.push({ points: [], length: Rivers.getApproximateLength([]) }, { points: [[1, 1]], length: Rivers.getApproximateLength([[1, 1]]) });

// ---- Math.hypot (the original's corner cosines and lengths use it, and V8's is not sqrt(a * a + b * b))
const hypotCases = [];
for (let k = 0; k < 3000; k++) {
	const scale = pick([1, 1, 1, 0.001, 1000, 1e8]);
	const a = (next() - 0.5) * 100 * scale, b = (next() - 0.5) * 100 * scale;
	hypotCases.push({ a, b, hypot: Math.hypot(a, b) });
}
for (const [a, b] of [[0, 0], [3, 4], [-3, 4], [0, 5], [5, 0], [1e-200, 1e-200], [1e200, 1e200], [-0, 0]]) hypotCases.push({ a, b, hypot: Math.hypot(a, b) });

// ---- Math.sin, Math.cos, Math.atan2 (V8 computes them with fdlibm; the system library differs in the last digits for some arguments)
const trigCases = [];
for (let k = 0; k < 5000; k++) {
	const a = k < 4000 ? (next() - 0.5) * 2 * 3.2 : (next() - 0.5) * 2 * pick([10, 100, 1000]);
	trigCases.push({ a, sin: Math.sin(a), cos: Math.cos(a) });
}
for (const a of [0, 1e-9, -1e-9, Math.PI / 4, Math.PI / 2, -Math.PI / 2, Math.PI, -Math.PI, 3 * Math.PI / 4, 2.356194490192345, 0.7853981633974483, 1.5707963267948966, 3.141592653589793]) trigCases.push({ a, sin: Math.sin(a), cos: Math.cos(a) });
const atan2Cases = [];
for (let k = 0; k < 5000; k++) {
	const scale = pick([1, 1, 1, 0.01, 100, 1e6]);
	let y = (next() - 0.5) * 2 * 50 * scale, x = (next() - 0.5) * 2 * 50 * scale;
	const special = next();
	if (special < 0.05) y = 0; else if (special < 0.1) x = 0; else if (special < 0.13) x = 1; else if (special < 0.16) x = Math.abs(y); else if (special < 0.18) x = -Math.abs(y);
	atan2Cases.push({ y, x, atan2: Math.atan2(y, x) });
}
for (const [y, x] of [[0, 0], [0, 1], [0, -1], [1, 0], [-1, 0], [1e300, 1e-300], [1e-300, 1e300], [-1e-300, -1e300], [5, 1], [-5, 1], [1, 1]]) atan2Cases.push({ y, x, atan2: Math.atan2(y, x) });

// ---- bulk checks of the fdlibm functions: 300,000 arguments each, only the sha256 of the results (explicitly little-endian doubles) is kept;
// the arguments come from small generators whose recipe the Swift test repeats exactly (a 32-bit linear congruential generator)
const bulkGenerator = seed => { let st = seed >>> 0; return () => { st = (Math.imul(st, 1664525) + 1013904223) >>> 0; return st / 4294967296; }; };
const shaOf = values => { const b = Buffer.alloc(values.length * 8); values.forEach((v, i) => b.writeDoubleLE(v, i * 8)); return createHash("sha256").update(b).digest("hex"); };
const bulk = {};
{
	const g = bulkGenerator(20241021), sins = [], coss = [];
	for (let k = 0; k < 300000; k++) {
		const r = g();
		const a = k < 200000 ? (r - 0.5) * 2 * 3.2 : k < 220000 ? (0.785 + r * 0.0004) * (k % 2 === 0 ? 1 : -1) : (r - 0.5) * 2 * 1000;
		sins.push(Math.sin(a)); coss.push(Math.cos(a));
	}
	bulk.shaSin = shaOf(sins); bulk.shaCos = shaOf(coss);
	const h = bulkGenerator(777), atans = [];
	for (let k = 0; k < 300000; k++) {
		const r = h(), sign = k % 2 === 0 ? 1 : -1, mode = k % 5;
		const a = mode === 0 ? (r - 0.5) * 10 : mode === 1 ? (r - 0.5) * 200 : mode === 2 ? r - 0.5 : mode === 3 ? sign * (1.18 + r * 1.3) : sign * (0.4 + r * 0.1);
		atans.push(Math.atan(a));
	}
	bulk.shaAtan = shaOf(atans);
	const q = bulkGenerator(4242), atan2s = [];
	for (let k = 0; k < 300000; k++) {
		const scale = [1, 1e-3, 1e5, 1][k % 4];
		const y = (q() - 0.5) * 100 * scale, x = (q() - 0.5) * 100 * scale;
		atan2s.push(Math.atan2(y, x));
	}
	bulk.shaAtan2 = shaOf(atan2s);
}

// ---- rivers over real packed maps
const defaultGeography = () => ({ mapSize: 100, latitude: 50, longitude: 50, coordinates: { latT: 180, latN: 90, latS: -90, lonT: 320, lonW: -160, lonE: 160 } });
async function build(seed, width, height, cellsDesired, key) {
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
	globalThis.pack = {};
	globalThis.Pack.generate();
	globalThis.Features.markupPack();
}
const riverRuns = [];
for (const [seed, width, height, cellsDesired] of [["kaz-1", 1280, 800, 2000], ["mid", 640, 400, 600], ["日本語", 640, 400, 1000]]) {
	for (const key of keys) {
		await build(seed, width, height, cellsDesired, key);
		const { cells } = globalThis.pack;
		const n = cells.i.length;
		cells.fl = Uint16Array.from({ length: n }, (_, i) => (i * 37 + 11) % 500);
		const flux = Array.from(cells.fl);
		const rivers = [];
		for (let start = 3; start < n && rivers.length < 14; start += Math.max(7, Math.floor(n / 25))) {
			// walk to the lowest neighbour while it is lower, leaving by the border (-1) or ending in water
			const list = [start];
			for (let step = 0; step < 80; step++) {
				const here = list[list.length - 1];
				if (cells.h[here] < 20) break;
				if (cells.b[here] && step > 0) { list.push(-1); break; }
				const lowest = cells.c[here].reduce((a, c) => (cells.h[c] < cells.h[a] ? c : a));
				if (cells.h[lowest] >= cells.h[here] && cells.h[lowest] >= 20) break;
				list.push(lowest);
			}
			if (list.length < 2) continue;
			rivers.push({ cells: list, points: Rivers.addMeandering(list) });
		}
		// also a few random neighbour walks (zig-zags that give acute corners) and lists that start in water or with the border
		for (let k = 0; k < 4; k++) {
			let here = Math.floor(next() * n);
			const list = [here];
			for (let step = 0; step < 12; step++) { here = pick(cells.c[here]); list.push(here); }
			if (k === 3) list.push(-1);
			rivers.push({ cells: list, points: Rivers.addMeandering(list) });
		}
		riverRuns.push({ seed, width, height, cellsDesired, key, flux, rivers });
	}
}
writeFileSync(join(resolve(outDir), "meander-original.json"), JSON.stringify({
	about: "Captured from the original's own meander, projectToNearestEdge (pathUtils.ts) and Rivers.addMeandering, getOffset, getSourceWidth, getWidth, getApproximateLength (river-generator.ts) by tools/capture-original-meander.mjs; see provenance.json.",
	meanderCases, edgeCases, widthCases, sourceWidths, widths, lengthCases, hypotCases, trigCases, atan2Cases, bulk, riverRuns
}));
console.log(`meander: ${meanderCases.length} cases, ${edgeCases.length} edge, ${widthCases.length} offsets, ${riverRuns.reduce((a, r) => a + r.rivers.length, 0)} rivers on ${riverRuns.length} maps`);
