// Construit web/dist de façon déterministe : copie la page et la bibliothèque
// « marked » (UMD), sans horodatage ni dépendance native.
import { copyFileSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { createRequire } from "node:module";

// « marked » n'exporte pas lib/marked.umd.js : on le localise via package.json.
const require = createRequire(import.meta.url);
const markedUmd = join(dirname(require.resolve("marked/package.json")), "lib/marked.umd.js");

mkdirSync("dist", { recursive: true });
copyFileSync(markedUmd, "dist/marked.umd.js");
const page = readFileSync("src/index.html", "utf8");
const readme = readFileSync("src/README.md", "utf8");
writeFileSync("dist/index.html", page.replace("__README__", JSON.stringify(readme)));
