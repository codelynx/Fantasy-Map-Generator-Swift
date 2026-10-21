// Runs the ORIGINAL's own HeightmapGenerator (bundled as described in tools/original-bundle/README.md) on grids made by
// the original's own Grid.generate, one step at a time, and saves the heights after every step. Usage:
//   node tools/capture-original-heights.mjs <bundle.mjs> <out dir> <clone path>
// The PRNG is reset exactly as the original's `HeightmapGenerator.generate` does (`Math.random = Alea(seed)`), and each
// step goes through the original's own `addStep`, so the comparison can say which step first differs.
import { createRequire } from "node:module";
import { writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";

const [bundlePath, outDir, clonePath] = process.argv.slice(2);
if (!bundlePath || !outDir || !clonePath) throw new Error("usage: capture-original-heights.mjs <bundle.mjs> <out dir> <clone path>");
const Alea = createRequire(join(resolve(clonePath), "package.json"))("alea");

globalThis.window = globalThis;
globalThis.TIME = false;
globalThis.document = { readyState: "loading", addEventListener() {}, documentElement: {} };
globalThis.options = { map: { seed: "", graph: { width: 1280, height: 800, points: 10000 } }, generation: {} };
await import(pathToFileURL(resolve(bundlePath)).href);

function capture(seed, width, height, cellsDesired, steps) {
	const graph = globalThis.Grid.generate(seed, width, height, cellsDesired);
	Math.random = Alea(seed); // the reset HeightmapGenerator.generate performs before it runs a template
	const generator = globalThis.HeightmapGenerator;
	generator.setGraph(graph, { width, height, points: cellsDesired });
	const afterEach = [];
	const randomStateAfterEach = [];
	for (const line of steps) {
		const elements = line.trim().split(" ");
		generator.addStep(...elements);
		afterEach.push(Array.from(generator.heights));
		randomStateAfterEach.push(Math.random.exportState()); // equal heights can hide different random consumption
	}
	return { seed, width, height, cellsDesired, blobPower: generator.blobPower, linePower: generator.linePower, steps, afterEach, randomStateAfterEach };
}

const hills = ["Hill 1 90-100 44-56 40-60", "Hill 5-6 20-30 25-55 45-55", "Hill 3 35-45 25-30 20-75"];
const runs = [
	capture("kaz-1", 1280, 800, 10000, [hills[0], "Add 7 all 0 0", "Multiply 0.8 land 0 0", hills[1], "Add -5 20-100 0 0", "Multiply 1.2 all 0 0", hills[2]]),
	capture("kaz-1", 1280, 800, 2000, [hills[0], hills[1], "Add 11 all 0 0", hills[2]]), // a density step with its own blob power
	capture("kaz-1", 1280, 800, 1000, [hills[0], hills[2]]), // another table entry
	capture("日本語", 100, 60, 24, ["Hill 1 90-100 44-56 40-60", "Hill 2-3 20-40 10-90 10-90", "Add 7 all 0 0", "Multiply 0.8 land 0 0"]), // not in the tables: the fallback power
	capture("", 1280, 800, 10000, [hills[1], "Multiply 0.5 20-60 0 0", "Add 30 land 0 0"]),
	capture("wide", 1000, 90, 300, [hills[0], "Hill 4 30-50 5-95 5-95", "Add 3 all 0 0"]),
	// stage 2: Pit, Smooth, Mask and Invert, in the original's own template syntax and a few variations
	capture("kaz-1", 1280, 800, 10000, [hills[0], hills[1], "Pit 3-5 10-30 15-85 20-80", "Smooth 2 0 0 0", "Smooth 1 0 0 0", "Smooth 3 0 0 0", "Mask 3 0 0 0", "Pit 12-20 30-40 15-85 20-80"]),
	capture("kaz-1", 1280, 800, 10000, [hills[1], "Mask -2 0 0 0", "Mask 0 0 0 0", "Mask -1.5 0 0 0", "Mask 4 0 0 0", "Invert 1 x 0 0", "Invert 1 y 0 0", "Invert 1 both 0 0", "Invert 0 x 0 0"]),
	capture("kaz-1", 1280, 800, 2000, [hills[0], hills[2], "Invert 0.4 both 0 0", "Invert 0.25 x 0 0", "Invert 0.5 y 0 0", "Pit 5-6 20-30 10-90 10-90", "Smooth 2 0 0 0", "Mask 3 0 0 0"]),
	capture("日本語", 100, 60, 24, ["Hill 2 60-80 20-80 20-80", "Pit 2 20-40 20-80 20-80", "Smooth 2 0 0 0", "Mask 4 0 0 0", "Invert 1 both 0 0", "Smooth 1 0 0 0"]),
	capture("wide", 1000, 90, 300, [hills[0], "Pit 3-4 10-20 15-85 20-80", "Smooth 3 0 0 0", "Mask -1.5 0 0 0", "Invert 1 x 0 0", "Invert 1 y 0 0"]),
	capture("tall", 90, 1000, 300, [hills[1], "Mask 3 0 0 0", "Invert 1 y 0 0", "Smooth 2 0 0 0", "Pit 2 10-30 20-80 20-80"]),
	// stage 3: Range, Trough and Strait, in the original's own template syntax
	capture("kaz-1", 1280, 800, 10000, [hills[0], "Range 1.5 30-55 45-55 40-60", "Trough 2-3 20-30 20-30 20-30", "Range 3 70 15-85 20-80", "Range 0-3 30-60 80-90 20-80", "Trough 10 20-30 5-95 5-95", "Smooth 2 0 0 0"]),
	capture("kaz-1", 1280, 800, 10000, [hills[1], "Strait 2 vertical 0 0", "Strait 2 horizontal 0 0", "Strait 1 vertical 0 0", "Strait 3-7 vertical 0 0", "Strait 0.5 horizontal 0 0"]),
	capture("kaz-1", 1280, 800, 2000, ["Range 4-6 30-80 0-100 0-10", "Trough 3-6 40-50 0-100 0-10", "Range 1-2 30-60 5-15 25-75", "Strait 2 vertical 0 0", "Trough 3-4 15-20 15-85 20-80", "Smooth 3 0 0 0"]),
	capture("kaz-1", 1280, 800, 1000, [hills[0], "Range 2-3 40-60 20-80 20-80", "Trough 4-8 15-30 0-30 0-20", "Strait 2 horizontal 0 0", "Range 5-6 30-40 10-90 35-65"]),
	capture("日本語", 200, 120, 100, ["Hill 2 60-80 20-80 20-80", "Range 1 40-50 45-55 45-55", "Trough 2 20-30 15-85 20-30", "Strait 1 vertical 0 0", "Range 1.5 30-40 15-85 30-40"]),
	capture("wide", 1000, 90, 300, ["Range 2 40-60 20-80 20-80", "Trough 2-3 20-30 20-30 20-30", "Strait 1 horizontal 0 0", "Strait 1 vertical 0 0"]),
	capture("tall", 90, 1000, 300, ["Hill 3 40-60 30-70 30-70", "Range 1-2 30-60 80-95 25-75", "Trough 3-4 5-10 45-55 45-55", "Strait 1 vertical 0 0", "Strait 1 horizontal 0 0"]),
	capture("", 1280, 800, 10000, [hills[0], "Range 1 40-50 45-55 45-55", "Strait 1-2 horizontal 0 0", "Trough 5-6 10-25 5-95 5-95", "Invert 0.4 both 0 0", "Range 5-7 30-40 10-90 20-80"])
];
writeFileSync(join(outDir, "heights-original.json"), JSON.stringify({
	note: "Produced by running the original's own HeightmapGenerator one step at a time; see tools/capture-original-heights.mjs",
	runs
}));
console.log("wrote", outDir, runs.map(r => [r.seed, r.cellsDesired, r.steps.length, r.blobPower, r.linePower]));
