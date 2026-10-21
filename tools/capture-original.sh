#!/bin/sh
# One command to capture the fixtures that come from the ORIGINAL's own code (see tools/original-bundle/README.md).
#
#   tools/capture-original.sh <clone of Azgaar/Fantasy-Map-Generator, npm installed> <fixtures dir> [--replace | --check]
#
# It bundles the original's grid-generator with the original's own bundler in a temporary folder, runs the capture
# script into a temporary destination, writes provenance.json, and compares the result with what is already in the
# fixtures dir. Committed fixtures are replaced only when --replace is given. With --check the script exits nonzero if
# the fixtures differ, and replaces nothing. A reference checkout with uncommitted changes to tracked files is refused,
# because a commit hash alone would not identify modified source.
set -eu

clone=$(cd "${1:?clone path}" && pwd)
fixtures=${2:?fixtures dir}
mode=${3:-}
case "$mode" in ""|--replace|--check) ;; *) echo "unknown option $mode" >&2; exit 2 ;; esac
here=$(cd "$(dirname "$0")" && pwd)
scratch=$(mktemp -d)
out=$scratch/out
mkdir -p "$out"
trap 'rm -rf "$scratch"' EXIT

if [ -n "$(git -C "$clone" status --porcelain --untracked-files=no)" ]; then
	echo "the reference checkout has uncommitted changes to tracked files; refusing (a commit hash would not identify it)" >&2
	exit 1
fi
sed "s|__CLONE__|$clone|g; s|__SCRATCH__|$scratch|g" "$here/original-bundle/utils-stub.template.ts" > "$scratch/utils-stub.ts"
sed "s|__CLONE__|$clone|g; s|__SCRATCH__|$scratch|g" "$here/original-bundle/rolldown.config.template.mjs" > "$scratch/rolldown.config.mjs"
printf 'import "%s/src/generators/grid-generator.ts";\nimport "%s/src/generators/heightmap-generator.ts";\nimport "%s/src/generators/features-generator.ts";\nimport { heightmapTemplates } from "%s/src/data/heightmap-templates.ts";\nglobalThis.__heightmapTemplates = heightmapTemplates;\nimport { Coastline } from "%s/src/generators/coastline-generator.ts";\nglobalThis.__coastline = Coastline;\nimport "%s/src/generators/coordinates.ts";\nimport "%s/src/generators/temperature-generator.ts";\nimport "%s/src/generators/precipitation-generator.ts";\nimport "%s/src/generators/pack-generator.ts";\n' "$clone" "$clone" "$clone" "$clone" "$clone" "$clone" "$clone" "$clone" "$clone" > "$scratch/entry.ts"
printf 'import "%s/src/generators/lakes.ts";\nimport { clipPoly } from "%s/src/utils/commonUtils.ts";\nglobalThis.__clipPoly = clipPoly;\nimport { connectVertices, meander, projectToNearestEdge } from "%s/src/utils/pathUtils.ts";\nglobalThis.__connectVertices = connectVertices;\nglobalThis.__meander = meander;\nglobalThis.__projectToNearestEdge = projectToNearestEdge;\nimport "%s/src/generators/river-generator.ts";\n' "$clone" "$clone" "$clone" "$clone" >> "$scratch/entry.ts"
(cd "$clone" && ./node_modules/.bin/rolldown -c "$scratch/rolldown.config.mjs")
node "$here/capture-original-grid.mjs" "$scratch/grid-bundle.mjs" "$out"
node "$here/capture-original-heights.mjs" "$scratch/grid-bundle.mjs" "$out" "$clone"
node "$here/capture-original-templates.mjs" "$scratch/grid-bundle.mjs" "$out"
node "$here/capture-original-features.mjs" "$scratch/grid-bundle.mjs" "$out"
node "$here/capture-original-lakes.mjs" "$scratch/grid-bundle.mjs" "$out"
node "$here/capture-original-coastline.mjs" "$scratch/grid-bundle.mjs" "$out"
node "$here/capture-original-coordinates.mjs" "$scratch/grid-bundle.mjs" "$out"
node "$here/capture-original-temperature.mjs" "$scratch/grid-bundle.mjs" "$out"
node "$here/capture-original-precipitation.mjs" "$scratch/grid-bundle.mjs" "$out"
node "$here/capture-original-pack.mjs" "$scratch/grid-bundle.mjs" "$out"
node "$here/capture-original-markup-pack.mjs" "$scratch/grid-bundle.mjs" "$out"
node "$here/capture-original-clip.mjs" "$scratch/grid-bundle.mjs" "$out"
node "$here/capture-original-lake-helpers.mjs" "$scratch/grid-bundle.mjs" "$out"
node "$here/capture-original-depressions.mjs" "$scratch/grid-bundle.mjs" "$out"
node "$here/capture-original-meander.mjs" "$scratch/grid-bundle.mjs" "$out"
node "$here/capture-original-rivers.mjs" "$scratch/grid-bundle.mjs" "$out"
node "$here/capture-original-river-paths.mjs" "$scratch/grid-bundle.mjs" "$out"

node - "$clone" "$out" "$here" <<'JS'
const { execFileSync } = require("node:child_process");
const { readFileSync, writeFileSync } = require("node:fs");
const { join, resolve } = require("node:path");
const [clone, out, here] = process.argv.slice(2);
const version = name => JSON.parse(readFileSync(join(clone, "node_modules", name, "package.json"), "utf8")).version;
const sha = file => execFileSync("shasum", ["-a", "256", file]).toString().split(" ")[0];
const tool = name => sha(resolve(here, name));
writeFileSync(join(out, "provenance.json"), JSON.stringify({
	originalCommit: execFileSync("git", ["-C", clone, "rev-parse", "HEAD"]).toString().trim(),
	originalCheckoutClean: true,
	node: process.version,
	v8: process.versions.v8,
	arch: process.arch,
	platform: process.platform,
	rolldown: version("rolldown"),
	alea: version("alea"),
	d3Random: version("d3-random"),
	delaunator: version("delaunator"),
	lineclip: version("lineclip"),
	robustPredicates: version("robust-predicates"),
	procedure: {
		"tools/capture-original.sh": tool("capture-original.sh"),
		"tools/capture-original-grid.mjs": tool("capture-original-grid.mjs"),
		"tools/capture-original-heights.mjs": tool("capture-original-heights.mjs"),
		"tools/capture-original-templates.mjs": tool("capture-original-templates.mjs"),
		"tools/capture-original-features.mjs": tool("capture-original-features.mjs"),
		"tools/capture-original-lakes.mjs": tool("capture-original-lakes.mjs"),
		"tools/capture-original-coastline.mjs": tool("capture-original-coastline.mjs"),
		"tools/capture-original-coordinates.mjs": tool("capture-original-coordinates.mjs"),
		"tools/capture-original-temperature.mjs": tool("capture-original-temperature.mjs"),
		"tools/capture-original-precipitation.mjs": tool("capture-original-precipitation.mjs"),
		"tools/capture-original-pack.mjs": tool("capture-original-pack.mjs"),
		"tools/capture-original-markup-pack.mjs": tool("capture-original-markup-pack.mjs"),
		"tools/capture-original-clip.mjs": tool("capture-original-clip.mjs"),
		"tools/capture-original-lake-helpers.mjs": tool("capture-original-lake-helpers.mjs"),
		"tools/capture-original-depressions.mjs": tool("capture-original-depressions.mjs"),
		"tools/capture-original-meander.mjs": tool("capture-original-meander.mjs"),
		"tools/capture-original-rivers.mjs": tool("capture-original-rivers.mjs"),
		"tools/capture-original-river-paths.mjs": tool("capture-original-river-paths.mjs"),
		"tools/original-bundle/rolldown.config.template.mjs": tool("original-bundle/rolldown.config.template.mjs"),
		"tools/original-bundle/utils-stub.template.ts": tool("original-bundle/utils-stub.template.ts")
	},
	gridFixtureSha256: sha(join(out, "grid-original.json")),
	heightsFixtureSha256: sha(join(out, "heights-original.json")),
	templatesFixtureSha256: sha(join(out, "templates-original.json")),
	featuresFixtureSha256: sha(join(out, "features-original.json")),
	lakesFixtureSha256: sha(join(out, "lakes-original.json")),
	coastlineFixtureSha256: sha(join(out, "coastline-original.json")),
	coordinatesFixtureSha256: sha(join(out, "coordinates-original.json")),
	temperatureFixtureSha256: sha(join(out, "temperature-original.json")),
	precipitationFixtureSha256: sha(join(out, "precipitation-original.json")),
	packFixtureSha256: sha(join(out, "pack-original.json")),
	markupPackFixtureSha256: sha(join(out, "markup-pack-original.json")),
	clipFixtureSha256: sha(join(out, "clip-original.json")),
	lakeHelpersFixtureSha256: sha(join(out, "lake-helpers-original.json")),
	depressionsFixtureSha256: sha(join(out, "depressions-original.json")),
	meanderFixtureSha256: sha(join(out, "meander-original.json")),
	riversFixtureSha256: sha(join(out, "rivers-original.json")),
	riverPathsFixtureSha256: sha(join(out, "river-paths-original.json"))
}, null, 1));
JS

# The fixtures were captured in one environment (the math functions of the engine, and the compiler's choices inside it, are part of what the
# river geometry compares with). A different environment must not silently replace them: report it, and stop unless it is allowed on purpose.
if [ -f "$fixtures/provenance.json" ]; then
	env_diff=$(node - "$out/provenance.json" "$fixtures/provenance.json" <<'JS'
const { readFileSync } = require("node:fs");
const [now, was] = process.argv.slice(2).map(f => JSON.parse(readFileSync(f, "utf8")));
const keys = ["node", "v8", "arch", "platform"];
const diff = keys.filter(k => k in was && was[k] !== now[k]).map(k => `${k}: committed ${was[k]}, now ${now[k]}`);
console.log(diff.join("; "));
JS
)
	if [ -n "$env_diff" ] && [ "${ALLOW_ENVIRONMENT_CHANGE:-}" != 1 ]; then
		echo "PROVENANCE MISMATCH: the capture environment differs from the committed fixtures' ($env_diff)." >&2
		echo "Nothing was compared or replaced. Set ALLOW_ENVIRONMENT_CHANGE=1 to capture here on purpose (the fixtures would then pin this environment)." >&2
		exit 1
	fi
fi

same=yes
for name in grid-original.json heights-original.json templates-original.json features-original.json lakes-original.json coastline-original.json coordinates-original.json temperature-original.json precipitation-original.json pack-original.json markup-pack-original.json clip-original.json lake-helpers-original.json depressions-original.json meander-original.json rivers-original.json river-paths-original.json; do
	if [ -f "$fixtures/$name" ] && cmp -s "$out/$name" "$fixtures/$name"; then
		echo "$name: identical to the committed fixture"
	else
		same=no
		echo "$name: DIFFERENT from (or missing in) $fixtures"
	fi
done
case "$mode" in
--replace)
	cp "$out/grid-original.json" "$out/heights-original.json" "$out/templates-original.json" "$out/features-original.json" "$out/lakes-original.json" "$out/coastline-original.json" "$out/coordinates-original.json" "$out/temperature-original.json" "$out/precipitation-original.json" "$out/pack-original.json" "$out/markup-pack-original.json" "$out/clip-original.json" "$out/lake-helpers-original.json" "$out/depressions-original.json" "$out/meander-original.json" "$out/rivers-original.json" "$out/river-paths-original.json" "$out/provenance.json" "$fixtures/"
	echo "replaced fixtures in $fixtures"
	;;
--check)
	if [ "$same" = yes ]; then echo "check passed"; else echo "check FAILED" >&2; exit 1; fi
	;;
*)
	echo "not replaced (pass --replace to copy the fixtures and provenance.json into $fixtures, or --check to fail when they differ)"
	;;
esac
cat "$out/provenance.json"
