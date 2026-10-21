// Runs the ORIGINAL's own Grid.generate (bundled as described in tools/original-bundle/README.md) and saves what it
// returns, as a fixture for the port. Usage:
//   node tools/capture-original-grid.mjs <grid-bundle.mjs> <out dir>
import { createHash } from "node:crypto";
import { writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const [bundlePath, outDir] = process.argv.slice(2);
if (!bundlePath || !outDir) throw new Error("usage: capture-original-grid.mjs <grid-bundle.mjs> <out dir>");

// stand-ins for the browser globals the original's modules touch when they load; no DOM is used
globalThis.window = globalThis;
globalThis.TIME = false;
globalThis.document = { readyState: "loading", addEventListener() {}, documentElement: {} };
globalThis.options = { map: { seed: "", graph: { width: 1280, height: 800, points: 10000 } }, generation: {} };
await import(pathToFileURL(resolve(bundlePath)).href);

function capture(seed, width, height, cellsDesired, { withCells }) {
	const g = globalThis.Grid.generate(seed, width, height, cellsDesired);
	const arr = x => Array.from(x, y => (y instanceof Object && "length" in y ? Array.from(y) : y));
	const out = {
		// a hash of the integer structure of the original's cells and vertices (neighbours, corners, border flags and the
		// vertices' adjacency), so large grids can be compared without storing every cell
		cellStructureSha256: createHash("sha256").update(JSON.stringify([arr(g.cells.c), arr(g.cells.v), arr(g.cells.b), arr(g.vertices.v), arr(g.vertices.c)])).digest("hex"),
		vertexCount: g.vertices.p.length,
		// every vertex coordinate, as one digest: SHA-256 over the little-endian IEEE-754 bytes of x then y of each vertex in
		// order, so the large grids' coordinates are compared exactly without storing them as text
		vertexPointsSha256: (() => {
			const bytes = Buffer.alloc(g.vertices.p.length * 16);
			g.vertices.p.forEach(([x, y], i) => {
				if (!Number.isFinite(x) || !Number.isFinite(y)) throw new Error("a vertex coordinate is not finite");
				bytes.writeDoubleLE(x, i * 16);
				bytes.writeDoubleLE(y, i * 16 + 8);
			});
			return createHash("sha256").update(bytes).digest("hex");
		})(),
		vertexPointsFirst20: g.vertices.p.slice(0, 20),
		seed, width, height, cellsDesired,
		spacing: g.spacing, cellsX: g.cellsX, cellsY: g.cellsY,
		points: g.points, boundary: g.boundary
	};
	if (withCells) {
		// the original's own Voronoi cells and vertices, for step 3 (small grids only)
		out.cellNeighbours = g.cells.c.map(c => Array.from(c));
		out.cellVertices = g.cells.v.map(v => Array.from(v));
		out.cellBorder = Array.from(g.cells.b);
		out.vertexPoints = g.vertices.p;
	}
	return out;
}

const grids = [
	capture("kaz-1", 100, 60, 24, { withCells: true }),
	capture("", 100, 60, 24, { withCells: true }),
	capture("日本語", 120, 80, 48, { withCells: true }),
	capture("kaz-1", 1280, 800, 10000, { withCells: false }), // the original's default map
	capture("é", 1280, 800, 1000, { withCells: false }),
	capture("é", 1280, 800, 1000, { withCells: false }),
	// odd aspect ratios, a different geometry from the usual 16:10 (small enough to keep the original's cells too)
	capture("wide", 1000, 90, 300, { withCells: true }),
	capture("tall", 90, 1000, 300, { withCells: true })
];
writeFileSync(join(outDir, "grid-original.json"), JSON.stringify({
	note: "Produced by running the original's own Grid.generate; see tools/original-bundle/README.md",
	grids
}));
console.log("wrote", outDir, grids.map(g => [g.seed, g.points.length, g.boundary.length]));
