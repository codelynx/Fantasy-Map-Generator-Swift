// Searches nearly collinear 5-point sets at scales from 1 to 1e9 for a Delaunator triangulation with a triangle whose circumcenter, by the original's voronoi.ts formula, is not finite. It found the case now used in GeometryTests (near 1.9e8).
// Usage: node tools/searches/find-nonfinite-circumcenter.mjs <clone of the original, npm installed>
import { resolve } from "node:path";
import { createRequire } from "node:module";
const require = createRequire(resolve(process.argv[2], "package.json"));
const D = require("delaunator"); const Delaunator = D.default ?? D;
function cc(a,b,c){const ad=a[0]*a[0]+a[1]*a[1],bd=b[0]*b[0]+b[1]*b[1],cd=c[0]*c[0]+c[1]*c[1];const Dd=2*(a[0]*(b[1]-c[1])+b[0]*(c[1]-a[1])+c[0]*(a[1]-b[1]));return [(1/Dd)*(ad*(b[1]-c[1])+bd*(c[1]-a[1])+cd*(a[1]-b[1])),(1/Dd)*(ad*(c[0]-b[0])+bd*(a[0]-c[0])+cd*(b[0]-a[0]))];}
let seed=7; const rnd=()=>(seed=(seed*1664525+1013904223)>>>0)/4294967296;
let hits=[];
for(let t=0;t<300000&&hits.length<3;t++){
  const s=10**Math.floor(rnd()*10);
  const base=[rnd()*s,rnd()*s]; const dir=[rnd()-0.5,rnd()-0.5];
  const pts=[];
  for(let i=0;i<5;i++){const k=rnd()*2; pts.push([base[0]+k*dir[0]*s*1e-3+(rnd()<0.3?(rnd()-0.5)*1e-9*s:0), base[1]+k*dir[1]*s*1e-3+(rnd()<0.3?(rnd()-0.5)*1e-9*s:0)]);}
  const d=Delaunator.from(pts);
  for(let i=0;i<d.triangles.length;i+=3){const c=cc(pts[d.triangles[i]],pts[d.triangles[i+1]],pts[d.triangles[i+2]]); if(!Number.isFinite(c[0])||!Number.isFinite(c[1])){hits.push({pts,tri:Array.from(d.triangles)});break;}}
}
console.log(hits.length, JSON.stringify(hits[0]));
