// Captures small reference fixtures from the ORIGINAL project's npm dependencies (alea, delaunator), so the Swift
// port can be tested against them stage by stage. Usage:
//   node tools/capture-fixtures.mjs <path to a clone of Azgaar/Fantasy-Map-Generator with npm install done> <out dir>
// The points are re-implemented here from the original's grid-generator.ts (spacing, jittered points, boundary
// points) and are NOT executed from the original's own code; the random numbers and the triangulation are the
// original's real dependencies. Nothing from the clone is copied except the numbers this script prints.
import { createRequire } from "node:module";
import { copyFileSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { pathToFileURL } from "node:url";
import { join, resolve } from "node:path";

const [clonePath, outDir] = process.argv.slice(2);
if (!clonePath || !outDir) throw new Error("usage: capture-fixtures.mjs <clone> <out dir>");
const clone = resolve(clonePath);
const require = createRequire(join(clone, "package.json"));
const Alea = require("alea");
const DelaunatorModule = require("delaunator");
const Delaunator = DelaunatorModule.default ?? DelaunatorModule;
mkdirSync(outDir, { recursive: true });

const version = name => JSON.parse(readFileSync(join(resolve(clonePath), "node_modules", name, "package.json"), "utf8")).version;
const meta = {
	note: "Captured from the original's npm dependencies; see tools/capture-fixtures.mjs",
	versions: { alea: version("alea"), delaunator: version("delaunator"), "robust-predicates": version("robust-predicates") }
};

// 1. Alea: the first values for a few seeds (empty, ASCII, digits, non-ASCII, a surrogate pair, composed vs decomposed)
// "\u00E9" is precomposed; "e\u0301" is the same letter decomposed. Written as escapes so the two cannot be silently merged.
const seeds = ["", "a", "abc", "kaz-1", "123456789", "日本語", "🗾x", "\u00E9", "e\u0301"];
const alea = seeds.map(seed => {
	const random = Alea(seed);
	return { seed, utf16Units: Array.from({ length: seed.length }, (_, i) => seed.charCodeAt(i)), values: Array.from({ length: 20 }, () => random()) };
});
// A long run for one seed: selected outputs and the generator state after 10,000 calls, to catch accumulated divergence
const long = Alea("kaz-1");
const checkpointIndexes = new Set([0, 1, 9, 99, 999, 4999, 9999]);
const checkpoints = [];
for (let i = 0; i < 10000; i++) {
	const value = long();
	if (checkpointIndexes.has(i)) checkpoints.push({ index: i, value });
}
const longRun = { seed: "kaz-1", calls: 10000, checkpoints, finalState: long.exportState() };
writeFileSync(join(outDir, "alea.json"), JSON.stringify({ ...meta, alea, longRun }, null, 1));

// 1b. orient2d from robust-predicates: nearly collinear points chosen to reach its adaptive (exact) path as well as the fast one
const { orient2d } = require("robust-predicates");
{
	const random = Alea("orient2d-cases");
	const cases = [];
	const push = (ax, ay, bx, by, cx, cy) => cases.push({ ax, ay, bx, by, cx, cy, value: orient2d(ax, ay, bx, by, cx, cy) });
	// well separated, exactly collinear, and the classic hard case near (0.5, 0.5)
	push(0, 0, 1, 0, 0, 1); push(0, 0, 1, 0, 0, -1); push(0, 0, 1, 1, 2, 2); push(12, 12, 24, 24, 0.5, 0.5);
	push(0.5, 0.5, 12, 12, 24, 24); push(-1, -1, 1, 1, 0, 0); push(1e-300, 1e-300, 2e-300, 2e-300, 3e-300, 3.0000000000000004e-300);
	const ulp = x => Math.abs(x) * 2.220446049250313e-16;
	for (let k = 0; k < 160; k++) {
		const scale = 10 ** Math.floor(random() * 12 - 4);
		const ax = (random() - 0.5) * scale, ay = (random() - 0.5) * scale;
		const bx = (random() - 0.5) * scale, by = (random() - 0.5) * scale;
		const t = random() * 3 - 1;
		let cx = ax + t * (bx - ax), cy = ay + t * (by - ay);
		// nudge c by a few ulps, in a random direction, so it is nearly (or exactly) on the line
		const nudge = Math.floor(random() * 5) - 2;
		cx += nudge * ulp(cx) * (random() < 0.5 ? 1 : 0);
		cy += nudge * ulp(cy) * (random() < 0.5 ? 1 : 0);
		push(ax, ay, bx, by, cx, cy);
	}
	// 1c. cases that reach each return point of orient2d, found by running an instrumented copy of the library's own source
	// (built in a temporary folder by replacing five return statements; every value is checked against the real library)
	const tmp = mkdtempSync(join(tmpdir(), "orient2d-"));
	const esm = join(clone, "node_modules", "robust-predicates", "esm");
	copyFileSync(join(esm, "util.js"), join(tmp, "util.js"));
	let src = readFileSync(join(esm, "orient2d.js"), "utf8");
	const rep = (a, b) => { if (src.split(a).length !== 2) throw new Error("pattern not found exactly once: " + a); src = src.replace(a, b); };
	rep("if (det >= errbound || -det >= errbound) {\n        return det;\n    }", "if (det >= errbound || -det >= errbound) {\n        globalThis.__b = 1; return det;\n    }");
	rep("if (acxtail === 0 && acytail === 0 && bcxtail === 0 && bcytail === 0) {\n        return det;\n    }", "if (acxtail === 0 && acytail === 0 && bcxtail === 0 && bcytail === 0) {\n        globalThis.__b = 2; return det;\n    }");
	rep("if (det >= errbound || -det >= errbound) return det;", "if (det >= errbound || -det >= errbound) { globalThis.__b = 3; return det; }");
	rep("return D[Dlen - 1];", "globalThis.__b = 4; return D[Dlen - 1];");
	rep("if (Math.abs(det) >= ccwerrboundA * detsum) return det;", "if (Math.abs(det) >= ccwerrboundA * detsum) { globalThis.__b = 0; return det; }");
	writeFileSync(join(tmp, "orient2d.mjs"), src);
	const { orient2d: traced } = await import(pathToFileURL(join(tmp, "orient2d.mjs")).href);
	const traceOf = (...args) => { globalThis.__b = -1; const value = traced(...args); const real = orient2d(...args); if (value !== real) throw new Error("instrumented copy disagrees with the library"); return { value, branch: globalThis.__b }; };
	// 0 = the fast filter; 1 = after the first exact estimate; 2 = tails all zero; 3 = after the first correction; 4 = the full exact sum
	const search = Alea("orient2d-branches");
	const found = { 0: [], 1: [], 2: [], 3: [], 4: [] };
	for (let k = 0; k < 400000 && Object.values(found).some(l => l.length < 6); k++) {
		const scale = 10 ** Math.floor(search() * 6 - 2);
		const ax = (search() - 0.5) * scale, ay = (search() - 0.5) * scale;
		const bx = (search() - 0.5) * scale, by = (search() - 0.5) * scale;
		const t = search() * 3 - 1;
		let cx = ax + t * (bx - ax), cy = ay + t * (by - ay);
		const mag = 2 ** -(40 + Math.floor(search() * 30));
		cx += (search() - 0.5) * mag * Math.abs(cx + 1e-300) * (search() < 0.7 ? 1 : 0);
		cy += (search() - 0.5) * mag * Math.abs(cy + 1e-300) * (search() < 0.7 ? 1 : 0);
		const { value, branch } = traceOf(ax, ay, bx, by, cx, cy);
		if (found[branch].length < 6) found[branch].push({ ax, ay, bx, by, cx, cy, value, branch });
	}
	const branchCases = Object.values(found).flat();
	// every permutation of the first case of each branch, and exactly collinear triples (value 0, any order)
	const perms = [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]];
	const permutations = [];
	for (const b of [0, 1, 2, 3, 4]) {
		const base = found[b][0];
		if (!base) continue;
		const p = [[base.ax, base.ay], [base.bx, base.by], [base.cx, base.cy]];
		for (const order of perms) {
			const [[ax, ay], [bx, by], [cx, cy]] = order.map(i => p[i]);
			permutations.push({ ax, ay, bx, by, cx, cy, ...traceOf(ax, ay, bx, by, cx, cy), order });
		}
	}
	const collinear = [];
	for (const [ax, ay, bx, by, cx, cy] of [[0, 0, 1, 1, 2, 2], [0.1, 0.1, 0.2, 0.2, 0.3, 0.3], [1e10, 1e10, 2e10, 2e10, 3e10, 3e10], [-5, 7, 5, -7, 15, -21], [1e-200, 0, 2e-200, 0, 3e-200, 0]]) {
		for (const order of perms) {
			const p = [[ax, ay], [bx, by], [cx, cy]];
			const [[a1, a2], [b1, b2], [c1, c2]] = order.map(i => p[i]);
			collinear.push({ ax: a1, ay: a2, bx: b1, by: b2, cx: c1, cy: c2, ...traceOf(a1, a2, b1, b2, c1, c2) });
		}
	}
	// the convention, pinned: the original gives this value for (0,0), (1,0), (0,1)
	const convention = { ax: 0, ay: 0, bx: 1, by: 0, cx: 0, cy: 1, value: orient2d(0, 0, 1, 0, 0, 1) };
	writeFileSync(join(outDir, "orient2d.json"), JSON.stringify({ ...meta, cases, branchCases, permutations, collinear, convention }, null, 1));
}

// 2. Points and triangulation of a tiny grid, from the original's grid-generator.ts logic
const rn = (v, d = 0) => { const m = 10 ** d; return Math.round(v * m) / m; };
function grid(seed, width, height, cellsDesired) {
	Math.random = Alea(seed);
	const spacing = rn(Math.sqrt((width * height) / cellsDesired), 2);
	const radius = spacing / 2;
	const jittering = radius * 0.9;
	const doubleJittering = jittering * 2;
	const jitter = () => Math.random() * doubleJittering - jittering;
	// the original reseeds Math.random inside generate() before placing points; the boundary uses no randomness
	const points = [];
	for (let y = radius; y < height; y += spacing) {
		for (let x = radius; x < width; x += spacing) {
			points.push([Math.min(rn(x + jitter(), 2), width), Math.min(rn(y + jitter(), 2), height)]);
		}
	}
	const offset = rn(-1 * spacing);
	const bSpacing = spacing * 2;
	const w = width - offset * 2;
	const h = height - offset * 2;
	const numberX = Math.ceil(w / bSpacing) - 1;
	const numberY = Math.ceil(h / bSpacing) - 1;
	const boundary = [];
	for (let i = 0.5; i < numberX; i++) {
		const x = Math.ceil((w * i) / numberX + offset);
		boundary.push([x, offset], [x, h + offset]);
	}
	for (let i = 0.5; i < numberY; i++) {
		const y = Math.ceil((h * i) / numberY + offset);
		boundary.push([offset, y], [w + offset, y]);
	}
	const delaunay = Delaunator.from(points.concat(boundary));
	return {
		seed, width, height, cellsDesired, spacing,
		cellsX: Math.floor((width + 0.5 * spacing - 1e-10) / spacing),
		cellsY: Math.floor((height + 0.5 * spacing - 1e-10) / spacing),
		points, boundary,
		triangles: Array.from(delaunay.triangles), halfedges: Array.from(delaunay.halfedges), hull: Array.from(delaunay.hull)
	};
}
const grids = [grid("kaz-1", 100, 60, 24), grid("", 100, 60, 24), grid("日本語", 120, 80, 48)];
writeFileSync(join(outDir, "grid.json"), JSON.stringify({ ...meta, grids }, null, 1));
console.log("wrote", outDir, meta, grids.map(g => [g.seed, g.points.length, g.boundary.length, g.triangles.length / 3]));
