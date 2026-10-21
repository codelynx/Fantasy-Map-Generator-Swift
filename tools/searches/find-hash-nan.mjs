// Searches random small integer point sets for one where a point equals the seed triangle's circumcenter (which would make Delaunator's hash key NaN). 3,000,000 sets were tried and none was found; the result is why the path is documented as guarded and not known to be reachable.
// Usage: node tools/searches/find-hash-nan.mjs <clone of the original, npm installed>
import { resolve } from "node:path";
import { createRequire } from "node:module";
const require = createRequire(resolve(process.argv[2], "package.json"));
const D = require("delaunator"); const Delaunator = D.default ?? D;
let found = [];
let seed = 12345; const rnd = () => (seed = (seed * 1664525 + 1013904223) >>> 0) / 4294967296;
for (let trial = 0; trial < 3000000 && found.length < 5; trial++) {
	const n = 5 + Math.floor(rnd() * 6);
	const pts = [];
	for (let i = 0; i < n; i++) pts.push([Math.floor(rnd() * 13), Math.floor(rnd() * 13)]);
	let d;
	try { d = Delaunator.from(pts); } catch (e) { continue; }
	if (d.triangles.length === 0) continue;
	if (pts.some(p => p[0] === d._cx && p[1] === d._cy)) found.push({ pts, cx: d._cx, cy: d._cy, tri: Array.from(d.triangles), hull: Array.from(d.hull) });
}
console.log(JSON.stringify(found.slice(0, 3)));
console.log(found.length);
