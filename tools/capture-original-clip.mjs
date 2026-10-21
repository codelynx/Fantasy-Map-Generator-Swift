// Runs the ORIGINAL's own `clipPoly` (src/utils/commonUtils.ts, which clips with lineclip's `clipPolygon`; bundled as described in
// tools/original-bundle/README.md) over polygons made here: random polygons around and across the map rectangle, with points exactly on
// its edges and corners, polygons wholly inside, wholly outside, concave, with repeated points, of 0 to 12 points. Usage:
//   node tools/capture-original-clip.mjs <bundle.mjs> <out dir>
// Each case saves the input, the rectangle and the output exactly (numbers round-trip through JSON).
import { writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const [bundlePath, outDir] = process.argv.slice(2);
if (!bundlePath || !outDir) throw new Error("usage: capture-original-clip.mjs <bundle.mjs> <out dir>");

globalThis.window = globalThis;
globalThis.TIME = false;
globalThis.DEBUG = {};
globalThis.document = { readyState: "loading", addEventListener() {}, documentElement: {} };
globalThis.options = { map: { seed: "", graph: { width: 1280, height: 800, points: 10000 } }, generation: {} };
await import(pathToFileURL(resolve(bundlePath)).href);
const clipPoly = globalThis.__clipPoly;

// a small deterministic generator (this file's own, so the cases do not depend on anything else)
let state = 123456789;
const next = () => { state = (Math.imul(state, 1664525) + 1013904223) >>> 0; return state / 4294967296; };

const rectangles = [[100, 60], [1280, 800], [10, 10]];
const cases = [];
const add = (points, width, height) => cases.push({ width, height, points, clipped: clipPoly(points.map(p => [...p]), width, height) });

for (const [w, h] of rectangles) {
	// fixed shapes: inside, outside on each side, around, across, on the edges and corners, a single point, nothing, a slit
	add([], w, h);
	add([[w / 2, h / 2]], w, h);
	add([[1, 1], [w - 1, 1], [w - 1, h - 1], [1, h - 1]], w, h);
	add([[-5, -5], [-1, -5], [-1, -1]], w, h);
	add([[w + 1, 0], [w + 5, 0], [w + 5, h]], w, h);
	add([[-10, -10], [w + 10, -10], [w + 10, h + 10], [-10, h + 10]], w, h);
	add([[0, 0], [w, 0], [w, h], [0, h]], w, h);
	add([[0, 0], [w, 0], [w / 2, h]], w, h);
	add([[-5, h / 2], [w + 5, h / 2], [w / 2, h + 20]], w, h);
	add([[w / 2, -5], [w / 2, h + 5], [w / 2 + 1, h / 2]], w, h);
	add([[0, 0], [0, 0], [w, h], [w, h]], w, h);
	add([[w / 2, h / 2], [w / 2, h / 2], [w / 2, h / 2]], w, h);
	add([[-w, h / 2], [w * 2, h / 2], [w * 2, h / 2 + 0.001]], w, h);
	// a concave star-like polygon crossing the rectangle
	add([[-20, h / 2], [w / 4, h / 4], [w / 2, -20], [3 * w / 4, h / 4], [w + 20, h / 2], [3 * w / 4, 3 * h / 4], [w / 2, h + 20], [w / 4, 3 * h / 4]], w, h);
	// random polygons, some points snapped onto the edges
	for (let k = 0; k < 220; k++) {
		const n = Math.floor(next() * 13);
		const points = [];
		for (let i = 0; i < n; i++) {
			let x = (next() * 1.6 - 0.3) * w, y = (next() * 1.6 - 0.3) * h;
			const snap = next();
			if (snap < 0.08) x = 0; else if (snap < 0.16) x = w; else if (snap < 0.24) y = 0; else if (snap < 0.32) y = h;
			if (next() < 0.5) { x = Math.round(x * 10) / 10; y = Math.round(y * 10) / 10; }
			points.push([x, y]);
		}
		add(points, w, h);
	}
}
writeFileSync(join(resolve(outDir), "clip-original.json"), JSON.stringify({
	about: "Captured from the original's own clipPoly (commonUtils.ts, lineclip 2.0.0 clipPolygon) by tools/capture-original-clip.mjs; see provenance.json. Input points, the rectangle and the output, exactly.",
	cases
}));
console.log(`clip: ${cases.length} cases, ${cases.filter(c => c.clipped.length === 0).length} empty results, ${cases.filter(c => c.clipped.length > c.points.length).length} longer than their input`);
